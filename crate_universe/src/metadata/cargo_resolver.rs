//! Tools for producing crate metadata with Cargo's own dependency and feature
//! resolver, through the `cargo_resolver` crate extracted from Cargo.
//!
//! [TreeResolverMetadata] is computed in-process from a single `cargo metadata`
//! invocation. The package graph `cargo metadata` reports is rebuilt as Cargo's
//! `Resolve`, and Cargo's feature resolver runs over it once per (host, target)
//! platform pair, with the host an explicit input rather than the machine at
//! hand: the dependencies of proc-macros and build scripts are resolved for the
//! platform that builds them and recorded under that triple, which is where Bazel
//! analyzes them (the exec configuration).
//!
//! `cfg(...)` dependencies are evaluated against the recorded `rustc --print=cfg`
//! table (see `rustc_cfgs`), so the resolution does not depend on the rustc at
//! hand.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::thread;

use anyhow::{bail, Context, Result};
use camino::Utf8Path;
use cargo_metadata::{DependencyKind, Metadata, Package, TargetKind};
use cargo_platform3::{Cfg, Platform};
use cargo_resolver::interning::InternedString;
use cargo_resolver::{
    CargoResult, CliFeatures, CompileKind, CompileTarget, DepKind, Dependency, FeatureOpts,
    FeatureResolver, FeatureResolverHost, FeaturesFor, Graph, HasDevUnits, PackageId, Resolve,
    ResolveBehavior, ResolveVersion, ResolvedFeatures, SourceId, Summary,
};
use cargo_util_schemas::lockfile::TomlLockfileMetadata;
use cargo_util_schemas::manifest::RustVersion;
use rustc_hash::{FxHashMap, FxHashSet};
use tracing::{debug, trace, warn};

use crate::config::CrateId;
use crate::metadata::binary_only::locked_metadata;
use crate::metadata::cargo_bin::Cargo;
use crate::metadata::manifest_parser::resolve_behavior;
use crate::metadata::rustc_cfgs::{print_cfg, RustcCfgs};
use crate::metadata::tree_resolver_metadata::{
    collapse_to_selects, group_by_cargo_triple, host_triples_with_tools, merge_tree_data,
    CargoTreeEntry, PerTripleMetadata, TreeResolverMetadata,
};
use crate::utils::target_triple::TargetTriple;

/// Generates metadata about a Cargo workspace tree using Cargo's feature resolver.
pub(crate) struct CargoResolver {
    /// The path to a `cargo` binary
    cargo_bin: Cargo,
}

impl CargoResolver {
    pub(crate) fn new(cargo_bin: Cargo) -> Self {
        Self { cargo_bin }
    }

    /// Computes the set of enabled features and resolved dependencies for each
    /// target triplet for each crate.
    ///
    /// The signature and return value match [crate::metadata::TreeResolver::generate]
    /// so the two are interchangeable.
    #[tracing::instrument(name = "CargoResolver::generate", skip_all)]
    pub(crate) fn generate(
        &self,
        pristine_manifest_path: &Utf8Path,
        target_triples: &BTreeSet<TargetTriple>,
    ) -> Result<TreeResolverMetadata> {
        debug!(
            "Generating features for manifest {} using cargo-resolver",
            pristine_manifest_path
        );

        let host_triples = host_triples_with_tools(target_triples)?;
        let cargo_host_triples = group_by_cargo_triple(&host_triples);
        let cargo_target_triples = group_by_cargo_triple(target_triples);

        let metadata = self.cargo_metadata(pristine_manifest_path)?;
        let behavior = resolve_behavior(pristine_manifest_path)?;

        // Platform `cfg`s per unique cargo triple, from the recorded
        // `rustc --print=cfg` output. Hosts are a subset of the targets, so the
        // target triples alone cover every platform needed below.
        let mut cfgs: HashMap<String, Vec<Cfg>> = HashMap::new();
        let mut platform_cfgs = Vec::<(String, Vec<cargo_platform::Cfg>)>::new();
        for triple in cargo_target_triples.keys() {
            let text = self.cfg_text(triple)?;
            cfgs.insert(triple.clone(), parse_cfgs(&text)?);
            platform_cfgs.push((triple.clone(), parse_metadata_cfgs(&text)));
        }

        ensure_dependencies_resolved(pristine_manifest_path, &metadata, &platform_cfgs)?;

        // Cargo's `Resolve` and `Summary` are `Rc`-based, so each worker builds its
        // own graph from the parsed metadata (milliseconds) and takes a slice of
        // the (host, target) pairs.
        let pairs: Vec<(&String, &String)> = cargo_host_triples
            .keys()
            .flat_map(|host| cargo_target_triples.keys().map(move |target| (host, target)))
            .collect();
        let max_parallel = thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4);
        let chunk_size = pairs.len().div_ceil(max_parallel).max(1);

