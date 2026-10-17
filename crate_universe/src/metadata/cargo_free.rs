//! Resolving a workspace without Cargo or rustc.
//!
//! Everything `cargo generate-lockfile` and `cargo metadata` provided comes
//! from the extracted Cargo crates instead: manifests through `cargo_parser`,
//! dependency resolution and the lockfile through `cargo_resolver`, the
//! registry through its sparse index over HTTP, crate sources from the
//! registry's download URL, and platform `cfg`s from the recorded
//! `rustc --print=cfg` table. The result is the same `cargo metadata` document
//! the rest of the generator consumes, so rendering is unchanged.
//!
//! Crate sources are placed where Cargo would put them,
//! `$CARGO_HOME/registry/src/<index>/<name>-<version>`, so a registry cache
//! Cargo populated is reused and the manifest paths in the metadata match
//! Cargo's.

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::str::FromStr;

use anyhow::{anyhow, bail, Context, Result};
use camino::{Utf8Path, Utf8PathBuf};
use cargo_parser::{read_manifest, to_summary, ManifestHost, ParseContext, ParsedManifest};
use cargo_platform3::{Cfg, Platform};
use cargo_resolver::interning::InternedString;
use cargo_resolver::{
    Artifact, CargoResult, CliFeatures, DepKind, Dependency, IndexSummary, IntoUrl, PackageId,
    QueryKind, Registry, Resolve, ResolveBehavior, ResolveOpts, ResolveVersion, SourceId, Summary,
    VersionPreferences,
};
use cargo_util_schemas::index::{IndexPackage, RegistryDependency};
use cargo_util_schemas::manifest::{TomlTarget, VecStringOrBool};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest as _, Sha256};
use tracing::{debug, trace};

use crate::config::CrateId;
use crate::metadata::cargo_resolver::{feature_tree_metadata, parse_cfgs, ResolveGraph};
use crate::metadata::manifest_parser::{resolve_behavior_of, workspace_members};
use crate::metadata::rustc_cfgs::RustcCfgs;
use crate::metadata::{CargoUpdateRequest, TreeResolverMetadata};
use crate::splicing::SourceInfo;
use crate::utils::target_triple::TargetTriple;

/// Highest index schema version this resolver understands (Cargo's `INDEX_V_MAX`).
const INDEX_V_MAX: u32 = 2;

/// What resolving a workspace produces, in the forms the rest of the generator
/// already consumes.
pub(crate) struct Resolution {
    /// The `cargo metadata` document, with the workspace metadata table left
    /// for the caller to fill in.
    pub(crate) metadata: Value,
    /// The lockfile, as Cargo would write it.
    pub(crate) lockfile: cargo_lock::Lockfile,
    /// Download URLs and checksums of every registry crate.
    pub(crate) sources: BTreeMap<CrateId, SourceInfo>,
    /// Features and dependencies per platform, from Cargo's feature resolver.
    pub(crate) tree_metadata: TreeResolverMetadata,
    /// The manifests of the workspace members.
    pub(crate) member_manifests: Vec<Utf8PathBuf>,
}

