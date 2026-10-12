//! This module is responsible for finding a Cargo workspace

pub(crate) mod cargo_config;
mod crate_index_lookup;
mod splicer;

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::str::FromStr;

use anyhow::{anyhow, bail, Context, Result};
use camino::{Utf8Path, Utf8PathBuf};
use cargo_lock::package::SourceKind;
use cargo_toml::Manifest;
use serde::{Deserialize, Serialize};

use crate::config::CrateId;
use crate::metadata::{Cargo, CargoUpdateRequest, LockGenerator, TreeResolverMetadata};
use crate::utils;
use crate::utils::starlark::Label;

use self::cargo_config::CargoConfig;
use self::crate_index_lookup::CrateIndexLookup;
pub(crate) use self::splicer::*;

type DirectPackageManifest = BTreeMap<String, cargo_toml::DependencyDetail>;

/// A collection of information used for splicing together a new Cargo manifest.
#[derive(Debug, Default, Serialize, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
pub(crate) struct SplicingManifest {
    /// A set of all packages directly written to the rule
    pub(crate) direct_packages: DirectPackageManifest,

    /// A mapping of manifest paths to the labels representing them
    pub(crate) manifests: BTreeMap<Utf8PathBuf, Label>,

    /// The path of a Cargo config file
    pub(crate) cargo_config: Option<Utf8PathBuf>,

    /// The path of the `Cargo.lock` the workspace resolves against, when it
    /// has one. Its package set is part of the lockfile digest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) cargo_lockfile: Option<Utf8PathBuf>,

    /// The Cargo resolver version to use for splicing
    pub(crate) resolver_version: cargo_toml::Resolver,
}

impl FromStr for SplicingManifest {
    type Err = serde_json::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(s)
    }
}

impl SplicingManifest {
    pub(crate) fn try_from_path<T: AsRef<Path>>(path: T) -> Result<Self> {
        let content = fs::read_to_string(path.as_ref())?;
        Self::from_str(&content).context("Failed to load SplicingManifest")
    }

    pub(crate) fn resolve(self, workspace_dir: &Path, output_base: &Path) -> Self {
        let Self {
            manifests,
            cargo_config,
            cargo_lockfile,
            ..
        } = self;

        let workspace_dir_str = workspace_dir.to_string_lossy();
        let output_base_str = output_base.to_string_lossy();

        // Ensure manifests all have absolute paths
        let manifests = manifests
            .into_iter()
            .map(|(path, label)| {
                let resolved_path = path
                    .to_string()
                    .replace("${build_workspace_directory}", &workspace_dir_str)
                    .replace("${output_base}", &output_base_str);
                (Utf8PathBuf::from(resolved_path), label)
            })
            .collect();

        // Ensure the cargo config and lockfile are located at absolute paths
        let resolve_path = |path: Utf8PathBuf| {
            let resolved_path = path
                .to_string()
                .replace("${build_workspace_directory}", &workspace_dir_str)
                .replace("${output_base}", &output_base_str);
            Utf8PathBuf::from(resolved_path)
        };
        let cargo_config = cargo_config.map(resolve_path);
        let cargo_lockfile = cargo_lockfile.map(resolve_path);

        Self {
            manifests,
            cargo_config,
            cargo_lockfile,
            ..self
        }
    }
}

/// The parts of a manifest which can change what Cargo resolves.
///
/// The lockfile digest covers this projection rather than the whole manifest, so
/// editing anything else - a description, a `[[bin]]`, lints, profiles - does
/// not require a repin.
#[derive(Debug, Default, Serialize)]
pub(crate) struct ManifestProjection {
    #[serde(skip_serializing_if = "Option::is_none")]
    package: Option<PackageProjection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    workspace: Option<WorkspaceProjection>,
    dependencies: cargo_toml::DepsSet,
    dev_dependencies: cargo_toml::DepsSet,
    build_dependencies: cargo_toml::DepsSet,
    target: cargo_toml::TargetDepsSet,
    features: cargo_toml::FeatureSet,
    patch: cargo_toml::PatchSet,
    replace: cargo_toml::DepsSet,
}