        let resolutions = thread::scope(|scope| -> Result<Vec<PairResolution>> {
            let workers: Vec<_> = pairs
                .chunks(chunk_size)
                .map(|chunk| {
                    let (metadata, cfgs) = (&metadata, &cfgs);
                    scope.spawn(move || -> Result<Vec<PairResolution>> {
                        let graph = ResolveGraph::build(metadata)?;
                        chunk
                            .iter()
                            .map(|(host, target)| resolve_pair(&graph, cfgs, behavior, host, target))
                            .collect()
                    })
                })
                .collect();
            let mut resolutions = Vec::with_capacity(pairs.len());
            for worker in workers {
                resolutions.extend(worker.join().expect("worker thread panicked")?);
            }
            Ok(resolutions)
        })?;

        // Target-side data is keyed by the target triple and host-side data by the
        // host triple, matching how `TreeResolver` splits `cargo tree` output.
        let mut per_triple = PerTripleMetadata::new();
        for ((cargo_host, cargo_target), resolution) in pairs.iter().zip(resolutions) {
            for target_plat in &cargo_target_triples[*cargo_target] {
                merge_tree_data(&mut per_triple, target_plat, &resolution.target_tree_data);
            }
            for host_plat in &cargo_host_triples[*cargo_host] {
                merge_tree_data(&mut per_triple, host_plat, &resolution.host_tree_data);
            }
        }

        Ok(collapse_to_selects(per_triple))
    }

    /// Runs `cargo metadata --all-features --locked`, completed with the
    /// binary-only packages `cargo metadata` drops.
    ///
    /// `--all-features` is required: the `resolve` section omits optional
    /// dependencies that are not enabled by default, and Cargo's feature resolver
    /// needs the complete graph to narrow.
    fn cargo_metadata(&self, manifest_path: &Utf8Path) -> Result<Metadata> {
        let json = locked_metadata(&self.cargo_bin, manifest_path.as_std_path(), true)?;
        serde_json::from_str(&json)
            .with_context(|| format!("Failed to parse the metadata of '{manifest_path}'"))
    }

    /// The `rustc --print=cfg` output for a cargo triple.
    ///
    /// The recorded table keeps the resolution independent of the rustc at hand;
    /// a triple it does not know, such as a custom target, falls back to asking
    /// rustc.
    fn cfg_text(&self, triple: &str) -> Result<String> {
        match RustcCfgs::recorded().cfg_text(triple) {
            Some(cfg_text) => Ok(cfg_text),
            None => {
                warn!(
                    "The platform `{triple}` has no recorded `rustc --print=cfg` output; asking \
                     the current rustc, which makes the resolution depend on its version"
                );
                Ok(print_cfg(self.cargo_bin.rustc_path(), triple)?.join("\n"))
            }
        }
    }
}

/// Parses `rustc --print=cfg` output into the form Cargo's feature resolver
/// evaluates `[target.'cfg(...)']` dependency tables against.
pub(super) fn parse_cfgs(cfg_text: &str) -> Result<Vec<Cfg>> {
    cfg_text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| {
            line.parse::<Cfg>()
                .with_context(|| format!("parsing cfg `{line}`"))
        })
        .collect()
}