/// Resolves the spliced workspace at `root_manifest`.
///
/// `existing_lockfile` is honoured as Cargo honours it: its versions are
/// preferred wherever they still satisfy the manifests. `repin` relaxes that
/// for everything (`Eager`), for nothing new (`Workspace`) or for one package.
#[tracing::instrument(skip_all)]
pub(crate) fn resolve_workspace(
    root_manifest: &Utf8Path,
    existing_lockfile: Option<&Path>,
    repin: Option<&CargoUpdateRequest>,
    target_triples: &BTreeSet<TargetTriple>,
) -> Result<Resolution> {
    let cargo_home = cargo_home()?;
    let host = Host {
        cargo_home: cargo_home.clone(),
    };
    let gctx = ParseContext::new(&host);

    // The workspace members, parsed with Cargo's parser.
    let members = workspace_members(root_manifest, &gctx)?;
    let root = &members[&normalize(root_manifest)];
    let behavior = resolve_behavior_of(root)?;
    let member_manifests: Vec<Utf8PathBuf> = members.keys().cloned().collect();

    let mut packages: HashMap<PackageId, PackageInfo> = HashMap::new();
    let mut member_ids = Vec::new();
    for (manifest_path, parsed) in &members {
        if parsed.is_virtual() {
            continue;
        }
        let dir = manifest_path.parent().expect("manifest paths have a parent");
        let source_id = SourceId::for_path(dir.as_std_path())?;
        let mut warnings = Vec::new();
        let summary = to_summary(parsed, source_id, &gctx, &mut warnings)?;
        for warning in warnings {
            debug!("{manifest_path}: {warning}");
        }
        member_ids.push(summary.package_id());
        packages.insert(
            summary.package_id(),
            PackageInfo {
                manifest_path: manifest_path.clone(),
                parsed: Rc::new(parsed_clone(parsed, &gctx)?),
                summary,
            },
        );
    }
    if member_ids.is_empty() {
        bail!("workspace at {root_manifest} has no packages to resolve");
    }

    // Dependency resolution against the registry index and local manifests.
    let registry = WorkspaceRegistry {
        gctx: &gctx,
        cargo_home: &cargo_home,
        http: Http::new()?,
        indexes: RefCell::new(HashMap::new()),
        path_packages: RefCell::new(
            packages
                .iter()
                .map(|(id, info)| (id.source_id(), info.summary.clone()))
                .collect(),
        ),
    };

    let previous = match existing_lockfile {
        Some(path) if path.exists() => Some(
            cargo_lock::Lockfile::load(path)
                .with_context(|| format!("Failed to load lockfile: {}", path.display()))?,
        ),
        _ => None,
    };
    let mut version_prefs = VersionPreferences::default();
    if let Some(previous) = &previous {
        let keep = |pkg: &cargo_lock::Package| match repin {
            None | Some(CargoUpdateRequest::Workspace) => true,
            Some(CargoUpdateRequest::Eager) => false,
            Some(CargoUpdateRequest::Package { name, .. }) => pkg.name.as_str() != name,
        };
        for pkg in previous.packages.iter().filter(|p| keep(p)) {
            let Some(source) = &pkg.source else {
                continue;
            };
            let source_id = SourceId::from_url(&source.to_string())?;
            version_prefs.prefer_package_id(PackageId::new(
                InternedString::new(pkg.name.as_str()),
                pkg.version.clone(),
                source_id,
            ));
        }
    }
    if behavior == ResolveBehavior::V3 {
        let rust_versions: Vec<_> = packages
            .values()
            .filter_map(|p| p.summary.rust_version().map(|rv| rv.to_partial()))
            .collect();
        if !rust_versions.is_empty() {
            version_prefs.rust_versions(rust_versions);
        }
    }
    let lowest_rust_version = packages
        .values()
        .filter_map(|p| p.summary.rust_version())
        .min();
    let resolve_version = match previous.as_ref().map(|l| l.version) {
        Some(cargo_lock::ResolveVersion::V1) => ResolveVersion::V1,
        Some(cargo_lock::ResolveVersion::V2) => ResolveVersion::V2,
        Some(cargo_lock::ResolveVersion::V3) => ResolveVersion::V3,
        Some(_) => ResolveVersion::V4,
        None => ResolveVersion::with_rust_version(lowest_rust_version),
    };

    let summaries: Vec<(Summary, ResolveOpts)> = member_ids
        .iter()
        .map(|id| (packages[id].summary.clone(), ResolveOpts::everything()))
        .collect();
    let resolve = cargo_resolver::resolve(
        &summaries,
        &[],
        &registry,
        &version_prefs,
        resolve_version,
        &(),
    )
    .context("Failed to resolve dependencies")?;

    // Every resolved package needs its manifest, for the metadata document and
    // for the feature resolver's view of proc-macros.
    let mut sources = BTreeMap::new();
    for id in resolve.iter() {
        if packages.contains_key(&id) {
            continue;
        }
        let source = id.source_id();
        if source.is_path() {
            let (manifest_path, parsed, summary) = registry.path_package(id)?;
            packages.insert(
                id,
                PackageInfo {
                    manifest_path,
                    parsed,
                    summary,
                },
            );
        } else if source.is_registry() {
            let index = registry.index(source)?;
            let checksum = index.checksum(id)?;
            let (manifest_path, parsed) = index.extracted_manifest(&registry, id, &checksum)?;
            let mut warnings = Vec::new();
            let summary = to_summary(&parsed, source, &gctx, &mut warnings)?;
            sources.insert(
                crate_id(id),
                SourceInfo {
                    url: index.download_url(id, &registry.http)?,
                    sha256: checksum,
                },
            );
            packages.insert(
                id,
                PackageInfo {
                    manifest_path,
                    parsed: Rc::new(parsed),
                    summary,
                },
            );
        } else {
            bail!(
                "`{id}` comes from {source}, which is not supported without Cargo yet; \
                 only registry and path dependencies are"
            );
        }
    }

    // The lockfile, through Cargo's own encoding.
    let lock_text = toml::to_string(&resolve).context("Failed to encode lockfile")?;
    let lockfile = cargo_lock::Lockfile::from_str(&lock_text)
        .context("Failed to parse the encoded lockfile")?;

    // Features per platform.
    let proc_macro = packages
        .iter()
        .map(|(id, info)| (*id, is_proc_macro(&info.parsed)))
        .collect();
    let members: Vec<(PackageId, CliFeatures)> = member_ids
        .iter()
        .map(|id| (*id, CliFeatures::new_all(false)))
        .collect();
    let graph = ResolveGraph::new(resolve, members, proc_macro);
    let tree_metadata = feature_tree_metadata(&graph, behavior, target_triples, recorded_cfgs)?;

    let metadata = metadata_document(root_manifest, &graph.resolve, &packages, &member_ids)?;

    Ok(Resolution {
        metadata,
        lockfile,
        sources,
        tree_metadata,
        member_manifests,
    })
}

/// A resolved package: where its manifest is, what the parser made of it, and
/// the summary built from that manifest.
struct PackageInfo {
    manifest_path: Utf8PathBuf,
    parsed: Rc<ParsedManifest>,
    summary: Summary,
}

/// `ParsedManifest` is not `Clone`; reading the file again is cheap.
fn parsed_clone(parsed: &ParsedManifest, gctx: &ParseContext<'_>) -> Result<ParsedManifest> {
    Ok(read_manifest(&parsed.manifest_path, true, gctx)?)
}

fn crate_id(id: PackageId) -> CrateId {
    CrateId::new(id.name().to_string(), id.version().clone())
}

