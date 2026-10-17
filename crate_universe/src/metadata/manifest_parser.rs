//! Reading Cargo manifests with Cargo's own parser.
//!
//! [`cargo_parser`] is the manifest half of Cargo, extracted: it resolves
//! workspace inheritance, discovers targets and brings every dependency into
//! its detailed form, producing the normalized manifest `cargo package`
//! publishes. Everything here derives from that, so the answers are Cargo's
//! rather than a reimplementation's.

use std::collections::BTreeMap;

use anyhow::{bail, Context, Result};
use camino::{Utf8Path, Utf8PathBuf};
use cargo_parser::{read_manifest, Edition, ParseContext, ParsedManifest, WorkspaceConfig};
use cargo_resolver::ResolveBehavior;
use cargo_util_schemas::manifest::{InheritableDependency, TomlDependency, TomlManifest};

/// The feature resolver a workspace uses, derived as Cargo does.
///
/// An explicit `resolver` in the root manifest's `[workspace]` or `[package]`
/// wins. Otherwise a root package implies its edition's default, and a virtual
/// manifest stays on the first resolver, no matter what editions its members
/// declare; Cargo warns about that rather than inferring.
pub(crate) fn resolve_behavior(manifest_path: &Utf8Path) -> Result<ResolveBehavior> {
    let gctx = ParseContext::default();
    let parsed = read_manifest(manifest_path.as_std_path(), true, &gctx)
        .with_context(|| format!("Failed to parse Cargo.toml file at {manifest_path}"))?;
    resolve_behavior_of(&parsed)
}

fn resolve_behavior_of(parsed: &ParsedManifest) -> Result<ResolveBehavior> {
    let toml = &parsed.normalized_toml;
    let package_resolver = toml.package().and_then(|p| p.resolver.as_deref());
    let workspace_resolver = toml.workspace.as_ref().and_then(|w| w.resolver.as_deref());
    let explicit = match (package_resolver, workspace_resolver) {
        (None, None) => None,
        (Some(resolver), None) | (None, Some(resolver)) => {
            Some(ResolveBehavior::from_manifest(resolver)?)
        }
        (Some(_), Some(_)) => {
            bail!("cannot specify `resolver` field in both `[workspace]` and `[package]`")
        }
    };
    if let Some(behavior) = explicit {
        return Ok(behavior);
    }
    match toml.package() {
        Some(package) => {
            let edition = package
                .normalized_edition()?
                .map(|e| e.parse::<Edition>())
                .transpose()?
                .unwrap_or_default();
            Ok(edition.default_resolve_behavior())
        }
        None => Ok(ResolveBehavior::V1),
    }
}

/// The members of a workspace, found the way Cargo's `Workspace` finds them.
///
/// Starting from the root manifest, that is the root package if there is one,
/// every package matched by `workspace.members`, and, transitively, the path
/// dependencies of members that lie inside the workspace root and are not
/// excluded. A manifest without a `[workspace]` section is a workspace of
/// one. Keys are normalized manifest paths.
///
/// Today this backs the conformance test against `cargo metadata`; it is the
/// member discovery crate_universe needs once it stops running Cargo.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn workspace_members(
    root_manifest: &Utf8Path,
    gctx: &ParseContext<'_>,
) -> Result<BTreeMap<Utf8PathBuf, ParsedManifest>> {
    let root_manifest = normalize(root_manifest);
    let root = read_manifest(root_manifest.as_std_path(), true, gctx)
        .with_context(|| format!("Failed to parse Cargo.toml file at {root_manifest}"))?;
    let mut members = BTreeMap::new();

    let WorkspaceConfig::Root(config) = root.workspace_config().clone() else {
        members.insert(root_manifest, root);
        return Ok(members);
    };

    let mut candidates = Vec::new();
    for (dir, glob) in config.members_paths(config.members().unwrap_or_default())? {
        let manifest = normalize(Utf8Path::from_path(&dir.join("Cargo.toml")).with_context(
            || format!("workspace member path is not UTF-8: {}", dir.display()),
        )?);
        candidates.push((manifest, glob.map(ToOwned::to_owned)));
    }

    // `find_path_deps` in Cargo, iteratively.
    let mut stack: Vec<(Utf8PathBuf, bool)> = Vec::new();
    for (manifest, _) in candidates.iter().rev() {
        stack.push((manifest.clone(), false));
    }
    stack.push((root_manifest.clone(), false));
    members.insert(root_manifest.clone(), root);
    while let Some((manifest, is_path_dep)) = stack.pop() {
        if is_path_dep
            && !manifest
                .parent()
                .map_or(false, |dir| dir.starts_with(config.root_dir()))
        {
            // A path dependency outside the workspace is not a member.
            continue;
        }
        if config.is_excluded(manifest.as_std_path()) {
            continue;
        }
        if !members.contains_key(&manifest) {
            let parsed = read_manifest(manifest.as_std_path(), true, gctx).with_context(|| {
                let via = candidates
                    .iter()
                    .find(|(m, _)| *m == manifest)
                    .and_then(|(_, glob)| glob.as_deref())
                    .map(|glob| format!(" via `{glob}`"))
                    .unwrap_or_default();
                format!(
                    "failed to load manifest for workspace member `{}`\nreferenced{via} by workspace at `{root_manifest}`",
                    manifest.parent().unwrap_or(&manifest)
                )
            })?;
            members.insert(manifest.clone(), parsed);
        }
        let parsed = &members[&manifest];
        if parsed.is_virtual() {
            continue;
        }
        let package_root = manifest.parent().expect("manifest paths have a parent");
        for (_, dep) in detailed_dependencies(&parsed.normalized_toml) {
            if let Some(path) = &dep.path {
                let candidate = normalize(&package_root.join(path).join("Cargo.toml"));
                stack.push((candidate, true));
            }
        }
    }
    Ok(members)
}