/// The same, in the `cargo_platform` version `cargo_metadata` reports
/// dependency targets with.
fn parse_metadata_cfgs(cfg_text: &str) -> Vec<cargo_platform::Cfg> {
    cfg_text
        .lines()
        .filter_map(|line| line.trim().parse().ok())
        .collect()
}

/// Fails if a package depends, unconditionally, on a package which `cargo metadata`
/// left out.
///
/// `cargo metadata` drops any dependency on a package without a library target
/// (`warning: ignoring invalid dependency ... which is missing a lib target`),
/// together with everything reachable only through it. `cargo build` ignores such
/// dependencies the same way, so this matches Cargo. The features such a package
/// would have enabled on its library dependencies are simply never applied, which
/// is easy to mistake for a resolution bug, so surface the discrepancy instead.
///
/// `Cargo.lock` is the complete package set, so anything in it that is not in the
/// metadata was dropped this way. Only unconditional dependencies on such a package
/// are reported: an optional one which nothing enables, or one behind a `cfg(...)`
/// no configured platform satisfies, is never built by Cargo in the first place,
/// yet still sits in the lockfile.
fn ensure_dependencies_resolved(
    manifest_path: &Utf8Path,
    metadata: &Metadata,
    platform_cfgs: &[(String, Vec<cargo_platform::Cfg>)],
) -> Result<()> {
    let lockfile_path = manifest_path
        .parent()
        .expect("manifest paths always have a parent directory")
        .join("Cargo.lock");
    let lockfile = cargo_lock::Lockfile::load(&lockfile_path)
        .with_context(|| format!("Failed to load lockfile '{lockfile_path}'"))?;

    let unresolved = unresolved_dependencies(metadata, &lockfile, platform_cfgs);
    if unresolved.is_empty() {
        return Ok(());
    }

    bail!(
        "Dependencies on packages which `cargo metadata` did not resolve: [{}]. Cargo \
         omits dependencies without a library target; those from registries are put \
         back from their downloaded sources, so this is a dependency which could not \
         be recovered. Please report it to rules_rust.",
        unresolved.join(", "),
    )
}

/// Every `package -> dependency` edge whose dependency is in the lockfile but not in
/// `metadata`, rendered as `name version -> name version`.
///
/// Optional dependencies are skipped (see [ensure_dependencies_resolved]), as are
/// dev-dependencies of packages outside the workspace and dependencies whose
/// `cfg(...)` matches none of `platform_cfgs`, which Cargo never builds.
fn unresolved_dependencies(
    metadata: &Metadata,
    lockfile: &cargo_lock::Lockfile,
    platform_cfgs: &[(String, Vec<cargo_platform::Cfg>)],
) -> Vec<String> {
    let resolved: BTreeSet<String> = metadata
        .packages
        .iter()
        .map(|package| format!("{} {}", package.name, package.version))
        .collect();
    let missing: Vec<&cargo_lock::Package> = lockfile
        .packages
        .iter()
        .filter(|package| !resolved.contains(&format!("{} {}", package.name, package.version)))
        .collect();
    if missing.is_empty() {
        return Vec::new();
    }

    let mut unresolved = Vec::new();
    for package in &metadata.packages {
        let is_workspace_member = metadata.workspace_members.contains(&package.id);
        for dependency in &package.dependencies {
            if dependency.optional
                || (dependency.kind == DependencyKind::Development && !is_workspace_member)
            {
                continue;
            }
            let enabled_somewhere = dependency.target.as_ref().is_none_or(|target| {
                platform_cfgs
                    .iter()
                    .any(|(triple, cfgs)| target.matches(triple, cfgs))
            });
            if !enabled_somewhere {
                continue;
            }
            for dropped in &missing {
                if dropped.name.as_str() == dependency.name
                    && dependency.req.matches(&dropped.version)
                {
                    unresolved.push(format!(
                        "{} {} -> {} {}",
                        package.name, package.version, dropped.name, dropped.version
                    ));
                }
            }
        }
    }
    unresolved.sort();
    unresolved.dedup();
    unresolved
}