/// The resolution relevant parts of a `[package]` table.
#[derive(Debug, Serialize)]
struct PackageProjection {
    name: String,
    version: cargo_toml::Inheritable<String>,
    edition: cargo_toml::Inheritable<cargo_toml::Edition>,
    links: Option<String>,
    resolver: Option<cargo_toml::Resolver>,
    /// `[package.metadata.bazel]`, the crate's own annotation defaults.
    bazel_metadata: Option<cargo_toml::Value>,
}

/// The resolution relevant parts of a `[workspace]` table.
#[derive(Debug, Serialize)]
struct WorkspaceProjection {
    members: Vec<String>,
    default_members: Vec<String>,
    exclude: Vec<String>,
    package: Option<cargo_toml::PackageTemplate>,
    resolver: Option<cargo_toml::Resolver>,
    dependencies: cargo_toml::DepsSet,
}

impl From<&cargo_toml::Manifest> for ManifestProjection {
    // `[replace]` is deprecated in favor of `[patch]` but Cargo still honors it.
    #[allow(deprecated)]
    fn from(manifest: &cargo_toml::Manifest) -> Self {
        Self {
            package: manifest.package.as_ref().map(|package| PackageProjection {
                name: package.name.clone(),
                version: package.version.clone(),
                edition: package.edition,
                links: package.links.clone(),
                resolver: package.resolver,
                bazel_metadata: package
                    .metadata
                    .as_ref()
                    .and_then(|metadata| metadata.get("bazel"))
                    .cloned(),
            }),
            workspace: manifest
                .workspace
                .as_ref()
                .map(|workspace| WorkspaceProjection {
                    members: workspace.members.clone(),
                    default_members: workspace.default_members.clone(),
                    exclude: workspace.exclude.clone(),
                    package: workspace.package.clone(),
                    resolver: workspace.resolver,
                    dependencies: workspace.dependencies.clone(),
                }),
            dependencies: manifest.dependencies.clone(),
            dev_dependencies: manifest.dev_dependencies.clone(),
            build_dependencies: manifest.build_dependencies.clone(),
            target: manifest.target.clone(),
            features: manifest.features.clone(),
            patch: manifest.patch.clone(),
            replace: manifest.replace.clone(),
        }
    }
}

/// The parts of a `Cargo.lock` which pin what gets rendered: every package
/// with its source and checksum, and the `[patch]` entries Cargo did not use.
///
/// The lockfile digest covers this projection rather than the file, so a change
/// of lockfile format version or of Cargo's layout does not require a repin,
/// while a package added, removed or moved to another version does.
#[derive(Debug, Default, Serialize, PartialEq, Eq)]
pub(crate) struct LockfileProjection {
    packages: Vec<LockedPackage>,
    unused_patches: Vec<String>,
}

#[derive(Debug, Serialize, PartialEq, Eq, PartialOrd, Ord)]
struct LockedPackage {
    name: String,
    version: String,
    source: Option<String>,
    checksum: Option<String>,
}

impl From<&cargo_lock::Lockfile> for LockfileProjection {
    fn from(lockfile: &cargo_lock::Lockfile) -> Self {
        let mut packages: Vec<LockedPackage> = lockfile
            .packages
            .iter()
            .map(|package| LockedPackage {
                name: package.name.to_string(),
                version: package.version.to_string(),
                source: package.source.as_ref().map(|source| source.to_string()),
                checksum: package
                    .checksum
                    .as_ref()
                    .map(|checksum| checksum.to_string()),
            })
            .collect();
        packages.sort();
        let mut unused_patches: Vec<String> = lockfile
            .patch
            .unused
            .iter()
            .map(|patch| match &patch.source {
                Some(source) => format!("{} {} ({})", patch.name, patch.version, source),
                None => format!("{} {}", patch.name, patch.version),
            })
            .collect();
        unused_patches.sort();
        Self {
            packages,
            unused_patches,
        }
    }
}