/// Every dependency declaration of a normalized manifest, across kinds and
/// platforms, with the name it is declared under.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn detailed_dependencies(
    toml: &TomlManifest,
) -> Vec<(
    &cargo_util_schemas::manifest::PackageName,
    &cargo_util_schemas::manifest::TomlDetailedDependency,
)> {
    let tables = [
        toml.dependencies.as_ref(),
        toml.dev_dependencies(),
        toml.build_dependencies(),
    ]
    .into_iter()
    .chain(toml.target.iter().flat_map(|target| {
        target.values().flat_map(|platform| {
            [
                platform.dependencies.as_ref(),
                platform.dev_dependencies(),
                platform.build_dependencies(),
            ]
        })
    }));
    tables
        .flatten()
        .flat_map(|table| table.iter())
        .filter_map(|(name, dep)| match dep {
            InheritableDependency::Value(TomlDependency::Detailed(detailed)) => {
                Some((name, detailed))
            }
            _ => None,
        })
        .collect()
}

fn normalize(path: &Utf8Path) -> Utf8PathBuf {
    Utf8PathBuf::from_path_buf(cargo_parser::paths::normalize_path(path.as_std_path()))
        .expect("normalizing a UTF-8 path keeps it UTF-8")
}

#[cfg(test)]
mod test {
    //! The parser against every `cargo metadata` fixture.
    //!
    //! `metadata.json` is what Cargo reported for the fixture's manifests. The
    //! workspace members' packages are compared with what [`cargo_parser`]
    //! normalizes from the same `Cargo.toml` files, field by field, so a
    //! difference between Cargo's parser and the extraction shows up here.

    use std::collections::{BTreeMap, BTreeSet};
    use std::path::PathBuf;
    use std::str::FromStr;

    use cargo_metadata::{DependencyKind, Metadata, Package, TargetKind};
    use cargo_platform::Platform;
    use cargo_util_schemas::manifest::{TomlDependency, TomlTarget};

    use super::*;

    fn fixtures_dir() -> Utf8PathBuf {
        let under_bazel = std::env::var("TEST_SRCDIR").ok().zip(std::env::var("TEST_WORKSPACE").ok());
        let root = match under_bazel {
            Some((srcdir, workspace)) => PathBuf::from(srcdir).join(workspace).join("crate_universe"),
            None => PathBuf::from(env!("CARGO_MANIFEST_DIR")),
        };
        Utf8PathBuf::from_path_buf(root.join("test_data").join("metadata")).unwrap()
    }