/// Runs Cargo's feature resolver over `graph` for every (host, target) pair and
/// folds the result into [TreeResolverMetadata], as [CargoResolver::generate]
/// does, but on one thread over a graph the caller already built: Cargo's
/// `Resolve` is `Rc` based and cannot be shared across threads.
pub(crate) fn feature_tree_metadata(
    graph: &ResolveGraph,
    behavior: ResolveBehavior,
    target_triples: &BTreeSet<TargetTriple>,
    cfgs_for: impl Fn(&str) -> Result<Vec<Cfg>>,
) -> Result<TreeResolverMetadata> {
    let host_triples = host_triples_with_tools(target_triples)?;
    let cargo_host_triples = group_by_cargo_triple(&host_triples);
    let cargo_target_triples = group_by_cargo_triple(target_triples);

    let mut cfgs: HashMap<String, Vec<Cfg>> = HashMap::new();
    for triple in cargo_target_triples.keys() {
        cfgs.insert(triple.clone(), cfgs_for(triple)?);
    }

    let mut per_triple = PerTripleMetadata::new();
    for (cargo_host, host_plats) in &cargo_host_triples {
        for (cargo_target, target_plats) in &cargo_target_triples {
            let resolution = resolve_pair(graph, &cfgs, behavior, cargo_host, cargo_target)?;
            for target_plat in target_plats {
                merge_tree_data(&mut per_triple, target_plat, &resolution.target_tree_data);
            }
            for host_plat in host_plats {
                merge_tree_data(&mut per_triple, host_plat, &resolution.host_tree_data);
            }
        }
    }
    Ok(collapse_to_selects(per_triple))
}

/// The resolution of a single (host, target) pair, split by which side each crate
/// is built for.
struct PairResolution {
    target_tree_data: BTreeMap<CrateId, CargoTreeEntry>,
    host_tree_data: BTreeMap<CrateId, CargoTreeEntry>,
}

fn resolve_pair(
    graph: &ResolveGraph,
    cfgs: &HashMap<String, Vec<Cfg>>,
    behavior: ResolveBehavior,
    cargo_host: &str,
    cargo_target: &str,
) -> Result<PairResolution> {
    trace!("Resolving features for host `{cargo_host}` targeting `{cargo_target}`");

    let compile_target = CompileTarget::new(cargo_target, false)?;
    let requested = [CompileKind::Target(compile_target)];
    let mut env = Env {
        host: InternedString::new(cargo_host),
        cfgs,
        proc_macro: &graph.proc_macro,
    };
    let resolved = FeatureResolver::resolve(
        &mut env,
        &graph.resolve,
        &graph.members,
        &requested,
        // `cargo tree` was invoked with `--edges normal,build,dev`.
        FeatureOpts::new_behavior(behavior, HasDevUnits::Yes),
    )
    .with_context(|| format!("Failed to resolve features for host `{cargo_host}` targeting `{cargo_target}`"))?;

    let (target_tree_data, host_tree_data) = split_sides(&resolved, graph, &env, &requested);
    Ok(PairResolution {
        target_tree_data,
        host_tree_data,
    })
}

// ---------------------------------------------------------------------------
// The dependency graph, as Cargo's `Resolve`.

pub(crate) struct ResolveGraph {
    pub(crate) resolve: Resolve,
    pub(crate) members: Vec<(PackageId, CliFeatures)>,
    /// Whether each package has a proc-macro target.
    pub(crate) proc_macro: HashMap<PackageId, bool>,
}

impl ResolveGraph {
    pub(crate) fn new(
        resolve: Resolve,
        members: Vec<(PackageId, CliFeatures)>,
        proc_macro: HashMap<PackageId, bool>,
    ) -> Self {
        Self {
            resolve,
            members,
            proc_macro,
        }
    }

