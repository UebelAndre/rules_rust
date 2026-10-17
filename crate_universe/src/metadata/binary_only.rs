//! Completion of `cargo metadata` output with the packages Cargo drops because
//! they have no library target.
//!
//! A dependency on a package which only ships binaries resolves like any other,
//! so it is in `Cargo.lock`, but `cargo metadata` warns that it is "missing a lib
//! target" and omits it, along with everything only it depends on, from both
//! `packages` and `resolve`. Cargo cannot build such a dependency without
//! `-Zbindeps`; `cargo-bazel` can, rendering the package like any other with its
//! binaries available as `rust_binary` targets. This module puts the dropped
//! packages back, reading their manifests from the sources `cargo fetch`
//! downloads for every package of the lockfile.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use cargo_lock::Lockfile;
use semver::VersionReq;
use serde_json::{json, Value};

use crate::metadata::Cargo;
use crate::splicing::cargo_config::CargoConfig;
use crate::splicing::registry_index_url;
use crate::utils::sanitize_module_name;

/// `cargo metadata --locked` for the workspace of `manifest_path`, completed
/// with the binary-only packages its `Cargo.lock` holds.
///
/// With `all_features`, every feature of every workspace member is enabled, as
/// `cargo metadata --all-features` does.
pub(crate) fn locked_metadata(
    cargo: &Cargo,
    manifest_path: &Path,
    all_features: bool,
) -> Result<String> {
    let mut options = vec!["--locked".to_owned()];
    if all_features {
        options.push("--all-features".to_owned());
    }
    let output = cargo
        .metadata_command_with_options(manifest_path, options)?
        .cargo_command()
        .output()
        .with_context(|| {
            format!(
                "Error spawning cargo in child process to compute metadata for manifest '{}'",
                manifest_path.display()
            )
        })?;
    if !output.status.success() {
        tracing::error!("{}", String::from_utf8_lossy(&output.stderr));
        bail!("Failed to run cargo metadata: {}", output.status);
    }
    let mut metadata: Value = serde_json::from_slice(&output.stdout)
        .context("`cargo metadata` produced output which was not valid JSON")?;

    let manifest_dir = manifest_path
        .parent()
        .expect("manifest paths always have a parent directory");
    let lockfile_path = manifest_dir.join("Cargo.lock");
    let lockfile = Lockfile::load(&lockfile_path)
        .with_context(|| format!("Failed to load lockfile '{}'", lockfile_path.display()))?;

    Completion::new(cargo, manifest_path, &lockfile, all_features)?.complete(&mut metadata)?;

    serde_json::to_string(&metadata).context("Failed to serialize metadata")
}

/// A package as `Cargo.lock` identifies it.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct LockKey {
    name: String,
    version: String,
}

impl LockKey {
    fn of_lock(pkg: &cargo_lock::Package) -> Self {
        Self {
            name: pkg.name.as_str().to_owned(),
            version: pkg.version.to_string(),
        }
    }

    fn of_package(pkg: &Value) -> Self {
        Self {
            name: text(&pkg["name"]).to_owned(),
            version: text(&pkg["version"]).to_owned(),
        }
    }
}

/// What dependents ask of a package: the features they enable on it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Request {
    features: BTreeSet<String>,
    default_features: bool,
}

impl Request {
    fn merge(&mut self, other: &Request) {
        self.features.extend(other.features.iter().cloned());
        self.default_features |= other.default_features;
    }
}

/// One declared dependency which Cargo would build, resolved to a lockfile
/// package.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Edge {
    to: LockKey,
    /// The name the dependency is used under, when renamed.
    rename: Option<String>,
    /// `resolve.nodes[].deps[].dep_kinds[].kind`.
    kind: Value,
    /// `resolve.nodes[].deps[].dep_kinds[].target`.
    target: Value,
    request: Request,
}

/// What a package's enabled features imply.
#[derive(Debug, Default)]
struct Activation {
    /// The enabled features.
    features: BTreeSet<String>,
    /// The dependencies they enable, by the name used in features. Only
    /// meaningful for optional dependencies; a `name/feature` entry names a
    /// dependency which may or may not be optional.
    optional_deps: BTreeSet<String>,
    /// The features they enable on dependencies, by the name used in features.
    dep_features: BTreeMap<String, BTreeSet<String>>,
}