    /// The parts of a package the parser is expected to reproduce, in a form
    /// that can be built from both `cargo metadata` and the normalized manifest.
    #[derive(Debug, PartialEq, Eq)]
    struct Projection {
        name: String,
        version: String,
        edition: String,
        links: Option<String>,
        features: BTreeMap<String, Vec<String>>,
        /// `(kind, name, source path relative to the fixture)`.
        targets: BTreeSet<(String, String, String)>,
        dependencies: BTreeSet<Dep>,
    }

    #[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
    struct Dep {
        name: String,
        rename: Option<String>,
        kind: String,
        target: Option<String>,
        req: String,
        optional: bool,
        uses_default_features: bool,
        features: Vec<String>,
        /// Relative to the fixture, for path dependencies.
        path: Option<String>,
    }

    fn relative(path: &str, fixture: &str) -> String {
        let prefix = format!("{{TEMP_DIR}}/{fixture}/");
        path.strip_prefix(&prefix)
            .unwrap_or_else(|| panic!("`{path}` is not under `{prefix}`"))
            .to_owned()
    }

    fn from_metadata(package: &Package, fixture: &str, explicit_features: &BTreeMap<String, Vec<String>>) -> Projection {
        let targets = package
            .targets
            .iter()
            .map(|t| {
                let kind = t
                    .kind
                    .iter()
                    .map(|k| match k {
                        TargetKind::Lib => "lib",
                        TargetKind::Bin => "bin",
                        TargetKind::Example => "example",
                        TargetKind::Test => "test",
                        TargetKind::Bench => "bench",
                        TargetKind::CustomBuild => "custom-build",
                        TargetKind::ProcMacro => "proc-macro",
                        TargetKind::CDyLib => "cdylib",
                        TargetKind::DyLib => "dylib",
                        TargetKind::RLib => "rlib",
                        TargetKind::StaticLib => "staticlib",
                        other => panic!("unexpected target kind {other:?}"),
                    })
                    .collect::<Vec<_>>()
                    .join(",");
                (kind, t.name.clone(), relative(t.src_path.as_str(), fixture))
            })
            .collect();
        let dependencies = package
            .dependencies
            .iter()
            .map(|d| Dep {
                name: d.name.clone(),
                rename: d.rename.clone(),
                kind: match d.kind {
                    DependencyKind::Normal => "normal",
                    DependencyKind::Development => "dev",
                    DependencyKind::Build => "build",
                    other => panic!("unexpected dependency kind {other:?}"),
                }
                .to_owned(),
                target: d.target.as_ref().map(|t| t.to_string()),
                req: d.req.to_string(),
                optional: d.optional,
                uses_default_features: d.uses_default_features,
                features: {
                    let mut f = d.features.clone();
                    f.sort();
                    f
                },
                path: d.path.as_ref().map(|p| relative(p.as_str(), fixture)),
            })
            .collect();
        // `cargo metadata` lists the implicit feature Cargo creates for each
        // optional dependency not named with `dep:` anywhere. Those come from
        // `Summary`, which is past the parser's cut, so only explicit features
        // are compared.
        let features = package
            .features
            .iter()
            .filter(|(name, values)| {
                explicit_features.contains_key(*name) || **values != vec![format!("dep:{name}")]
            })
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        Projection {
            name: package.name.to_string(),
            version: package.version.to_string(),
            edition: package.edition.as_str().to_owned(),
            links: package.links.clone(),
            features,
            targets,
            dependencies,
        }
    }