    fn build(metadata: &Metadata) -> Result<Self> {
        let resolve_section = metadata
            .resolve
            .as_ref()
            .context("`cargo metadata` output has no `resolve` section")?;

        let mut ids: HashMap<&cargo_metadata::PackageId, PackageId> = HashMap::new();
        let mut summaries: FxHashMap<PackageId, Summary> = FxHashMap::default();
        let mut proc_macro = HashMap::new();
        for package in &metadata.packages {
            let id = package_id(package)?;
            ids.insert(&package.id, id);
            summaries.insert(id, summary(package, id)?);
            proc_macro.insert(
                id,
                package
                    .targets
                    .iter()
                    .any(|t| t.kind.contains(&TargetKind::ProcMacro)),
            );
        }

        let mut graph: Graph<PackageId, FxHashSet<Dependency>> = Graph::new();
        let mut features: FxHashMap<PackageId, Vec<InternedString>> = FxHashMap::default();
        for node in &resolve_section.nodes {
            let parent = *ids
                .get(&node.id)
                .with_context(|| format!("unknown resolve node {}", node.id))?;
            graph.add(parent);
            features.insert(
                parent,
                node.features.iter().map(|f| InternedString::new(f)).collect(),
            );
            let parent_summary = &summaries[&parent];
            for node_dep in &node.deps {
                let child = *ids
                    .get(&node_dep.pkg)
                    .with_context(|| format!("unknown resolve dependency {}", node_dep.pkg))?;
                // Cargo's edge set is every declaration of `parent` that resolved to
                // `child`; `dep_kinds` lists exactly those, one `(kind, target)` each.
                let edge = graph.link(parent, child);
                for decl in parent_summary.dependencies() {
                    if decl.package_name() != child.name() {
                        continue;
                    }
                    let decl_target = decl.platform().map(ToString::to_string);
                    let listed = node_dep.dep_kinds.iter().any(|dk| {
                        dep_kind(dk.kind) == decl.kind()
                            && dk.target.as_ref().map(ToString::to_string) == decl_target
                    });
                    if listed {
                        edge.insert(decl.clone());
                    }
                }
                if edge.is_empty() {
                    bail!(
                        "no declaration of `{}` matches its resolved dependency `{}`",
                        parent,
                        child
                    );
                }
            }
        }

        let members = metadata
            .workspace_members
            .iter()
            .map(|m| {
                ids.get(m)
                    .copied()
                    .map(|id| (id, CliFeatures::new_all(false)))
                    .with_context(|| format!("unknown workspace member {m}"))
            })
            .collect::<Result<Vec<_>>>()?;

        let resolve = Resolve::new(
            graph,
            FxHashMap::default(),
            features,
            FxHashMap::default(),
            TomlLockfileMetadata::default(),
            Vec::new(),
            ResolveVersion::max_stable(),
            summaries,
        );
        Ok(Self {
            resolve,
            members,
            proc_macro,
        })
    }
}

fn package_id(package: &Package) -> Result<PackageId> {
    let source = match &package.source {
        Some(source) => SourceId::from_url(&source.repr)?,
        None => SourceId::for_path(
            package
                .manifest_path
                .parent()
                .context("manifest path has no parent")?
                .as_std_path(),
        )?,
    };
    Ok(PackageId::new(
        InternedString::new(&package.name),
        package.version.clone(),
        source,
    ))
}

fn dependency(dep: &cargo_metadata::Dependency) -> Result<Dependency> {
    let source = match (&dep.source, &dep.path) {
        (Some(source), _) => SourceId::from_url(source)?,
        (None, Some(path)) => SourceId::for_path(path.as_std_path())?,
        (None, None) => bail!("dependency `{}` has neither a source nor a path", dep.name),
    };
    let mut out = Dependency::parse(dep.name.as_str(), Some(&dep.req.to_string()), source)?;
    if let Some(rename) = &dep.rename {
        out.set_explicit_name_in_toml(rename.as_str());
    }
    if dep.registry.is_some() && !source.is_crates_io() {
        out.set_registry_id(source);
    }
    let platform = match &dep.target {
        Some(target) => Some(
            target
                .to_string()
                .parse::<Platform>()
                .with_context(|| format!("parsing target `{target}`"))?,
        ),
        None => None,
    };
    out.set_optional(dep.optional)
        .set_default_features(dep.uses_default_features)
        .set_features(dep.features.iter().map(String::as_str))
        .set_platform(platform)
        .set_kind(dep_kind(dep.kind));
    Ok(out)
}