/// Enable `request` on a package with the given `[features]` table, following
/// Cargo's feature syntax: `feat`, `dep:name`, `name/feat` and `name?/feat`.
fn activate(table: &BTreeMap<String, Vec<String>>, request: &Request) -> Activation {
    let mut activation = Activation::default();
    let mut pending: Vec<String> = request.features.iter().cloned().collect();
    if request.default_features && table.contains_key("default") {
        pending.push("default".to_owned());
    }

    while let Some(feature) = pending.pop() {
        let Some(enables) = table.get(&feature) else {
            // Not a feature: an optional dependency named directly.
            activation.optional_deps.insert(feature);
            continue;
        };
        if !activation.features.insert(feature) {
            continue;
        }
        for value in enables {
            if let Some(dep) = value.strip_prefix("dep:") {
                activation.optional_deps.insert(dep.to_owned());
            } else if let Some((dep, dep_feature)) = value.split_once('/') {
                let (dep, weak) = match dep.strip_suffix('?') {
                    Some(dep) => (dep, true),
                    None => (dep, false),
                };
                if !weak {
                    activation.optional_deps.insert(dep.to_owned());
                }
                activation
                    .dep_features
                    .entry(dep.to_owned())
                    .or_default()
                    .insert(dep_feature.to_owned());
            } else {
                pending.push(value.clone());
            }
        }
    }

    activation
}

/// The `[features]` table of a package.
fn feature_table(pkg: &Value) -> BTreeMap<String, Vec<String>> {
    pkg["features"]
        .as_object()
        .map(|table| {
            table
                .iter()
                .map(|(feature, enables)| {
                    let enables = enables
                        .as_array()
                        .map(|values| values.iter().map(|v| text(v).to_owned()).collect())
                        .unwrap_or_default();
                    (feature.clone(), enables)
                })
                .collect()
        })
        .unwrap_or_default()
}

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or_default()
}

/// The name a dependency on `pkg` is used under in the resolve graph: its
/// library target as a module name, or the rename. A package without a
/// library target has nothing to use, so Cargo leaves the name empty, as it
/// does for artifact dependencies; the feature resolver relies on that.
fn extern_name(pkg: &Value, rename: Option<&str>) -> String {
    let lib_target = pkg["targets"].as_array().and_then(|targets| {
        targets.iter().find(|target| {
            target["kind"].as_array().is_some_and(|kinds| {
                kinds.iter().any(|kind| {
                    matches!(
                        text(kind),
                        "lib" | "rlib" | "dylib" | "cdylib" | "staticlib" | "proc-macro"
                    )
                })
            })
        })
    });
    match (lib_target, rename) {
        (None, _) => String::new(),
        (Some(_), Some(rename)) => sanitize_module_name(rename),
        (Some(target), None) => sanitize_module_name(text(&target["name"])),
    }
}

struct Completion<'a> {
    cargo: &'a Cargo,
    manifest_path: &'a Path,
    cargo_home: PathBuf,
    cargo_config: Option<CargoConfig>,
    locked: BTreeMap<LockKey, &'a cargo_lock::Package>,
    all_features: bool,
    /// Whether `cargo fetch` has been run to download missing sources.
    fetched: bool,
}

impl<'a> Completion<'a> {
    fn new(
        cargo: &'a Cargo,
        manifest_path: &'a Path,
        lockfile: &'a Lockfile,
        all_features: bool,
    ) -> Result<Self> {
        let manifest_dir = manifest_path
            .parent()
            .expect("manifest paths always have a parent directory");
        // Note that this path must match the one defined in `splicing::setup_cargo_config`
        let config_path = manifest_dir.join(".cargo").join("config.toml");
        let cargo_config = if config_path.exists() {
            Some(CargoConfig::try_from_path(&config_path)?)
        } else {
            None
        };
        Ok(Self {
            cargo,
            manifest_path,
            cargo_home: cargo.cargo_home()?,
            cargo_config,
            locked: lockfile
                .packages
                .iter()
                .map(|pkg| (LockKey::of_lock(pkg), pkg))
                .collect(),
            all_features,
            fetched: false,
        })
    }