impl LockfileProjection {
    /// The projection of the `Cargo.lock` at `path`, or `None` when there is
    /// none yet: a lockfile attribute may point at an empty file to be filled
    /// in by the first resolution.
    fn try_from_path(path: &Utf8Path) -> Result<Option<Self>> {
        if !path.exists() {
            return Ok(None);
        }
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read Cargo lockfile '{}'", path))?;
        if content.trim().is_empty() {
            return Ok(None);
        }
        let lockfile: cargo_lock::Lockfile = content
            .parse()
            .with_context(|| format!("Failed to parse Cargo lockfile '{}'", path))?;
        Ok(Some(Self::from(&lockfile)))
    }
}

/// The result of fully resolving a [SplicingManifest] in preparation for splicing.
#[derive(Debug, Serialize, Default)]
pub(crate) struct SplicingMetadata {
    /// A set of all packages directly written to the rule
    pub(crate) direct_packages: DirectPackageManifest,

    /// The resolution relevant parts of each manifest, keyed by its label.
    pub(crate) manifests: BTreeMap<Label, ManifestProjection>,

    /// The path of a Cargo config file
    pub(crate) cargo_config: Option<CargoConfig>,

    /// The package set of the `Cargo.lock`, when the workspace has one. Left
    /// out when it does not so such repositories keep their digest.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) cargo_lock: Option<LockfileProjection>,

    /// The Cargo resolver version used for splicing, which changes what gets
    /// resolved and so belongs in the lockfile digest.
    pub(crate) resolver_version: cargo_toml::Resolver,
}

impl TryFrom<SplicingManifest> for SplicingMetadata {
    type Error = anyhow::Error;

    fn try_from(value: SplicingManifest) -> Result<Self, Self::Error> {
        let direct_packages = value.direct_packages;

        let manifests = value
            .manifests
            .into_iter()
            .map(|(path, label)| {
                // We read the content of a manifest file to buffer and use `from_slice` to
                // parse it. The reason is that the `from_path` version will resolve indirect
                // path dependencies in the workspace to absolute path, which causes the hash
                // to be unstable. Not resolving implicit data is okay here because the
                // workspace manifest is also included in the hash.
                // See https://github.com/bazelbuild/rules_rust/issues/2016
                let manifest_content = fs::read(&path)
                    .with_context(|| format!("Failed to load manifest '{}'", path))?;
                let manifest = cargo_toml::Manifest::from_slice(&manifest_content)
                    .with_context(|| format!("Failed to parse manifest '{}'", path))?;
                Ok((label, ManifestProjection::from(&manifest)))
            })
            .collect::<Result<BTreeMap<Label, ManifestProjection>>>()?;

        let cargo_config = match value.cargo_config {
            Some(path) => Some(
                CargoConfig::try_from_path(path.as_std_path())
                    .with_context(|| format!("Failed to load cargo config '{}'", path))?,
            ),
            None => None,
        };

        let cargo_lock = match &value.cargo_lockfile {
            Some(path) => LockfileProjection::try_from_path(path)?,
            None => None,
        };

        Ok(Self {
            direct_packages,
            manifests,
            cargo_config,
            cargo_lock,
            resolver_version: value.resolver_version,
        })
    }
}

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub(crate) struct SourceInfo {
    /// A url where to a `.crate` file.
    pub(crate) url: String,

    /// The `.crate` file's sha256 checksum.
    pub(crate) sha256: String,
}

/// Information about the Cargo workspace relative to the Bazel workspace
#[derive(Debug, Default, Serialize, Deserialize)]
pub(crate) struct WorkspaceMetadata {
    /// A mapping of crates to information about where their source can be downloaded
    pub(crate) sources: BTreeMap<CrateId, SourceInfo>,

    /// The path from the root of a Bazel workspace to the root of the Cargo workspace
    pub(crate) workspace_prefix: Option<String>,