fn dep_kind(kind: DependencyKind) -> DepKind {
    match kind {
        DependencyKind::Development => DepKind::Development,
        DependencyKind::Build => DepKind::Build,
        _ => DepKind::Normal,
    }
}

fn summary(package: &Package, id: PackageId) -> Result<Summary> {
    let deps = package
        .dependencies
        .iter()
        .map(dependency)
        .collect::<Result<Vec<_>>>()
        .with_context(|| format!("dependencies of {}", package.id))?;
    let features: BTreeMap<InternedString, Vec<InternedString>> = package
        .features
        .iter()
        .map(|(k, v)| {
            (
                InternedString::new(k),
                v.iter().map(|s| InternedString::new(s)).collect(),
            )
        })
        .collect();
    let rust_version = package
        .rust_version
        .as_ref()
        .map(|v| v.to_string().parse::<RustVersion>())
        .transpose()?;
    Summary::new(id, deps, &features, package.links.as_deref(), rust_version)
        .with_context(|| format!("summary of {}", package.id))
}

// ---------------------------------------------------------------------------
// The environment the feature resolver asks about.

struct Env<'a> {
    host: InternedString,
    cfgs: &'a HashMap<String, Vec<Cfg>>,
    proc_macro: &'a HashMap<PackageId, bool>,
}

impl Env<'_> {
    fn triple<'k>(&'k self, kind: &'k CompileKind) -> &'k str {
        match kind {
            CompileKind::Host => self.host.as_str(),
            CompileKind::Target(t) => t.short_name(),
        }
    }
}