    /// Add the dropped packages, and the edges to them, to `metadata`.
    fn complete(mut self, metadata: &mut Value) -> Result<()> {
        let members: BTreeSet<String> = metadata["workspace_members"]
            .as_array()
            .map(|ids| ids.iter().map(|id| text(id).to_owned()).collect())
            .unwrap_or_default();
        let packages = metadata["packages"]
            .as_array()
            .cloned()
            .context("`cargo metadata` output has no `packages`")?;
        let nodes: BTreeMap<String, Value> = metadata["resolve"]["nodes"]
            .as_array()
            .context("`cargo metadata` output has no `resolve`")?
            .iter()
            .map(|node| (text(&node["id"]).to_owned(), node.clone()))
            .collect();
        let present: BTreeMap<LockKey, Value> = packages
            .iter()
            .map(|pkg| (LockKey::of_package(pkg), pkg.clone()))
            .collect();

        // Edges from the packages Cargo kept to the ones it dropped. A kept
        // package's node tells which of its features are enabled, so which of
        // its optional dependencies Cargo would have followed.
        let mut from_present: BTreeMap<String, Vec<Edge>> = BTreeMap::new();
        for pkg in &packages {
            let id = text(&pkg["id"]);
            let Some(node) = nodes.get(id) else { continue };
            let request = Request {
                features: node["features"]
                    .as_array()
                    .map(|f| f.iter().map(|v| text(v).to_owned()).collect())
                    .unwrap_or_default(),
                default_features: false,
            };
            let edges: Vec<Edge> = self
                .edges_of(pkg, &request, members.contains(id))
                .into_iter()
                .filter(|edge| !present.contains_key(&edge.to))
                .collect();
            if !edges.is_empty() {
                from_present.insert(id.to_owned(), edges);
            }
        }
        if from_present.is_empty() {
            return Ok(());
        }

        // Recover the dropped packages, then the edges among them. A dropped
        // package's features depend on everything that depends on it, which
        // can include other dropped packages, so iterate to a fixed point.
        let mut dropped: BTreeMap<LockKey, Value> = BTreeMap::new();
        let mut from_dropped: BTreeMap<LockKey, Vec<Edge>> = BTreeMap::new();
        loop {
            let mut requests: BTreeMap<LockKey, Request> = BTreeMap::new();
            for edge in from_present.values().flatten() {
                requests
                    .entry(edge.to.clone())
                    .or_default()
                    .merge(&edge.request);
            }
            for edge in from_dropped.values().flatten() {
                if !present.contains_key(&edge.to) {
                    requests
                        .entry(edge.to.clone())
                        .or_default()
                        .merge(&edge.request);
                }
            }
            for key in requests.keys() {
                if !dropped.contains_key(key) {
                    let pkg = self.recover(key)?;
                    dropped.insert(key.clone(), pkg);
                }
            }

            let next: BTreeMap<LockKey, Vec<Edge>> = dropped
                .iter()
                .map(|(key, pkg)| {
                    let request = requests.get(key).cloned().unwrap_or_default();
                    (key.clone(), self.edges_of(pkg, &request, false))
                })
                .collect();
            let settled = next == from_dropped && next.keys().all(|key| dropped.contains_key(key));
            from_dropped = next;
            if settled {
                break;
            }
        }

        let package_of = |key: &LockKey| present.get(key).or_else(|| dropped.get(key));
        let node_deps = |edges: &[Edge]| -> (Vec<Value>, Vec<Value>) {
            let mut deps: BTreeMap<String, Value> = BTreeMap::new();
            for edge in edges {
                let Some(target) = package_of(&edge.to) else {
                    continue;
                };
                let id = text(&target["id"]).to_owned();
                let dep = deps.entry(id.clone()).or_insert_with(|| {
                    json!({
                        "name": extern_name(target, edge.rename.as_deref()),
                        "pkg": id,
                        "dep_kinds": [],
                    })
                });
                let kinds = dep["dep_kinds"].as_array_mut().expect("just created");
                let kind = json!({"kind": edge.kind, "target": edge.target});
                if !kinds.contains(&kind) {
                    kinds.push(kind);
                }
            }
            let dependencies = deps.keys().map(|id| json!(id)).collect();
            (dependencies, deps.into_values().collect())
        };

        // The dropped packages and their nodes.
        let mut new_packages = Vec::new();
        let mut new_nodes = Vec::new();
        for (key, pkg) in &dropped {
            let edges = &from_dropped[key];
            let request = from_present
                .values()
                .chain(from_dropped.values())
                .flatten()
                .filter(|edge| &edge.to == key)
                .fold(Request::default(), |mut request, edge| {
                    request.merge(&edge.request);
                    request
                });
            let activation = activate(&feature_table(pkg), &request);
            let (dependencies, deps) = node_deps(edges);
            new_nodes.push(json!({
                "id": pkg["id"],
                "dependencies": dependencies,
                "deps": deps,
                "features": activation.features,
            }));
            new_packages.push(pkg.clone());
        }

        let out_nodes = metadata["resolve"]["nodes"]
            .as_array_mut()
            .expect("checked above");

        // The edges Cargo dropped from the packages it kept.
        for node in out_nodes.iter_mut() {
            let Some(edges) = from_present.get(text(&node["id"])) else {
                continue;
            };
            let (dependencies, deps) = node_deps(edges);
            node["dependencies"]
                .as_array_mut()
                .context("resolve nodes have a `dependencies` list")?
                .extend(dependencies);
            node["deps"]
                .as_array_mut()
                .context("resolve nodes have a `deps` list")?
                .extend(deps);
        }
        out_nodes.extend(new_nodes);
        metadata["packages"]
            .as_array_mut()
            .expect("checked above")
            .extend(new_packages);

        Ok(())
    }