    /// Paths from the root of a Bazel workspace to a Cargo package
    pub(crate) package_prefixes: BTreeMap<String, String>,

    /// Feature set for each target triplet and crate.
    ///
    /// We store this here because it's computed during the splicing phase via
    /// calls to "cargo tree" which need the full spliced workspace.
    pub(crate) tree_metadata: TreeResolverMetadata,
}

impl TryFrom<toml::Value> for WorkspaceMetadata {
    type Error = anyhow::Error;

    fn try_from(value: toml::Value) -> Result<Self, Self::Error> {
        match value.get("cargo-bazel") {
            Some(v) => v
                .to_owned()
                .try_into()
                .context("Failed to deserialize toml value"),
            None => bail!("cargo-bazel workspace metadata not found"),
        }
    }
}

impl TryFrom<serde_json::Value> for WorkspaceMetadata {
    type Error = anyhow::Error;

    fn try_from(value: serde_json::Value) -> Result<Self, Self::Error> {
        match value.get("cargo-bazel") {
            Some(value) => {
                serde_json::from_value(value.to_owned()).context("Failed to deserialize json value")
            }
            None => bail!("cargo-bazel workspace metadata not found"),
        }
    }
}

impl WorkspaceMetadata {
    fn new(
        splicing_manifest: &SplicingManifest,
        member_manifests: BTreeMap<&Utf8PathBuf, String>,
    ) -> Result<Self> {
        let mut package_prefixes: BTreeMap<String, String> = member_manifests
            .iter()
            .filter_map(|(original_manifest, cargo_package_name)| {
                let label = match splicing_manifest.manifests.get(*original_manifest) {
                    Some(v) => v,
                    None => return None,
                };

                let package = match label.package() {
                    Some(package) if !package.is_empty() => PathBuf::from(package),
                    Some(_) | None => return None,
                };

                let prefix = package.to_string_lossy().to_string();

                Some((cargo_package_name.clone(), prefix))
            })
            .collect();

        // It is invalid for toml maps to use empty strings as keys. In the case
        // the empty key is expected to be the root package. If the root package
        // has a prefix, then all other packages will as well (even if no other
        // manifest represents them). The value is then saved as a separate value
        let workspace_prefix = package_prefixes.remove("");

        let package_prefixes = package_prefixes
            .into_iter()
            .map(|(k, v)| {
                let prefix_path = PathBuf::from(v);
                let prefix = prefix_path.parent().unwrap();
                (k, prefix.to_string_lossy().to_string())
            })
            .collect();

        Ok(Self {
            sources: BTreeMap::new(),
            workspace_prefix,
            package_prefixes,
            tree_metadata: TreeResolverMetadata::new(),
        })
    }