impl FeatureResolverHost for Env<'_> {
    fn host_triple(&self) -> InternedString {
        self.host
    }

    fn dep_platform_activated(&self, dep: &Dependency, kind: CompileKind) -> bool {
        let Some(platform) = dep.platform() else {
            return true;
        };
        let name = self.triple(&kind);
        let cfg = self
            .cfgs
            .get(name)
            .unwrap_or_else(|| panic!("no cfg was queried for `{name}`"));
        platform.matches(name, cfg)
    }

    fn activate_target(&mut self, kind: CompileKind) -> CargoResult<()> {
        let name = self.triple(&kind);
        if !self.cfgs.contains_key(name) {
            bail!("target `{name}` was not among the triples queried from rustc");
        }
        Ok(())
    }

    fn has_any_proc_macro(&self, package_id: PackageId) -> bool {
        self.proc_macro.get(&package_id).copied().unwrap_or(false)
    }

    fn has_proc_macro_lib(&self, package_id: PackageId) -> bool {
        self.proc_macro.get(&package_id).copied().unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// From `ResolvedFeatures` to per-side tree data.

fn crate_id(id: PackageId) -> CrateId {
    CrateId::new(id.name().to_string(), id.version().clone())
}

/// Mirror of the feature resolver's own platform rule for a dependency.
fn platform_activated(
    dep: &Dependency,
    fk: FeaturesFor,
    env: &Env<'_>,
    requested: &[CompileKind],
) -> bool {
    match (dep.is_build(), fk) {
        (true, _) | (_, FeaturesFor::HostDep) => env.dep_platform_activated(dep, CompileKind::Host),
        (_, FeaturesFor::NormalOrDev) => requested
            .iter()
            .any(|k| env.dep_platform_activated(dep, *k)),
        (_, FeaturesFor::ArtifactDep(t)) => env.dep_platform_activated(dep, CompileKind::Target(t)),
    }
}

/// Walks the graph from the workspace members the way `cargo tree` does.
///
/// Features come from the side a crate is built for; a dependency edge is
/// attributed to the side its *parent* is built for. Only crates reachable
/// through platform-active edges are reported, which matters under resolver v1,
/// where the feature resolver activates packages on every platform.
fn split_sides(
    resolved: &ResolvedFeatures,
    graph: &ResolveGraph,
    env: &Env<'_>,
    requested: &[CompileKind],
) -> (
    BTreeMap<CrateId, CargoTreeEntry>,
    BTreeMap<CrateId, CargoTreeEntry>,
) {
    let mut target_side = BTreeMap::<CrateId, CargoTreeEntry>::new();
    let mut host_side = BTreeMap::<CrateId, CargoTreeEntry>::new();
    let mut seen = HashSet::<(PackageId, bool)>::new();
    let mut queue: Vec<(PackageId, bool)> = graph
        .members
        .iter()
        // As `cargo tree` does: a member with any proc-macro target is a host root.
        .map(|(member, _)| (*member, env.has_any_proc_macro(*member)))
        .collect();
    while let Some((pkg, for_host)) = queue.pop() {
        if !seen.insert((pkg, for_host)) {
            continue;
        }
        let fk = FeaturesFor::from_for_host(for_host);
        let side = if for_host {
            &mut host_side
        } else {
            &mut target_side
        };
        let entry = side.entry(crate_id(pkg)).or_default();
        if let Some(features) = resolved.activated_features_unverified(pkg, fk) {
            entry
                .features
                .extend(features.iter().map(|f| f.to_string()));
        }
        for (dep_id, deps) in graph.resolve.deps(pkg) {
            for dep in deps {
                if dep.platform().is_some() && !platform_activated(dep, fk, env, requested) {
                    continue;
                }
                if dep.is_optional() && !resolved.is_dep_activated(pkg, fk, dep.name_in_toml()) {
                    continue;
                }
                entry.deps.insert(crate_id(dep_id));
                // As `cargo tree` does: build deps and packages with any proc-macro
                // target are built for the host.
                let child_for_host = for_host || dep.is_build() || env.has_any_proc_macro(dep_id);
                queue.push((dep_id, child_for_host));
            }
        }
    }
    (target_side, host_side)
}

#[cfg(test)]
mod test {
    use super::*;

    const X86_64_LINUX_GNU_CFG: &str = indoc::indoc! {r#"
        debug_assertions
        panic="unwind"
        target_abi=""
        target_arch="x86_64"
        target_endian="little"
        target_env="gnu"
        target_family="unix"
        target_feature="fxsr"
        target_feature="sse"
        target_feature="sse2"
        target_has_atomic="16"
        target_has_atomic="32"
        target_has_atomic="64"
        target_has_atomic="8"
        target_has_atomic="ptr"
        target_has_atomic_primitive_alignment="16"
        target_has_atomic_primitive_alignment="32"
        target_has_atomic_primitive_alignment="64"
        target_has_atomic_primitive_alignment="8"
        target_has_atomic_primitive_alignment="ptr"
        target_os="linux"
        target_pointer_width="64"
        target_vendor="unknown"
        unix
    "#};

    /// Cargo evaluates `cfg(...)` predicates against `rustc --print=cfg`
    /// output; that is what decides whether a target-gated dependency is pulled in.
    #[test]
    fn recorded_cfgs_evaluate_predicates_as_cargo_does() {
        let cfgs = parse_cfgs(X86_64_LINUX_GNU_CFG).unwrap();
        for (spec, expected) in [
            (r#"cfg(target_os = "linux")"#, true),
            (r#"cfg(unix)"#, true),
            (r#"cfg(windows)"#, false),
            (r#"cfg(target_arch = "x86_64")"#, true),
            (r#"cfg(target_arch = "aarch64")"#, false),
            (r#"cfg(target_feature = "sse2")"#, true),
            (r#"cfg(target_feature = "avx512f")"#, false),
            // Unrecognized bare flags (`rustix_use_libc`, `miri`, ...) must be
            // false, or every dependency gated behind one is pulled in on every
            // platform.
            (r#"cfg(rustix_use_libc)"#, false),
            (r#"cfg(not(rustix_use_libc))"#, true),
        ] {
            let platform: Platform = spec.parse().unwrap();
            assert_eq!(
                expected,
                platform.matches("x86_64-unknown-linux-gnu", &cfgs),
                "unexpected evaluation of `{spec}`"
            );
        }
    }

    /// `cargo metadata` output for `test_data/metadata/no_deps`, a workspace with a
    /// single package and nothing else.
    const NO_DEPS_METADATA: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/test_data/metadata/no_deps/metadata.json"
    ));

    /// A lockfile for `no_deps` which also lists `shellharden`, as it would if the
    /// package declared a dependency on it: a binary-only package stays in the
    /// lockfile while `cargo metadata` leaves it out.
    const NO_DEPS_WITH_SHELLHARDEN_LOCKFILE: &str = indoc::indoc! {r#"
        version = 3

        [[package]]
        name = "no-deps"
        version = "0.1.0"
        dependencies = [
         "shellharden",
        ]

        [[package]]
        name = "shellharden"
        version = "4.3.2"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        checksum = "0000000000000000000000000000000000000000000000000000000000000000"
    "#};

    /// The `no_deps` metadata with a dependency on `shellharden` declared by its
    /// package, which `cargo metadata` would have dropped from `resolve`.
    fn no_deps_metadata_depending_on_shellharden(
        optional: bool,
        target: Option<&str>,
    ) -> cargo_metadata::Metadata {
        let mut metadata: serde_json::Value = serde_json::from_str(NO_DEPS_METADATA).unwrap();
        metadata["packages"][0]["dependencies"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!({
                "name": "shellharden",
                "source": "registry+https://github.com/rust-lang/crates.io-index",
                "req": "=4.3.2",
                "kind": null,
                "rename": null,
                "optional": optional,
                "uses_default_features": true,
                "features": [],
                "target": target,
                "registry": null,
            }));
        serde_json::from_value(metadata).unwrap()
    }

    /// The cfgs of a single linux platform, as `generate` would collect them.
    fn linux_platform_cfgs() -> Vec<(String, Vec<cargo_platform::Cfg>)> {
        vec![(
            "x86_64-unknown-linux-gnu".to_owned(),
            parse_metadata_cfgs(X86_64_LINUX_GNU_CFG),
        )]
    }

    #[test]
    fn lockfile_packages_all_resolved() {
        let metadata: cargo_metadata::Metadata = serde_json::from_str(NO_DEPS_METADATA).unwrap();
        let lockfile: cargo_lock::Lockfile = indoc::indoc! {r#"
            version = 3

            [[package]]
            name = "no-deps"
            version = "0.1.0"
        "#}
        .parse()
        .unwrap();

        assert!(unresolved_dependencies(&metadata, &lockfile, &linux_platform_cfgs()).is_empty());
    }

    #[test]
    fn unconditional_dependency_on_a_dropped_package_is_reported() {
        let metadata = no_deps_metadata_depending_on_shellharden(false, None);
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        assert_eq!(
            vec!["no-deps 0.1.0 -> shellharden 4.3.2".to_owned()],
            unresolved_dependencies(&metadata, &lockfile, &linux_platform_cfgs()),
        );
    }

    /// An optional dependency nothing enables is never built, so a lockfile entry
    /// for it is not a discrepancy.
    #[test]
    fn optional_dependency_on_a_dropped_package_is_ignored() {
        let metadata = no_deps_metadata_depending_on_shellharden(true, None);
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        assert!(unresolved_dependencies(&metadata, &lockfile, &linux_platform_cfgs()).is_empty());
    }

    /// `cxx` declares `cxxbridge-cmd` under `[target."cfg(any())".build-dependencies]`
    /// purely to pin its version; no platform ever satisfies it.
    #[test]
    fn dependency_gated_on_an_unsatisfied_cfg_is_ignored() {
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        let never = no_deps_metadata_depending_on_shellharden(false, Some("cfg(any())"));
        assert!(unresolved_dependencies(&never, &lockfile, &linux_platform_cfgs()).is_empty());

        let windows_only = no_deps_metadata_depending_on_shellharden(false, Some("cfg(windows)"));
        assert!(unresolved_dependencies(&windows_only, &lockfile, &linux_platform_cfgs()).is_empty());

        let unix_only = no_deps_metadata_depending_on_shellharden(false, Some("cfg(unix)"));
        assert_eq!(
            vec!["no-deps 0.1.0 -> shellharden 4.3.2".to_owned()],
            unresolved_dependencies(&unix_only, &lockfile, &linux_platform_cfgs()),
        );
    }
}