    /// The dependencies of `pkg` Cargo would build given `request`, resolved
    /// through the lockfile. Dev-dependencies count for workspace members only.
    fn edges_of(&self, pkg: &Value, request: &Request, include_dev: bool) -> Vec<Edge> {
        let Some(lock_pkg) = self.locked.get(&LockKey::of_package(pkg)) else {
            return Vec::new();
        };
        let activation = activate(&feature_table(pkg), request);
        let all_features = self.all_features && include_dev;

        let mut edges = Vec::new();
        for dep in pkg["dependencies"].as_array().into_iter().flatten() {
            let kind = dep["kind"].clone();
            if kind == "dev" && !include_dev {
                continue;
            }
            let name = text(&dep["name"]);
            let rename = dep["rename"].as_str().map(str::to_owned);
            let feature_name = rename.as_deref().unwrap_or(name);
            let optional = dep["optional"].as_bool().unwrap_or(false);
            if optional && !all_features && !activation.optional_deps.contains(feature_name) {
                continue;
            }
            let Ok(req) = VersionReq::parse(text(&dep["req"])) else {
                continue;
            };
            let Some(to) = lock_pkg
                .dependencies
                .iter()
                .find(|d| d.name.as_str() == name && req.matches(&d.version))
            else {
                continue;
            };
            let mut features: BTreeSet<String> = dep["features"]
                .as_array()
                .map(|f| f.iter().map(|v| text(v).to_owned()).collect())
                .unwrap_or_default();
            if let Some(more) = activation.dep_features.get(feature_name) {
                features.extend(more.iter().cloned());
            }
            edges.push(Edge {
                to: LockKey {
                    name: to.name.as_str().to_owned(),
                    version: to.version.to_string(),
                },
                rename,
                kind,
                target: dep["target"].clone(),
                request: Request {
                    features,
                    default_features: dep["uses_default_features"].as_bool().unwrap_or(true),
                },
            });
        }
        edges
    }

    /// The `packages[]` entry of a dropped package, from its downloaded source.
    fn recover(&mut self, key: &LockKey) -> Result<Value> {
        let lock_pkg = self.locked[key];
        let source = lock_pkg.source.as_ref().ok_or_else(|| {
            anyhow!(
                "`cargo metadata` did not resolve the path package {} {} and it cannot be recovered",
                key.name,
                key.version
            )
        })?;
        if !source.is_registry() {
            bail!(
                "The dependency {} {} has no library target and comes from {}. Only binary-only \
                 packages from registries are supported.",
                key.name,
                key.version,
                source
            );
        }

        let index_url = registry_index_url(
            self.cargo,
            self.cargo_config.as_ref(),
            source.kind(),
            source.url().as_str(),
        )?;
        let hash_kind = if self.cargo.uses_stable_registry_hash()? {
            crates_index::HashKind::Stable
        } else {
            crates_index::HashKind::Legacy
        };
        let (index_dir, _) = crates_index::local_path_and_canonical_url_with_hash_kind(
            &index_url,
            Some(&self.cargo_home),
            &hash_kind,
        )?;
        let source_dir = self
            .cargo_home
            .join("registry")
            .join("src")
            .join(
                index_dir
                    .file_name()
                    .context("registry index directories have names")?,
            )
            .join(format!("{}-{}", key.name, key.version));

        if !source_dir.exists() && !self.fetched {
            self.fetch()?;
        }
        if !source_dir.exists() {
            bail!(
                "The source of {} {} is not at {} after `cargo fetch`",
                key.name,
                key.version,
                source_dir.display()
            );
        }

        let manifest_path = source_dir.join("Cargo.toml");
        let output = self
            .cargo
            .metadata_command_with_options(
                &manifest_path,
                vec!["--no-deps".to_owned(), "--offline".to_owned()],
            )?
            .cargo_command()
            .output()
            .with_context(|| {
                format!(
                    "Error running cargo metadata for '{}'",
                    manifest_path.display()
                )
            })?;
        if !output.status.success() {
            tracing::error!("{}", String::from_utf8_lossy(&output.stderr));
            bail!(
                "Failed to run cargo metadata for '{}': {}",
                manifest_path.display(),
                output.status
            );
        }
        let metadata: Value = serde_json::from_slice(&output.stdout)
            .context("`cargo metadata` produced output which was not valid JSON")?;
        let mut pkg = metadata["packages"]
            .as_array()
            .and_then(|packages| packages.first())
            .cloned()
            .with_context(|| {
                format!(
                    "No package in the metadata of '{}'",
                    manifest_path.display()
                )
            })?;

        // Identify the package by its registry source rather than the path it
        // was read from, as Cargo would have.
        pkg["source"] = json!(source.to_string());
        pkg["id"] = json!(format!("{}#{}@{}", source, key.name, key.version));
        Ok(pkg)
    }