    /// Update an existing Cargo manifest with metadata about registry urls and target
    /// features that are needed in generator steps beyond splicing.
    #[tracing::instrument(skip_all)]
    pub(crate) fn write_registry_urls_and_feature_map(
        cargo: &Cargo,
        lockfile: &cargo_lock::Lockfile,
        resolver_data: TreeResolverMetadata,
        input_manifest_path: &Utf8Path,
        output_manifest_path: &Utf8Path,
    ) -> Result<()> {
        let mut manifest = read_manifest(input_manifest_path)?;

        let mut workspace_metadata = WorkspaceMetadata::try_from(
            manifest
                .workspace
                .as_ref()
                .unwrap()
                .metadata
                .as_ref()
                .unwrap()
                .clone(),
        )?;

        // Locate all packages sourced from a registry
        let pkg_sources: Vec<&cargo_lock::Package> = lockfile
            .packages
            .iter()
            .filter(|pkg| pkg.source.is_some())
            .filter(|pkg| pkg.source.as_ref().unwrap().is_registry())
            .collect();

        // Collect a unique set of index urls
        let index_urls: BTreeSet<(SourceKind, String)> = pkg_sources
            .iter()
            .map(|pkg| {
                let source = pkg.source.as_ref().unwrap();
                (source.kind().clone(), source.url().to_string())
            })
            .collect();

        // Load the cargo config
        let cargo_config = {
            // Note that this path must match the one defined in `splicing::setup_cargo_config`
            let config_path = input_manifest_path
                .parent()
                .unwrap()
                .join(".cargo")
                .join("config.toml");

            if config_path.exists() {
                Some(CargoConfig::try_from_path(config_path.as_std_path())?)
            } else {
                None
            }
        };

        let crate_index_hash_kind = if cargo.uses_stable_registry_hash()? {
            crates_index::HashKind::Stable
        } else {
            crates_index::HashKind::Legacy
        };

        // Load each index for easy access
        let crate_indexes = index_urls
            .into_iter()
            .map(|(source_kind, url)| {
                let index_url =
                    registry_index_url(cargo, cargo_config.as_ref(), &source_kind, &url)?;
                let index = if index_url.starts_with("sparse+") {
                    let index = crates_index::SparseIndex::from_url_with_hash_kind(
                        &index_url,
                        &crate_index_hash_kind,
                    )?;
                    let index_config = index
                        .index_config()
                        .context("Failed to get crate index config")?;
                    CrateIndexLookup::Http {
                        index,
                        index_config,
                    }
                } else {
                    let index = crates_index::GitIndex::from_url_with_hash_kind(
                        &index_url,
                        &crate_index_hash_kind,
                    )
                    .with_context(|| format!("Failed to load index for url: {index_url}"))?;
                    let index_config = index.index_config().with_context(|| {
                        format!("`config.json` not found in index: {index_url}")
                    })?;
                    CrateIndexLookup::Git {
                        index,
                        index_config,
                    }
                };
                Ok((url, index))
            })
            .collect::<Result<BTreeMap<String, _>>>()
            .context("Failed to locate crate indexes")?;

        // Get the download URL of each package based on it's registry url.
        let additional_sources = pkg_sources
            .iter()
            .map(|pkg| {
                let source_id = pkg.source.as_ref().unwrap();
                let source_url = source_id.url().to_string();
                let lookup = crate_indexes.get(&source_url).ok_or_else(|| {
                    anyhow!(
                        "Couldn't find crate_index data for SourceID {:?}",
                        source_id
                    )
                })?;
                lookup.get_source_info(pkg).map(|source_info| {
                    (
                        CrateId::new(pkg.name.as_str().to_owned(), pkg.version.clone()),
                        source_info,
                    )
                })
            })
            .collect::<Result<Vec<_>>>()?;

        workspace_metadata
            .sources
            .extend(additional_sources.into_iter());
        workspace_metadata.tree_metadata = resolver_data;
        workspace_metadata.inject_into(&mut manifest)?;

        write_root_manifest(output_manifest_path.as_std_path(), manifest)?;

        Ok(())
    }

    fn inject_into(&self, manifest: &mut Manifest) -> Result<()> {
        let metadata_value = toml::Value::try_from(self)?;
        let workspace = manifest.workspace.as_mut().unwrap();

        match &mut workspace.metadata {
            Some(data) => match data.as_table_mut() {
                Some(map) => {
                    map.insert("cargo-bazel".to_owned(), metadata_value);
                }
                None => bail!("The metadata field is always expected to be a table"),
            },
            None => {
                let mut table = toml::map::Map::new();
                table.insert("cargo-bazel".to_owned(), metadata_value);
                workspace.metadata = Some(toml::Value::Table(table))
            }
        }

        Ok(())
    }
}

#[derive(Debug)]
pub(crate) enum SplicedManifest {
    Workspace(Utf8PathBuf),
    Package(Utf8PathBuf),
    MultiPackage(Utf8PathBuf),
}

impl SplicedManifest {
    pub(crate) fn as_path_buf(&self) -> &Utf8PathBuf {
        match self {
            SplicedManifest::Workspace(p) => p,
            SplicedManifest::Package(p) => p,
            SplicedManifest::MultiPackage(p) => p,
        }
    }
}