fn normalize(path: &Utf8Path) -> Utf8PathBuf {
    Utf8PathBuf::from_path_buf(cargo_parser::paths::normalize_path(path.as_std_path()))
        .expect("normalizing a UTF-8 path keeps it UTF-8")
}

fn cargo_home() -> Result<PathBuf> {
    if let Some(home) = std::env::var_os("CARGO_HOME") {
        return Ok(PathBuf::from(home));
    }
    let home = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .context("Neither CARGO_HOME nor HOME is set; cannot locate Cargo's home directory")?;
    Ok(PathBuf::from(home).join(".cargo"))
}

/// The parser's host: Cargo's home, so workspace discovery stops there.
struct Host {
    cargo_home: PathBuf,
}

impl ManifestHost for Host {
    fn cargo_home(&self) -> Option<&Path> {
        Some(&self.cargo_home)
    }
}

fn is_proc_macro(parsed: &ParsedManifest) -> bool {
    parsed.normalized_toml.lib.as_ref().is_some_and(|lib| {
        lib.proc_macro() == Some(true)
            || lib
                .crate_types()
                .is_some_and(|kinds| kinds.iter().any(|k| k == "proc-macro"))
    })
}

// ---------------------------------------------------------------------------
// The registry the resolver queries.

struct WorkspaceRegistry<'a> {
    gctx: &'a ParseContext<'a>,
    cargo_home: &'a Path,
    http: Http,
    /// Sparse indexes by registry source.
    indexes: RefCell<HashMap<SourceId, Rc<SparseIndex>>>,
    /// Packages from the file system, by their source, read on first use.
    path_packages: RefCell<HashMap<SourceId, Summary>>,
}

impl WorkspaceRegistry<'_> {
    fn index(&self, source: SourceId) -> Result<Rc<SparseIndex>> {
        if let Some(index) = self.indexes.borrow().get(&source) {
            return Ok(index.clone());
        }
        let index = Rc::new(SparseIndex::new(source, self.cargo_home)?);
        self.indexes.borrow_mut().insert(source, index.clone());
        Ok(index)
    }

    /// The summary of the package at a path source, reading its manifest if
    /// it has not been read yet.
    fn path_summary(&self, source: SourceId) -> Result<Summary> {
        if let Some(summary) = self.path_packages.borrow().get(&source) {
            return Ok(summary.clone());
        }
        let (_, _, summary) = self.read_path_package(source)?;
        self.path_packages
            .borrow_mut()
            .insert(source, summary.clone());
        Ok(summary)
    }

    fn path_package(&self, id: PackageId) -> Result<(Utf8PathBuf, Rc<ParsedManifest>, Summary)> {
        let (manifest_path, parsed, summary) = self.read_path_package(id.source_id())?;
        Ok((manifest_path, Rc::new(parsed), summary))
    }

    fn read_path_package(
        &self,
        source: SourceId,
    ) -> Result<(Utf8PathBuf, ParsedManifest, Summary)> {
        let dir = source
            .local_path()
            .with_context(|| format!("`{source}` is not a local path"))?;
        let manifest_path = Utf8PathBuf::from_path_buf(dir.join("Cargo.toml"))
            .map_err(|p| anyhow!("path is not UTF-8: {}", p.display()))?;
        let parsed = read_manifest(manifest_path.as_std_path(), true, self.gctx)
            .with_context(|| format!("Failed to parse Cargo.toml file at {manifest_path}"))?;
        let mut warnings = Vec::new();
        let summary = to_summary(&parsed, source, self.gctx, &mut warnings)?;
        Ok((manifest_path, parsed, summary))
    }
}

impl Registry for WorkspaceRegistry<'_> {
    async fn query(
        &self,
        dep: &Dependency,
        kind: QueryKind,
        f: &mut dyn FnMut(IndexSummary),
    ) -> CargoResult<()> {
        let source = dep.source_id();
        if source.is_path() {
            let summary = self.path_summary(source)?;
            if dep.matches(&summary) {
                f(IndexSummary::Candidate(summary));
            }
            return Ok(());
        }
        if source.is_git() {
            bail!(
                "dependency `{}` comes from {source}; git dependencies are not supported \
                 without Cargo yet",
                dep.package_name()
            );
        }
        let index = self.index(source)?;
        for entry in index.entries(dep.package_name().as_str(), &self.http)?.iter() {
            let matches = match kind {
                QueryKind::Exact => dep.matches_id(entry.summary.package_id()),
                QueryKind::RejectedVersions => true,
                QueryKind::AlternativeNames | QueryKind::Normalized => false,
            };
            if matches {
                f(entry.as_index_summary());
            }
        }
        Ok(())
    }

    fn describe_source(&self, source: SourceId) -> String {
        format!("{source}")
    }

    fn is_replaced(&self, _source: SourceId) -> bool {
        false
    }
}

// ---------------------------------------------------------------------------
// A sparse registry index over HTTP, with Cargo's on-disk layout for sources.

struct SparseIndex {
    source: SourceId,
    /// `https://index.crates.io/`
    base: String,
    /// Where fetched index files are kept between runs.
    cache_dir: PathBuf,
    /// Cargo's `registry/src/<index>` directory for this registry.
    src_dir: PathBuf,
    /// Cargo's `registry/cache/<index>` directory for this registry.
    crate_cache_dir: PathBuf,
    config: RefCell<Option<IndexConfig>>,
    entries: RefCell<HashMap<String, Rc<Vec<IndexEntry>>>>,
}