    fn from_parsed(manifest: &Utf8Path, parsed: &ParsedManifest, fixture_dir: &Utf8Path) -> Projection {
        let toml = &parsed.normalized_toml;
        let package = toml.package().expect("members are packages");
        let package_root = manifest.parent().unwrap();
        let rel = |path: &std::path::Path| {
            let abs = normalize(Utf8Path::from_path(&package_root.as_std_path().join(path)).unwrap());
            abs.strip_prefix(fixture_dir).unwrap().as_str().to_owned()
        };
        let mut targets = BTreeSet::new();
        if let Some(lib) = &toml.lib {
            let kind = if lib.proc_macro() == Some(true) {
                "proc-macro".to_owned()
            } else {
                lib.crate_types()
                    .map(|kinds| kinds.join(","))
                    .unwrap_or_else(|| "lib".to_owned())
            };
            targets.insert((kind, lib.name.clone().unwrap(), rel(&lib.path.as_ref().unwrap().0)));
        }
        let mut add = |kind: &str, list: Option<&Vec<TomlTarget>>| {
            for t in list.into_iter().flatten() {
                targets.insert((kind.to_owned(), t.name.clone().unwrap(), rel(&t.path.as_ref().unwrap().0)));
            }
        };
        add("bin", toml.bin.as_ref());
        add("example", toml.example.as_ref());
        add("test", toml.test.as_ref());
        add("bench", toml.bench.as_ref());
        for script in package.normalized_build().unwrap().into_iter().flatten() {
            let path = std::path::Path::new(script);
            let stem = path.file_stem().unwrap().to_str().unwrap();
            targets.insert(("custom-build".to_owned(), format!("build-script-{stem}"), rel(path)));
        }

        let mut dependencies = BTreeSet::new();
        let mut add_table = |kind: &str, target: Option<&str>, table: Option<&BTreeMap<cargo_util_schemas::manifest::PackageName, InheritableDependency>>| {
            for (name_in_toml, dep) in table.into_iter().flatten() {
                let InheritableDependency::Value(dep) = dep else {
                    panic!("`{name_in_toml}` was not normalized");
                };
                let (package_name, req, optional, default_features, features, path) = match dep {
                    TomlDependency::Simple(req) => (None, Some(req.as_str()), None, None, Vec::new(), None),
                    TomlDependency::Detailed(d) => (
                        d.package.as_ref().map(|p| p.to_string()),
                        d.version.as_deref(),
                        d.optional,
                        d.default_features(),
                        d.features.clone().unwrap_or_default(),
                        d.path.as_deref(),
                    ),
                };
                let name = package_name.clone().unwrap_or_else(|| name_in_toml.to_string());
                let mut features = features;
                features.sort();
                dependencies.insert(Dep {
                    rename: (name != name_in_toml.as_str()).then(|| name_in_toml.to_string()),
                    name,
                    kind: kind.to_owned(),
                    target: target.map(|t| Platform::from_str(t).unwrap().to_string()),
                    req: semver::VersionReq::parse(req.unwrap_or("*")).unwrap().to_string(),
                    optional: optional.unwrap_or(false),
                    uses_default_features: default_features.unwrap_or(true),
                    features,
                    path: path.map(|p| rel(std::path::Path::new(p))),
                });
            }
        };
        add_table("normal", None, toml.dependencies.as_ref());
        add_table("dev", None, toml.dev_dependencies());
        add_table("build", None, toml.build_dependencies());
        for (platform, tables) in toml.target.iter().flatten() {
            add_table("normal", Some(platform), tables.dependencies.as_ref());
            add_table("dev", Some(platform), tables.dev_dependencies());
            add_table("build", Some(platform), tables.build_dependencies());
        }

        Projection {
            name: package.normalized_name().unwrap().to_string(),
            version: package.normalized_version().unwrap().unwrap().to_string(),
            edition: package.normalized_edition().unwrap().cloned().unwrap_or_else(|| "2015".to_owned()),
            links: package.links.clone(),
            features: toml
                .features
                .iter()
                .flatten()
                .map(|(k, v)| (k.to_string(), v.clone()))
                .collect(),
            targets,
            dependencies,
        }
    }