pub(crate) fn read_manifest(manifest: &Utf8Path) -> Result<Manifest> {
    let content = fs::read_to_string(manifest.as_std_path())?;
    cargo_toml::Manifest::from_str(content.as_str()).context("Failed to deserialize manifest")
}

/// The URL of the index a registry package is looked up in: the lockfile's
/// source after any `[source]` replacement of the Cargo config, in the form
/// `crates_index` expects (`sparse+` for sparse registries).
pub(crate) fn registry_index_url(
    cargo: &Cargo,
    cargo_config: Option<&CargoConfig>,
    source_kind: &SourceKind,
    url: &str,
) -> Result<String> {
    let index_url = match cargo_config {
        Some(config) => config.resolve_replacement_url(url)?.to_owned(),
        None => url.to_owned(),
    };
    if cargo.use_sparse_registries_for_crates_io()? && index_url == utils::CRATES_IO_INDEX_URL {
        return Ok("sparse+https://index.crates.io/".to_owned());
    }
    if index_url.starts_with("sparse+") {
        return Ok(index_url);
    }
    match source_kind {
        SourceKind::Registry => Ok(index_url),
        SourceKind::SparseRegistry => Ok(format!("sparse+{index_url}")),
        unknown => Err(anyhow!(
            "'{:?}' crate index type is not supported (caused by '{}')",
            unknown,
            url
        )),
    }
}

pub(crate) fn generate_lockfile(
    manifest_path: &SplicedManifest,
    existing_lock: &Option<PathBuf>,
    cargo_bin: Cargo,
    update_request: &Option<CargoUpdateRequest>,
) -> Result<cargo_lock::Lockfile> {
    let manifest_dir = manifest_path
        .as_path_buf()
        .parent()
        .expect("Every manifest should be contained in a parent directory");

    let root_lockfile_path = manifest_dir.join("Cargo.lock");

    // Remove the file so it's not overwritten if it happens to be a symlink.
    if root_lockfile_path.exists() {
        fs::remove_file(&root_lockfile_path)?;
    }

    // Generate the new lockfile
    let lockfile = LockGenerator::new(cargo_bin).generate(
        manifest_path.as_path_buf(),
        existing_lock,
        update_request,
    )?;

    // Write the lockfile to disk
    if !root_lockfile_path.exists() {
        bail!("Failed to generate Cargo.lock file")
    }

    Ok(lockfile)
}

#[cfg(test)]
mod test {
    use super::*;

    fn projection(manifest: &str) -> serde_json::Value {
        let manifest = cargo_toml::Manifest::from_slice(manifest.as_bytes()).unwrap();
        serde_json::to_value(ManifestProjection::from(&manifest)).unwrap()
    }