#[derive(Deserialize)]
struct IndexConfig {
    dl: String,
}

struct IndexEntry {
    summary: Summary,
    checksum: String,
    yanked: bool,
    schema_version: u32,
}

impl IndexEntry {
    fn as_index_summary(&self) -> IndexSummary {
        if self.schema_version > INDEX_V_MAX {
            IndexSummary::Unsupported(self.summary.clone(), self.schema_version)
        } else if self.yanked {
            IndexSummary::Yanked(self.summary.clone())
        } else {
            IndexSummary::Candidate(self.summary.clone())
        }
    }
}

impl SparseIndex {
    fn new(source: SourceId, cargo_home: &Path) -> Result<Self> {
        let sparse_url = if source.is_crates_io() {
            cargo_resolver::CRATES_IO_HTTP_INDEX.to_owned()
        } else if source.is_sparse() {
            format!("sparse+{}", source.url())
        } else {
            bail!(
                "registry {source} is a git index; only sparse registries are supported \
                 without Cargo"
            );
        };
        let base = sparse_url
            .strip_prefix("sparse+")
            .expect("sparse urls start with `sparse+`")
            .trim_end_matches('/')
            .to_owned()
            + "/";

        // Cargo names the per-registry directories `<host>-<hash>`; `crates-index`
        // knows the hash, so sources land where Cargo's own would.
        let (index_dir, _) = crates_index::local_path_and_canonical_url_with_hash_kind(
            &sparse_url,
            Some(cargo_home),
            &crates_index::HashKind::Stable,
        )
        .with_context(|| format!("Failed to derive the registry directory for {sparse_url}"))?;
        let dir_name = index_dir
            .file_name()
            .context("registry index directory has no name")?
            .to_owned();
        let registry = cargo_home.join("registry");
        Ok(Self {
            source,
            base,
            cache_dir: registry.join("cargo-bazel").join(&dir_name),
            src_dir: registry.join("src").join(&dir_name),
            crate_cache_dir: registry.join("cache").join(&dir_name),
            config: RefCell::new(None),
            entries: RefCell::new(HashMap::new()),
        })
    }

    fn config(&self, http: &Http) -> Result<IndexConfig> {
        if let Some(config) = self.config.borrow().as_ref() {
            return Ok(IndexConfig {
                dl: config.dl.clone(),
            });
        }
        let body = http
            .fetch_cached(&format!("{}config.json", self.base), &self.cache_dir.join("config.json"))?
            .with_context(|| format!("{}config.json was not found", self.base))?;
        let config: IndexConfig =
            serde_json::from_slice(&body).context("Failed to parse the registry's config.json")?;
        let dl = config.dl.clone();
        *self.config.borrow_mut() = Some(config);
        Ok(IndexConfig { dl })
    }

    /// The index entries of `name`, fetched once per run.
    fn entries(&self, name: &str, http: &Http) -> Result<Rc<Vec<IndexEntry>>> {
        if let Some(entries) = self.entries.borrow().get(name) {
            return Ok(entries.clone());
        }
        let rel = index_path(name);
        let body = http.fetch_cached(&format!("{}{rel}", self.base), &self.cache_dir.join(&rel))?;
        let mut entries = Vec::new();
        if let Some(body) = body {
            let text = String::from_utf8(body).context("index file is not UTF-8")?;
            for line in text.lines().filter(|l| !l.trim().is_empty()) {
                let pkg: IndexPackage<'_> = serde_json::from_str(line)
                    .with_context(|| format!("Failed to parse the index entry for {name}"))?;
                let schema_version = pkg.v.unwrap_or(1);
                let yanked = pkg.yanked.unwrap_or(false);
                let checksum = pkg.cksum.clone();
                let summary = index_package_to_summary(pkg, self.source)?;
                entries.push(IndexEntry {
                    summary,
                    checksum,
                    yanked,
                    schema_version,
                });
            }
        }
        let entries = Rc::new(entries);
        self.entries
            .borrow_mut()
            .insert(name.to_owned(), entries.clone());
        Ok(entries)
    }

    /// The index checksum of a resolved package. The resolver only resolves to
    /// entries it was served, so the entry is cached.
    fn checksum(&self, id: PackageId) -> Result<String> {
        let entries = self.entries.borrow();
        let entries = entries
            .get(id.name().as_str())
            .with_context(|| format!("`{id}` was resolved without consulting the index"))?;
        entries
            .iter()
            .find(|e| e.summary.package_id() == id)
            .map(|e| e.checksum.clone())
            .with_context(|| format!("`{id}` is not in the index"))
    }

    /// Where the `.crate` file of `id` is downloaded from, per the registry's
    /// `config.json`.
    fn download_url(&self, id: PackageId, http: &Http) -> Result<String> {
        let config = self.config(http)?;
        let dl = &config.dl;
        let name = id.name();
        let version = id.version().to_string();
        let markers = ["{crate}", "{version}", "{prefix}", "{lowerprefix}", "{sha256-checksum}"];
        if markers.iter().any(|m| dl.contains(m)) {
            let prefix = index_prefix(name.as_str());
            let checksum = self.checksum(id)?;
            Ok(dl
                .replace("{crate}", name.as_str())
                .replace("{version}", &version)
                .replace("{prefix}", &prefix)
                .replace("{lowerprefix}", &prefix.to_lowercase())
                .replace("{sha256-checksum}", &checksum))
        } else {
            Ok(format!("{dl}/{name}/{version}/download"))
        }
    }