    #[test]
    fn members_match_cargo_metadata_for_every_fixture() {
        let fixtures_dir = fixtures_dir();
        let mut checked = 0;
        for entry in std::fs::read_dir(&fixtures_dir).unwrap() {
            let dir = Utf8PathBuf::from_path_buf(entry.unwrap().path()).unwrap();
            let manifest = dir.join("Cargo.toml");
            let metadata_json = dir.join("metadata.json");
            if !manifest.exists() || !metadata_json.exists() {
                continue;
            }
            let fixture = dir.file_name().unwrap();
            let metadata: Metadata =
                serde_json::from_str(&std::fs::read_to_string(&metadata_json).unwrap()).unwrap();
            if metadata.workspace_root.as_str() != format!("{{TEMP_DIR}}/{fixture}") {
                // Some fixtures pair a manifest with metadata recorded for a
                // different workspace (`abspath` carries `common`'s).
                continue;
            }

            let gctx = ParseContext::default();
            let members = workspace_members(&manifest, &gctx)
                .unwrap_or_else(|e| panic!("{fixture}: {e:?}"));

            let expected: BTreeMap<String, &Package> = metadata
                .packages
                .iter()
                .filter(|p| metadata.workspace_members.contains(&p.id))
                .map(|p| (relative(p.manifest_path.as_str(), fixture), p))
                .collect();
            let actual: BTreeMap<String, (&Utf8PathBuf, &ParsedManifest)> = members
                .iter()
                .map(|(path, parsed)| (path.strip_prefix(&dir).unwrap().as_str().to_owned(), (path, parsed)))
                .collect();
            assert_eq!(
                expected.keys().collect::<Vec<_>>(),
                actual.keys().collect::<Vec<_>>(),
                "{fixture}: workspace members differ"
            );
            for (rel_manifest, package) in &expected {
                let (path, parsed) = actual[rel_manifest];
                let ours = from_parsed(path, parsed, &dir);
                let theirs = from_metadata(package, fixture, &ours.features);
                assert_eq!(theirs, ours, "{fixture}: {rel_manifest} differs");
                assert!(parsed.errors.is_empty(), "{fixture}: {:?}", parsed.errors);
            }
            checked += 1;
        }
        assert!(checked >= 20, "only {checked} fixtures checked under {fixtures_dir}");
    }

    #[test]
    fn resolver_version_follows_cargo_rules() {
        let fixtures_dir = fixtures_dir();
        let behavior = |fixture: &str| {
            resolve_behavior(&fixtures_dir.join(fixture).join("Cargo.toml")).unwrap()
        };
        // A package without `resolver` takes its edition's default.
        assert_eq!(behavior("crate_types"), ResolveBehavior::V1); // edition 2018
        assert_eq!(behavior("nested_build_dependencies"), ResolveBehavior::V2); // edition 2021
        // An explicit `resolver` wins, in `[package]` or `[workspace]`.
        assert_eq!(behavior("resolver_2_deps"), ResolveBehavior::V2);
        assert_eq!(behavior("workspace_path"), ResolveBehavior::V2);
    }

    /// Writes `contents` to a `Cargo.toml` in a fresh temp dir and derives its
    /// resolver behavior.
    fn behavior_of(name: &str, contents: &str) -> ResolveBehavior {
        let (_tempdir, dir) = crate::test::test_tempdir(name);
        let manifest_path = dir.join("Cargo.toml");
        std::fs::write(&manifest_path, contents).unwrap();
        resolve_behavior(Utf8Path::from_path(&manifest_path).unwrap()).unwrap()
    }

    #[test]
    fn resolver_version_is_read_from_the_manifest() {
        assert_eq!(
            ResolveBehavior::V2,
            behavior_of(
                "explicit_resolver",
                indoc::indoc! {r#"
                    [workspace]
                    resolver = "2"

                    [package]
                    name = "example"
                    version = "0.0.0"
                    edition = "2015"
                "#},
            ),
        );
    }

    /// Cargo infers the resolver from the edition of the package at the workspace
    /// root when no `resolver` is declared. Defaulting to v1 here instead would
    /// union features across platforms and pull target-gated optional dependencies
    /// onto every platform.
    #[test]
    fn resolver_version_defaults_to_the_edition_default() {
        for (edition, expected) in [
            ("2015", ResolveBehavior::V1),
            ("2018", ResolveBehavior::V1),
            ("2021", ResolveBehavior::V2),
            ("2024", ResolveBehavior::V3),
        ] {
            assert_eq!(
                expected,
                behavior_of(
                    &format!("edition_{edition}"),
                    &format!(
                        indoc::indoc! {r#"
                            [workspace]

                            [package]
                            name = "example"
                            version = "0.0.0"
                            edition = "{}"
                        "#},
                        edition,
                    ),
                ),
                "unexpected resolver for edition {edition}",
            );
        }
    }

    /// A virtual manifest has no root package to take an edition from, so Cargo
    /// leaves it on the v1 resolver whatever its members' editions.
    #[test]
    fn resolver_version_of_a_virtual_manifest_defaults_to_v1() {
        assert_eq!(
            ResolveBehavior::V1,
            behavior_of(
                "virtual_manifest",
                indoc::indoc! {r#"
                    [workspace]
                    members = []
                "#},
            ),
        );
    }
}