    /// Only what can change the resolution is in the projection, so edits to
    /// anything else leave the lockfile digest alone.
    #[test]
    fn manifest_projection_covers_only_resolution_inputs() {
        let base = indoc::indoc! {r#"
            [package]
            name = "example"
            version = "0.1.0"
            edition = "2021"
            description = "before"

            [dependencies]
            anyhow = "1"

            [features]
            default = []
        "#};
        let cosmetic = indoc::indoc! {r#"
            [package]
            name = "example"
            version = "0.1.0"
            edition = "2021"
            description = "after"
            license = "MIT"

            [[bin]]
            name = "tool"
            path = "src/tool.rs"

            [dependencies]
            anyhow = "1"

            [features]
            default = []

            [lints.rust]
            unsafe_code = "forbid"

            [profile.release]
            lto = true
        "#};
        assert_eq!(projection(base), projection(cosmetic));

        for changed in [
            base.replace("anyhow = \"1\"", "anyhow = \"2\""),
            base.replace("default = []", "default = [\"std\"]\nstd = []"),
            base.replace("edition = \"2021\"", "edition = \"2018\""),
            base.replace("[dependencies]", "[target.'cfg(unix)'.dependencies]"),
            format!("{base}\n[package.metadata.bazel]\ngen_build_script = false\n"),
        ] {
            assert_ne!(projection(base), projection(&changed), "{changed}");
        }
    }

    /// Only the package set is in the projection, so Cargo rewriting the file
    /// in a newer lockfile format leaves the lockfile digest alone.
    #[test]
    fn lockfile_projection_covers_only_the_package_set() {
        let projection =
            |text: &str| LockfileProjection::from(&text.parse::<cargo_lock::Lockfile>().unwrap());
        let base = indoc::indoc! {r#"
            # This file is automatically @generated by Cargo.
            # It is not intended for manual editing.
            version = 3

            [[package]]
            name = "cfg-if"
            version = "1.0.0"
            source = "registry+https://github.com/rust-lang/crates.io-index"
            checksum = "baf1de4339761588bc0619e3cbc0120ee582ebb74b53b4efbf79117bd2da40fd"

            [[package]]
            name = "example"
            version = "0.1.0"
            dependencies = [
             "cfg-if",
            ]
        "#};
        let reformatted = base
            .replace("version = 3", "version = 4")
            .replace("# It is not intended for manual editing.\n", "");
        assert_eq!(projection(base), projection(&reformatted));

        for changed in [
            base.replace("version = \"1.0.0\"", "version = \"1.0.1\""),
            base.replace("checksum = \"baf1", "checksum = \"0af1"),
            base.replace("name = \"example\"", "name = \"renamed\""),
        ] {
            assert_ne!(projection(base), projection(&changed), "{changed}");
        }
    }

    #[test]
    fn deserialize_splicing_manifest() {
        let runfiles = runfiles::Runfiles::create().unwrap();
        let path = runfiles::rlocation!(
            runfiles,
            "rules_rust/crate_universe/test_data/serialized_configs/splicing_manifest.json"
        )
        .unwrap();

        let content = std::fs::read_to_string(path).unwrap();

        let manifest: SplicingManifest = serde_json::from_str(&content).unwrap();

        // Check manifests
        assert_eq!(
            manifest.manifests,
            BTreeMap::from([
                (
                    Utf8PathBuf::from("${build_workspace_directory}/submod/Cargo.toml"),
                    Label::from_str("//submod:Cargo.toml").unwrap()
                ),
                (
                    Utf8PathBuf::from("${output_base}/external_crate/Cargo.toml"),
                    Label::from_str("@external_crate//:Cargo.toml").unwrap()
                ),
                (
                    Utf8PathBuf::from("/tmp/abs/path/workspace/Cargo.toml"),
                    Label::from_str("//:Cargo.toml").unwrap()
                ),
            ])
        );

        // Check splicing configs
        assert_eq!(manifest.resolver_version, cargo_toml::Resolver::V2);

        // Check packages
        assert_eq!(manifest.direct_packages.len(), 4);
        let package = manifest.direct_packages.get("rand").unwrap();
        assert_eq!(
            package,
            &cargo_toml::DependencyDetail {
                default_features: false,
                features: vec!["small_rng".to_owned()],
                version: Some("0.8.5".to_owned()),
                ..Default::default()
            }
        );
        let package = manifest.direct_packages.get("cfg-if").unwrap();
        assert_eq!(
            package,
            &cargo_toml::DependencyDetail {
                git: Some("https://github.com/rust-lang/cfg-if.git".to_owned()),
                rev: Some("b9c2246a".to_owned()),
                default_features: true,
                ..Default::default()
            }
        );
        let package = manifest.direct_packages.get("log").unwrap();
        assert_eq!(
            package,
            &cargo_toml::DependencyDetail {
                git: Some("https://github.com/rust-lang/log.git".to_owned()),
                branch: Some("master".to_owned()),
                default_features: true,
                ..Default::default()
            }
        );
        let package = manifest.direct_packages.get("cargo_toml").unwrap();
        assert_eq!(
            package,
            &cargo_toml::DependencyDetail {
                git: Some("https://gitlab.com/lib.rs/cargo_toml.git".to_owned()),
                tag: Some("v0.15.2".to_owned()),
                default_features: true,
                ..Default::default()
            }
        );

        // Check cargo config
        assert_eq!(
            manifest.cargo_config,
            Some(Utf8PathBuf::from(
                "/tmp/abs/path/workspace/.cargo/config.toml"
            ))
        );
    }

    #[test]
    fn splicing_manifest_resolve() {
        let runfiles = runfiles::Runfiles::create().unwrap();
        let path = runfiles::rlocation!(
            runfiles,
            "rules_rust/crate_universe/test_data/serialized_configs/splicing_manifest.json"
        )
        .unwrap();

        let content = std::fs::read_to_string(path).unwrap();

        let mut manifest: SplicingManifest = serde_json::from_str(&content).unwrap();
        manifest.cargo_config = Some(Utf8PathBuf::from(
            "${build_workspace_directory}/.cargo/config.toml",
        ));
        manifest = manifest.resolve(
            &PathBuf::from("/tmp/abs/path/workspace"),
            &PathBuf::from("/tmp/output_base"),
        );

        // Check manifests
        assert_eq!(
            manifest.manifests,
            BTreeMap::from([
                (
                    Utf8PathBuf::from("/tmp/abs/path/workspace/submod/Cargo.toml"),
                    Label::from_str("//submod:Cargo.toml").unwrap()
                ),
                (
                    Utf8PathBuf::from("/tmp/output_base/external_crate/Cargo.toml"),
                    Label::from_str("@external_crate//:Cargo.toml").unwrap()
                ),
                (
                    Utf8PathBuf::from("/tmp/abs/path/workspace/Cargo.toml"),
                    Label::from_str("//:Cargo.toml").unwrap()
                ),
            ])
        );

        // Check cargo config
        assert_eq!(
            manifest.cargo_config.unwrap(),
            PathBuf::from("/tmp/abs/path/workspace/.cargo/config.toml"),
        )
    }

    #[test]
    fn splicing_metadata_workspace_path() {
        let runfiles = runfiles::Runfiles::create().unwrap();
        let workspace_manifest_path = runfiles::rlocation!(
            runfiles,
            "rules_rust/crate_universe/test_data/metadata/workspace_path/Cargo.toml"
        )
        .unwrap();
        let workspace_path = workspace_manifest_path.parent().unwrap().to_path_buf();
        let child_a_manifest_path = runfiles::rlocation!(
            runfiles,
            "rules_rust/crate_universe/test_data/metadata/workspace_path/child_a/Cargo.toml"
        )
        .unwrap();
        let child_b_manifest_path = runfiles::rlocation!(
            runfiles,
            "rules_rust/crate_universe/test_data/metadata/workspace_path/child_b/Cargo.toml"
        )
        .unwrap();
        let manifest = SplicingManifest {
            direct_packages: BTreeMap::new(),
            cargo_lockfile: None,
            manifests: BTreeMap::from([
                (
                    Utf8PathBuf::try_from(workspace_manifest_path).unwrap(),
                    Label::from_str("//:Cargo.toml").unwrap(),
                ),
                (
                    Utf8PathBuf::try_from(child_a_manifest_path).unwrap(),
                    Label::from_str("//child_a:Cargo.toml").unwrap(),
                ),
                (
                    Utf8PathBuf::try_from(child_b_manifest_path).unwrap(),
                    Label::from_str("//child_b:Cargo.toml").unwrap(),
                ),
            ]),
            cargo_config: None,
            resolver_version: cargo_toml::Resolver::V2,
        };
        let metadata = SplicingMetadata::try_from(manifest).unwrap();
        let metadata = serde_json::to_string(&metadata).unwrap();
        assert!(
            !metadata.contains(workspace_path.to_str().unwrap()),
            "serialized metadata should not contain absolute path"
        );
    }
}