    /// The manifest of `id`, from the crate's sources in Cargo's registry
    /// layout, downloading and extracting the `.crate` if they are not there.
    fn extracted_manifest(
        &self,
        registry: &WorkspaceRegistry<'_>,
        id: PackageId,
        checksum: &str,
    ) -> Result<(Utf8PathBuf, ParsedManifest)> {
        let dir_name = format!("{}-{}", id.name(), id.version());
        let src = self.src_dir.join(&dir_name);
        if !src.join(".cargo-ok").exists() {
            let crate_file = self.crate_cache_dir.join(format!("{dir_name}.crate"));
            let bytes = match fs::read(&crate_file) {
                Ok(bytes) if sha256_hex(&bytes) == checksum => bytes,
                _ => {
                    let url = self.download_url(id, &registry.http)?;
                    debug!("Downloading {url}");
                    let bytes = registry
                        .http
                        .fetch(&url)?
                        .with_context(|| format!("{url} was not found"))?;
                    let actual = sha256_hex(&bytes);
                    if actual != checksum {
                        bail!(
                            "checksum of {url} is {actual}, but the index says {checksum}"
                        );
                    }
                    fs::create_dir_all(&self.crate_cache_dir)?;
                    fs::write(&crate_file, &bytes)
                        .with_context(|| format!("Failed to write {}", crate_file.display()))?;
                    bytes
                }
            };
            extract_crate(&bytes, &dir_name, &self.src_dir)?;
        }
        let manifest_path = Utf8PathBuf::from_path_buf(src.join("Cargo.toml"))
            .map_err(|p| anyhow!("path is not UTF-8: {}", p.display()))?;
        let parsed = read_manifest(manifest_path.as_std_path(), false, registry.gctx)
            .with_context(|| format!("Failed to parse Cargo.toml file at {manifest_path}"))?;
        Ok((manifest_path, parsed))
    }
}

/// `se/rd/serde`, `3/a/abc`, `2/ab`, `1/a`: the index's layout.
fn index_path(name: &str) -> String {
    let lower = name.to_lowercase();
    match lower.len() {
        1 => format!("1/{lower}"),
        2 => format!("2/{lower}"),
        3 => format!("3/{}/{lower}", &lower[..1]),
        _ => format!("{}/{}/{lower}", &lower[..2], &lower[2..4]),
    }
}