    /// Download the sources of every package in the lockfile.
    fn fetch(&mut self) -> Result<()> {
        self.fetched = true;
        let manifest_dir = self
            .manifest_path
            .parent()
            .expect("manifest paths always have a parent directory");
        let output = self
            .cargo
            .command()?
            .current_dir(manifest_dir)
            .arg("fetch")
            .arg("--locked")
            .arg("--manifest-path")
            .arg(self.manifest_path)
            .output()
            .context("Error running cargo to fetch crates")?;
        if !output.status.success() {
            eprintln!("{}", String::from_utf8_lossy(&output.stderr));
            bail!("Failed to fetch crates: {}", output.status);
        }
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use super::*;

    fn table(entries: &[(&str, &[&str])]) -> BTreeMap<String, Vec<String>> {
        entries
            .iter()
            .map(|(feature, enables)| {
                (
                    feature.to_string(),
                    enables.iter().map(|e| e.to_string()).collect(),
                )
            })
            .collect()
    }

    fn request(features: &[&str], default_features: bool) -> Request {
        Request {
            features: features.iter().map(|f| f.to_string()).collect(),
            default_features,
        }
    }

    #[test]
    fn features_follow_cargo_syntax() {
        let table = table(&[
            ("default", &["std", "serde"]),
            ("std", &["alloc", "regex/std"]),
            ("alloc", &[]),
            ("serde", &["dep:serde", "chrono?/serde"]),
            ("full", &["default", "tokio"]),
        ]);

        let activation = activate(&table, &request(&[], true));
        assert_eq!(
            activation.features,
            ["default", "std", "alloc", "serde"]
                .into_iter()
                .map(String::from)
                .collect()
        );
        // `dep:serde` and `regex/std` enable their dependencies; `chrono?/serde`
        // is weak and does not enable chrono.
        assert_eq!(
            activation.optional_deps,
            BTreeSet::from(["regex".to_owned(), "serde".to_owned()])
        );
        assert_eq!(
            activation.dep_features,
            BTreeMap::from([
                ("regex".to_owned(), BTreeSet::from(["std".to_owned()])),
                ("chrono".to_owned(), BTreeSet::from(["serde".to_owned()])),
            ])
        );

        // An optional dependency named as a feature is enabled directly.
        let activation = activate(&table, &request(&["full"], false));
        assert!(activation.features.contains("std"));
        assert_eq!(
            activation.optional_deps,
            BTreeSet::from(["regex".to_owned(), "serde".to_owned(), "tokio".to_owned()])
        );

        // Without default features nothing is enabled.
        let activation = activate(&table, &request(&[], false));
        assert!(activation.features.is_empty());
        assert!(activation.optional_deps.is_empty());
    }

    #[test]
    fn extern_names_prefer_library_targets() {
        let pkg = json!({
            "name": "my-crate",
            "targets": [
                {"name": "my-crate", "kind": ["bin"]},
                {"name": "my_lib", "kind": ["lib"]},
            ],
        });
        assert_eq!(extern_name(&pkg, None), "my_lib");
        assert_eq!(extern_name(&pkg, Some("renamed-dep")), "renamed_dep");

        // Nothing links against a package without a library target.
        let bin_only = json!({
            "name": "bin-only",
            "targets": [{"name": "bin-only", "kind": ["bin"]}],
        });
        assert_eq!(extern_name(&bin_only, None), "");
        assert_eq!(extern_name(&bin_only, Some("tool")), "");
    }
}