/// The `{prefix}` of a download URL template.
fn index_prefix(name: &str) -> String {
    match name.len() {
        1 => "1".to_owned(),
        2 => "2".to_owned(),
        3 => format!("3/{}", &name[..1]),
        _ => format!("{}/{}", &name[..2], &name[2..4]),
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

/// Unpacks a `.crate` (a gzipped tar whose entries start with
/// `<name>-<version>/`) into `src_dir`, marking completion the way Cargo does.
fn extract_crate(bytes: &[u8], dir_name: &str, src_dir: &Path) -> Result<()> {
    let dest = src_dir.join(dir_name);
    if dest.exists() {
        fs::remove_dir_all(&dest)
            .with_context(|| format!("Failed to clear {}", dest.display()))?;
    }
    fs::create_dir_all(src_dir)?;
    let decoder = flate2::read::GzDecoder::new(bytes);
    let mut archive = tar::Archive::new(decoder);
    let prefix = Path::new(dir_name);
    for entry in archive.entries().context("Failed to read crate archive")? {
        let mut entry = entry?;
        let path = entry.path()?.into_owned();
        if !path.starts_with(prefix) {
            bail!(
                "crate archive entry `{}` is outside `{dir_name}/`",
                path.display()
            );
        }
        entry.unpack_in(src_dir)?;
    }
    fs::write(dest.join(".cargo-ok"), "ok")?;
    Ok(())
}

/// Port of Cargo's `index_package_to_summary`.
fn index_package_to_summary(pkg: IndexPackage<'_>, source_id: SourceId) -> CargoResult<Summary> {
    let pkgid = PackageId::new(pkg.name.as_ref().into(), pkg.vers, source_id);
    let deps = pkg
        .deps
        .into_iter()
        .map(|dep| registry_dependency_into_dep(dep, source_id))
        .collect::<CargoResult<Vec<_>>>()?;
    let mut features = pkg.features;
    if let Some(features2) = pkg.features2 {
        for (name, values) in features2 {
            features.entry(name).or_default().extend(values);
        }
    }
    let features = features
        .into_iter()
        .map(|(name, values)| {
            (
                InternedString::new(&name),
                values.into_iter().map(|v| InternedString::new(&v)).collect(),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let links: Option<InternedString> = pkg.links.as_ref().map(|l| l.as_ref().into());
    let mut summary = Summary::new(pkgid, deps, &features, links, pkg.rust_version)?;
    summary.set_checksum(pkg.cksum);
    Ok(summary)
}

/// Port of Cargo's `registry_dependency_into_dep`.
fn registry_dependency_into_dep(
    dep: RegistryDependency<'_>,
    default: SourceId,
) -> CargoResult<Dependency> {
    let RegistryDependency {
        name,
        req,
        mut features,
        optional,
        default_features,
        target,
        kind,
        registry,
        package,
        public,
        artifact,
        bindep_target,
        lib,
    } = dep;

    let id = if let Some(registry) = &registry {
        SourceId::for_registry(&registry.into_url()?)?
    } else {
        default
    };

    let interned_name = InternedString::new(package.as_ref().unwrap_or(&name));
    let mut dep = Dependency::parse(interned_name, Some(&req), id)?;
    if package.is_some() {
        dep.set_explicit_name_in_toml(name);
    }
    let kind = match kind.as_deref().unwrap_or("") {
        "dev" => DepKind::Development,
        "build" => DepKind::Build,
        _ => DepKind::Normal,
    };

    let platform = match target {
        Some(target) => Some(target.parse::<Platform>()?),
        None => None,
    };

    let public = public.unwrap_or(false);

    features.retain(|s| !s.is_empty());

    if !id.is_crates_io() {
        dep.set_registry_id(id);
    }

    if let Some(artifacts) = artifact {
        let artifact = Artifact::parse(&artifacts, lib, bindep_target.as_deref(), false)?;
        dep.set_artifact(artifact);
    }

    dep.set_optional(optional)
        .set_default_features(default_features)
        .set_features(features)
        .set_platform(platform)
        .set_kind(kind)
        .set_public(public);

    Ok(dep)
}

// ---------------------------------------------------------------------------
// HTTP, with a cache keyed by ETag so unchanged index files are not re-sent.

struct Http {
    agent: ureq::Agent,
}

impl Http {
    fn new() -> Result<Self> {
        let config = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .user_agent(concat!("cargo-bazel/", env!("CARGO_PKG_VERSION")))
            .build();
        Ok(Self {
            agent: config.new_agent(),
        })
    }

    /// `GET url`; `None` when the server has no such file.
    fn fetch(&self, url: &str) -> Result<Option<Vec<u8>>> {
        let mut response = self
            .agent
            .get(url)
            .call()
            .with_context(|| format!("Failed to fetch {url}"))?;
        match response.status().as_u16() {
            200 => Ok(Some(
                response
                    .body_mut()
                    .read_to_vec()
                    .with_context(|| format!("Failed to read {url}"))?,
            )),
            404 | 410 | 451 => Ok(None),
            status => bail!("{url} returned HTTP {status}"),
        }
    }

    /// `GET url`, revalidating a cached copy at `cache_path` with its ETag.
    fn fetch_cached(&self, url: &str, cache_path: &Path) -> Result<Option<Vec<u8>>> {
        let etag_path = cache_path.with_extension("etag");
        let cached = fs::read(cache_path).ok();
        let etag = fs::read_to_string(&etag_path).ok();
        let mut request = self.agent.get(url);
        if let (Some(_), Some(etag)) = (&cached, &etag) {
            request = request.header("If-None-Match", etag.trim());
        }
        trace!("GET {url}");
        let mut response = request
            .call()
            .with_context(|| format!("Failed to fetch {url}"))?;
        match response.status().as_u16() {
            200 => {
                let etag = response
                    .headers()
                    .get("etag")
                    .and_then(|v| v.to_str().ok())
                    .map(ToOwned::to_owned);
                let mut body = Vec::new();
                response
                    .body_mut()
                    .as_reader()
                    .read_to_end(&mut body)
                    .with_context(|| format!("Failed to read {url}"))?;
                if let Some(parent) = cache_path.parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::write(cache_path, &body)?;
                match etag {
                    Some(etag) => fs::write(&etag_path, etag)?,
                    None => {
                        let _ = fs::remove_file(&etag_path);
                    }
                }
                Ok(Some(body))
            }
            304 => Ok(cached),
            404 | 410 | 451 => Ok(None),
            status => bail!("{url} returned HTTP {status}"),
        }
    }
}

// ---------------------------------------------------------------------------
// The `cargo metadata` document.

fn metadata_document(
    root_manifest: &Utf8Path,
    resolve: &Resolve,
    packages: &HashMap<PackageId, PackageInfo>,
    member_ids: &[PackageId],
) -> Result<Value> {
    let mut ids: Vec<PackageId> = resolve.iter().collect();
    ids.sort();

    let mut package_values = Vec::with_capacity(ids.len());
    let mut nodes = Vec::with_capacity(ids.len());
    for id in &ids {
        let info = &packages[id];
        package_values.push(package_json(*id, info)?);

        let mut deps: Vec<(PackageId, Value)> = Vec::new();
        for (dep_id, edges) in resolve.deps(*id) {
            let lib_name = lib_target_name(&packages[&dep_id]);
            let (extern_name, _) = resolve.extern_crate_name_and_dep_name(*id, dep_id, &lib_name)?;
            let mut dep_kinds: Vec<Value> = edges
                .iter()
                .map(|dep| {
                    json!({
                        "kind": dep_kind_json(dep.kind()),
                        "target": dep.platform().map(|p| p.to_string()),
                    })
                })
                .collect();
            dep_kinds.sort_by_key(|v| v.to_string());
            deps.push((
                dep_id,
                json!({
                    "name": extern_name.as_str(),
                    "pkg": spec(dep_id),
                    "dep_kinds": dep_kinds,
                }),
            ));
        }
        deps.sort_by(|a, b| a.0.cmp(&b.0));
        let mut dependencies: Vec<String> = deps.iter().map(|(dep_id, _)| spec(*dep_id)).collect();
        dependencies.sort();
        let mut features: Vec<&str> = resolve.features(*id).iter().map(|f| f.as_str()).collect();
        features.sort();
        nodes.push(json!({
            "id": spec(*id),
            "dependencies": dependencies,
            "deps": deps.into_iter().map(|(_, v)| v).collect::<Vec<_>>(),
            "features": features,
        }));
    }

    let root_dir = root_manifest
        .parent()
        .expect("manifest paths have a parent");
    let mut member_specs: Vec<String> = member_ids.iter().map(|id| spec(*id)).collect();
    member_specs.sort();
    let root = member_ids
        .iter()
        .find(|id| packages[id].manifest_path == normalize(root_manifest))
        .map(|id| spec(*id));

    Ok(json!({
        "packages": package_values,
        "workspace_members": member_specs,
        "workspace_default_members": member_specs,
        "resolve": {
            "nodes": nodes,
            "root": root,
        },
        "target_directory": root_dir.join("target"),
        "version": 1,
        "workspace_root": root_dir,
        "metadata": Value::Null,
    }))
}

fn spec(id: PackageId) -> String {
    id.to_spec().to_string()
}

fn dep_kind_json(kind: DepKind) -> Value {
    match kind {
        DepKind::Normal => Value::Null,
        DepKind::Development => json!("dev"),
        DepKind::Build => json!("build"),
    }
}

/// The crate name of a package's library target, which is what resolve-graph
/// dependency names are expressed in.
fn lib_target_name(info: &PackageInfo) -> String {
    let toml = &info.parsed.normalized_toml;
    toml.lib
        .as_ref()
        .and_then(|lib| lib.name.clone())
        .unwrap_or_else(|| info.summary.name().replace('-', "_"))
}

fn package_json(id: PackageId, info: &PackageInfo) -> Result<Value> {
    let toml = &info.parsed.normalized_toml;
    let package = toml
        .package()
        .expect("resolved packages are not virtual manifests");
    let package_root = info
        .manifest_path
        .parent()
        .expect("manifest paths have a parent");
    let edition = package
        .normalized_edition()?
        .cloned()
        .unwrap_or_else(|| "2015".to_owned());

    let dependencies: Vec<Value> = info
        .summary
        .dependencies()
        .iter()
        .map(|dep| serde_json::to_value(dep.serialized(false)))
        .collect::<Result<_, _>>()
        .context("Failed to serialize dependencies")?;

    let features: BTreeMap<String, Vec<String>> = info
        .summary
        .features()
        .iter()
        .map(|(name, values)| {
            (
                name.to_string(),
                values.iter().map(|v| v.to_string()).collect(),
            )
        })
        .collect();

    let publish = match package.normalized_publish()? {
        None | Some(VecStringOrBool::Bool(true)) => Value::Null,
        Some(VecStringOrBool::Bool(false)) => json!([]),
        Some(VecStringOrBool::VecString(registries)) => json!(registries),
    };
    let source = if id.source_id().is_path() {
        Value::Null
    } else {
        json!(id.source_id().as_url().to_string())
    };

    Ok(json!({
        "name": id.name().as_str(),
        "version": id.version().to_string(),
        "id": spec(id),
        "license": package.normalized_license()?,
        "license_file": package.normalized_license_file()?,
        "description": package.normalized_description()?,
        "source": source,
        "dependencies": dependencies,
        "targets": targets_json(package, toml, package_root, &edition)?,
        "features": features,
        "manifest_path": info.manifest_path,
        "metadata": package.metadata.as_ref().map(serde_json::to_value).transpose()?,
        "publish": publish,
        "authors": package.normalized_authors()?.cloned().unwrap_or_default(),
        "categories": package.normalized_categories()?.cloned().unwrap_or_default(),
        "keywords": package.normalized_keywords()?.cloned().unwrap_or_default(),
        "readme": package.normalized_readme()?,
        "repository": package.normalized_repository()?,
        "homepage": package.normalized_homepage()?,
        "documentation": package.normalized_documentation()?,
        "edition": edition,
        "links": package.links,
        "default_run": package.default_run,
        "rust_version": package.normalized_rust_version()?.map(|v| v.to_string()),
    }))
}

/// The package's targets as `cargo metadata` lists them, from the normalized
/// manifest.
fn targets_json(
    package: &cargo_util_schemas::manifest::TomlPackage,
    toml: &cargo_util_schemas::manifest::TomlManifest,
    package_root: &Utf8Path,
    edition: &str,
) -> Result<Vec<Value>> {
    let mut targets = Vec::new();
    let target = |kind: &[&str],
                  crate_types: &[&str],
                  name: &str,
                  path: &Path,
                  t: Option<&TomlTarget>,
                  defaults: (bool, bool, bool)| {
        let (doc, doctest, test) = defaults;
        let mut value = json!({
            "kind": kind,
            "crate_types": crate_types,
            "name": name,
            "src_path": package_root.join(Utf8Path::from_path(path).expect("UTF-8 target path")),
            "edition": t.and_then(|t| t.edition.clone()).unwrap_or_else(|| edition.to_owned()),
            "doc": t.and_then(|t| t.doc).unwrap_or(doc),
            "doctest": t.and_then(|t| t.doctest).unwrap_or(doctest),
            "test": t.and_then(|t| t.test).unwrap_or(test),
        });
        if let Some(required) = t.and_then(|t| t.required_features.clone()) {
            value["required-features"] = json!(required);
        }
        value
    };
    if let Some(lib) = &toml.lib {
        let crate_types: Vec<&str> = if lib.proc_macro() == Some(true) {
            vec!["proc-macro"]
        } else {
            lib.crate_types()
                .map(|kinds| kinds.iter().map(String::as_str).collect())
                .unwrap_or_else(|| vec!["lib"])
        };
        targets.push(target(
            &crate_types,
            &crate_types,
            lib.name.as_deref().expect("normalized"),
            &lib.path.as_ref().expect("normalized").0,
            Some(lib),
            (true, true, true),
        ));
    }
    for bin in toml.bin.iter().flatten() {
        targets.push(target(
            &["bin"],
            &["bin"],
            bin.name.as_deref().expect("normalized"),
            &bin.path.as_ref().expect("normalized").0,
            Some(bin),
            (true, false, true),
        ));
    }
    for example in toml.example.iter().flatten() {
        let crate_types: Vec<&str> = example
            .crate_types()
            .map(|kinds| kinds.iter().map(String::as_str).collect())
            .unwrap_or_else(|| vec!["bin"]);
        targets.push(target(
            &["example"],
            &crate_types,
            example.name.as_deref().expect("normalized"),
            &example.path.as_ref().expect("normalized").0,
            Some(example),
            (false, false, false),
        ));
    }
    for test in toml.test.iter().flatten() {
        targets.push(target(
            &["test"],
            &["bin"],
            test.name.as_deref().expect("normalized"),
            &test.path.as_ref().expect("normalized").0,
            Some(test),
            (false, false, true),
        ));
    }
    for bench in toml.bench.iter().flatten() {
        targets.push(target(
            &["bench"],
            &["bin"],
            bench.name.as_deref().expect("normalized"),
            &bench.path.as_ref().expect("normalized").0,
            Some(bench),
            (false, false, false),
        ));
    }
    for script in package.normalized_build()?.into_iter().flatten() {
        let path = Path::new(script);
        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .context("build script path has no file stem")?;
        targets.push(target(
            &["custom-build"],
            &["bin"],
            &format!("build-script-{stem}"),
            path,
            None,
            (false, false, false),
        ));
    }
    Ok(targets)
}

/// Platform cfgs for the feature resolver, from the recorded
/// `rustc --print=cfg` table. Without rustc there is nothing to fall back to
/// for a triple the table does not know.
fn recorded_cfgs(triple: &str) -> Result<Vec<Cfg>> {
    match RustcCfgs::recorded().cfg_text(triple) {
        Some(text) => parse_cfgs(&text),
        None => bail!(
            "The platform `{triple}` has no recorded `rustc --print=cfg` output and no rustc is \
             used to ask; add it to `src/metadata/rustc_cfgs.json` with \
             `bazel run //crate_universe:rustc_cfgs.install`"
        ),
    }
}

// ---------------------------------------------------------------------------
// The splice step without Cargo.

/// What the splice step hands to generation, in place of what `cargo metadata`
/// and `cargo generate-lockfile` produced.
pub(crate) struct SplicedWithoutCargo {
    /// The document as `cargo metadata` would print it; what `generate`
    /// reads back from disk.
    pub(crate) metadata_json: Value,
    pub(crate) metadata: cargo_metadata::Metadata,
    pub(crate) lockfile: cargo_lock::Lockfile,
    /// The manifests of the workspace members, for the repository rule to watch.
    pub(crate) member_manifests: Vec<Utf8PathBuf>,
}

/// Resolves the spliced workspace at `manifest_path`, writes its `Cargo.lock`,
/// records sources and features in the root manifest and produces the
/// `cargo metadata` document, all without Cargo.
#[tracing::instrument(skip_all)]
pub(crate) fn splice_without_cargo(
    manifest_path: &Utf8Path,
    existing_lockfile: Option<&Path>,
    repin: Option<&CargoUpdateRequest>,
    target_triples: &BTreeSet<TargetTriple>,
) -> Result<SplicedWithoutCargo> {
    let resolution = resolve_workspace(manifest_path, existing_lockfile, repin, target_triples)?;

    let manifest_dir = manifest_path
        .parent()
        .expect("Every manifest should be contained in a parent directory");
    fs::write(
        manifest_dir.join("Cargo.lock"),
        resolution.lockfile.to_string(),
    )
    .context("Failed to write the resolved lockfile")?;

    crate::splicing::WorkspaceMetadata::write_sources_and_feature_map(
        resolution.sources,
        resolution.tree_metadata,
        manifest_path,
        manifest_path,
    )
    .context("Failed to write registry URLs and feature map")?;

    // `cargo metadata` reports the root manifest's `[workspace.metadata]`, which
    // now carries the cargo-bazel table.
    let root = crate::splicing::read_manifest(manifest_path)?;
    let workspace_metadata = root
        .workspace
        .and_then(|workspace| workspace.metadata)
        .map(serde_json::to_value)
        .transpose()
        .context("Failed to convert workspace metadata")?
        .unwrap_or(Value::Null);
    let mut document = resolution.metadata;
    document["metadata"] = workspace_metadata;

    let metadata: cargo_metadata::Metadata = serde_json::from_value(document.clone())
        .context("The generated metadata is not a valid `cargo metadata` document")?;

    Ok(SplicedWithoutCargo {
        metadata_json: document,
        metadata,
        lockfile: resolution.lockfile,
        member_manifests: resolution.member_manifests,
    })
}
