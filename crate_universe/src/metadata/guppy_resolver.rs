//! Tools for producing Crate metadata using [guppy]'s simulation of Cargo's
//! dependency and feature resolution.
//!
//! [TreeResolverMetadata] is computed in-process from a single `cargo metadata`
//! invocation, simulating one Cargo build per (host, target) platform pair. guppy
//! takes the host and target platforms as independent parameters, so the host a
//! crate's proc-macros and build scripts are built on is simply an input: their
//! dependencies are resolved once per host and recorded under the host triple,
//! which is where Bazel analyzes them (the exec configuration), rather than being
//! fabricated onto every target platform.
//!
//! [guppy]: https://docs.rs/guppy

use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use std::thread;

use anyhow::{bail, Context, Result};
use camino::Utf8Path;
use cargo_resolver::ResolveBehavior;
use guppy::graph::cargo::{CargoOptions, CargoResolverVersion, CargoSet};
use guppy::graph::feature::{FeatureSet, StandardFeatures};
use guppy::graph::{DependencyDirection, PackageGraph, PackageMetadata};
use guppy::platform::{Platform, TargetFeatures};
use tracing::{debug, trace, warn};

use crate::config::CrateId;
use crate::metadata::binary_only::locked_metadata;
use crate::metadata::manifest_parser::resolve_behavior;
use crate::metadata::cargo_bin::Cargo;
use crate::metadata::rustc_cfgs::{print_cfg, RustcCfgs};
use crate::metadata::tree_resolver_metadata::{
    collapse_to_selects, group_by_cargo_triple, host_triples_with_tools, merge_tree_data,
    CargoTreeEntry, PerTripleMetadata, TreeResolverMetadata,
};
use crate::utils::target_triple::TargetTriple;

/// The resolution of a single (host, target) pair, split by which side each crate
/// is built for.
struct PairResolution {
    target_tree_data: BTreeMap<CrateId, CargoTreeEntry>,
    host_tree_data: BTreeMap<CrateId, CargoTreeEntry>,
}

/// Generates metadata about a Cargo workspace tree using guppy's Cargo build
/// simulation.
pub(crate) struct GuppyResolver {
    /// The path to a `cargo` binary
    cargo_bin: Cargo,
}

impl GuppyResolver {
    pub(crate) fn new(cargo_bin: Cargo) -> Self {
        Self { cargo_bin }
    }

    /// Computes the set of enabled features and resolved dependencies for each
    /// target triplet for each crate.
    #[tracing::instrument(name = "GuppyResolver::generate", skip_all)]
    pub(crate) fn generate(
        &self,
        pristine_manifest_path: &Utf8Path,
        target_triples: &BTreeSet<TargetTriple>,
    ) -> Result<TreeResolverMetadata> {
        debug!(
            "Generating features for manifest {} using guppy",
            pristine_manifest_path
        );

        // Only platforms which ship host tools are considered as hosts. guppy itself
        // has no such restriction (the host platform is just another parameter), but a
        // platform without host tools can never be the one a build runs on.
        let host_triples = host_triples_with_tools(target_triples)?;

        // We only want to resolve once per unique cargo platform, then replicate the
        // result across every Bazel triple that maps onto it.
        let cargo_host_triples = group_by_cargo_triple(&host_triples);
        let cargo_target_triples = group_by_cargo_triple(target_triples);

        let (package_graph, metadata) = self.build_package_graph(pristine_manifest_path)?;
        let resolver = resolver_version(pristine_manifest_path)?;

        // Build a `Platform` per unique cargo triple from recorded `rustc --print=cfg`
        // output (see `rustc_cfgs`). Using rustc's own values rather than guppy's
        // built-in target database means `cfg(target_feature = "...")` evaluates the
        // way rustc would. Hosts are a subset of the targets, so the target triples
        // alone cover every platform needed below.
        let mut platforms = BTreeMap::<String, Arc<Platform>>::new();
        let mut platform_cfgs = Vec::<(String, Vec<cargo_platform::Cfg>)>::new();
        for triple in cargo_target_triples.keys() {
            let (platform, cfgs) = self.platform_for_triple(triple)?;
            platforms.insert(triple.clone(), Arc::new(platform));
            platform_cfgs.push((triple.clone(), cfgs));
        }

        ensure_dependencies_resolved(
            pristine_manifest_path,
            &metadata,
            &package_graph,
            &platform_cfgs,
        )?;

        // The initials are what Cargo starts resolution from and do not vary with the
        // platform pair. Building them here also warms the feature graph guppy builds
        // lazily, which the workers below would otherwise race to build a copy of.
        let initials = package_graph
            .resolve_workspace()
            .to_feature_set(StandardFeatures::Default);

        let jobs: Vec<(&String, &String)> = cargo_host_triples
            .keys()
            .flat_map(|host| {
                cargo_target_triples
                    .keys()
                    .map(move |target| (host, target))
            })
            .collect();

        // Each pair is independent and only reads the package graph, so spread them
        // over the available cores rather than resolving `{HOSTS} * {TARGETS}` pairs
        // one at a time.
        let max_parallel = thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4);
        let chunk_size = jobs.len().div_ceil(max_parallel).max(1);

        let resolutions = thread::scope(|scope| -> Result<Vec<PairResolution>> {
            let workers: Vec<_> = jobs
                .chunks(chunk_size)
                .map(|chunk| {
                    let (initials, platforms) = (&initials, &platforms);
                    scope.spawn(move || {
                        chunk
                            .iter()
                            .map(|(host, target)| {
                                resolve_pair(initials, platforms, resolver, host, target)
                            })
                            .collect::<Result<Vec<_>>>()
                    })
                })
                .collect();

            let mut resolutions = Vec::with_capacity(jobs.len());
            for worker in workers {
                resolutions.extend(worker.join().expect("worker thread panicked")?);
            }
            Ok(resolutions)
        })?;

        // Replicate outputs for any de-duplicated platforms. Target-side data is keyed
        // by the target triple and host-side data by the host triple.
        let mut metadata = PerTripleMetadata::new();
        for ((cargo_host, cargo_target), resolution) in jobs.iter().zip(resolutions) {
            for target_plat in &cargo_target_triples[*cargo_target] {
                merge_tree_data(&mut metadata, target_plat, &resolution.target_tree_data);
            }
            for host_plat in &cargo_host_triples[*cargo_host] {
                merge_tree_data(&mut metadata, host_plat, &resolution.host_tree_data);
            }
        }

        Ok(collapse_to_selects(metadata))
    }

    /// Runs `cargo metadata` and builds a guppy [PackageGraph] from the output.
    ///
    /// `--all-features` is required: guppy derives dependency edges from
    /// `resolve.nodes`, which omits optional dependencies that are not enabled by
    /// default. Feature resolution itself is performed by guppy against the
    /// `StandardFeatures::Default` initials, so this only widens the graph guppy is
    /// allowed to see, not the features it reports.
    fn build_package_graph(
        &self,
        manifest_path: &Utf8Path,
    ) -> Result<(PackageGraph, cargo_metadata::Metadata)> {
        let json = locked_metadata(&self.cargo_bin, manifest_path.as_std_path(), true)?;

        let package_graph = PackageGraph::from_json(&json)
            .map_err(anyhow::Error::new)
            .with_context(|| {
                format!(
                    "Failed to build a package graph from the metadata of '{}'",
                    manifest_path
                )
            })?;
        // Parsed a second time with this crate's own `cargo_metadata`, since guppy's
        // copy of the type is private. Only the declared dependencies are read from it.
        let metadata: cargo_metadata::Metadata = serde_json::from_str(&json)
            .with_context(|| format!("Failed to parse the metadata of '{manifest_path}'"))?;

        Ok((package_graph, metadata))
    }

    /// Builds a guppy [Platform] for a cargo target triple from the output of
    /// `rustc --print=cfg --target={triple}`, along with the cfgs themselves.
    fn platform_for_triple(&self, triple: &str) -> Result<(Platform, Vec<cargo_platform::Cfg>)> {
        // The recorded table keeps the resolution independent of the rustc at
        // hand; a triple it does not know, such as a custom target, falls back
        // to asking rustc.
        let cfg_text = match RustcCfgs::recorded().cfg_text(triple) {
            Some(cfg_text) => cfg_text,
            None => {
                warn!(
                    "The platform `{triple}` has no recorded `rustc --print=cfg` output; asking \
                     the current rustc, which makes the resolution depend on its version"
                );
                print_cfg(self.cargo_bin.rustc_path(), triple)?.join("\n")
            }
        };
        let target_features = parse_target_features(&cfg_text);

        let platform = Platform::new_custom_cfg(triple.to_owned(), &cfg_text, target_features)
            .map_err(anyhow::Error::new)
            .with_context(|| format!("Failed to build a platform for the triple '{triple}'"))?;

        Ok((platform, parse_cfgs(&cfg_text)))
    }
}

/// Simulates a Cargo build of the workspace for a single (host, target) pair.
fn resolve_pair<'g>(
    initials: &FeatureSet<'g>,
    platforms: &BTreeMap<String, Arc<Platform>>,
    resolver: CargoResolverVersion,
    cargo_host: &str,
    cargo_target: &str,
) -> Result<PairResolution> {
    trace!("Simulating Cargo build for host `{cargo_host}` targeting `{cargo_target}`");

    let mut opts = CargoOptions::new();
    opts.set_resolver(resolver)
        // Dev-dependencies of workspace members are rendered for their tests.
        .set_include_dev(true)
        .set_host_platform(platforms[cargo_host].clone())
        .set_target_platform(platforms[cargo_target].clone());

    let cargo_set = initials.clone().into_cargo_set(&opts).with_context(|| {
        format!("Failed to simulate Cargo build for host `{cargo_host}` targeting `{cargo_target}`")
    })?;

    Ok(PairResolution {
        target_tree_data: collect_tree_data(
            cargo_set.target_features(),
            target_side_links(&cargo_set),
        ),
        host_tree_data: collect_tree_data(
            cargo_set.host_features(),
            cargo_set.host_links().map(|link| link.endpoints()),
        ),
    })
}

/// The dependency edges belonging to the target side of a build.
///
/// A dependency edge is attributed to the side its *parent* is built for, while
/// a crate's features are attributed to the side that crate itself is built for.
/// Proc-macro and build-dependency links cross from a target parent to a host
/// child, so the edges belong to the target side even though the child's features
/// are reported under the host. guppy keeps those two categories out of both
/// `target_links` and `host_links`, so they have to be folded back in explicitly.
fn target_side_links<'a, 'g>(
    cargo_set: &'a CargoSet<'g>,
) -> impl Iterator<Item = (PackageMetadata<'g>, PackageMetadata<'g>)> + 'a {
    cargo_set
        .target_links()
        .chain(cargo_set.proc_macro_links())
        .chain(cargo_set.build_dep_links())
        .map(|link| link.endpoints())
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
    metadata: &cargo_metadata::Metadata,
    package_graph: &PackageGraph,
    platform_cfgs: &[(String, Vec<cargo_platform::Cfg>)],
) -> Result<()> {
    let lockfile_path = manifest_path
        .parent()
        .expect("manifest paths always have a parent directory")
        .join("Cargo.lock");
    let lockfile = cargo_lock::Lockfile::load(&lockfile_path)
        .with_context(|| format!("Failed to load lockfile '{lockfile_path}'"))?;

    let unresolved = unresolved_dependencies(metadata, &lockfile, package_graph, platform_cfgs);
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
/// `package_graph`, rendered as `name version -> name version`.
///
/// Optional dependencies are skipped (see [ensure_dependencies_resolved]), as are
/// dev-dependencies of packages outside the workspace and dependencies whose
/// `cfg(...)` matches none of `platform_cfgs`, which Cargo never builds.
fn unresolved_dependencies(
    metadata: &cargo_metadata::Metadata,
    lockfile: &cargo_lock::Lockfile,
    package_graph: &PackageGraph,
    platform_cfgs: &[(String, Vec<cargo_platform::Cfg>)],
) -> Vec<String> {
    let resolved: BTreeSet<String> = package_graph
        .packages()
        .map(|package| format!("{} {}", package.name(), package.version()))
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
                || (dependency.kind == cargo_metadata::DependencyKind::Development
                    && !is_workspace_member)
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

/// Parses `rustc --print=cfg` output into the form `cargo_platform` evaluates
/// `[target.'cfg(...)']` dependency tables against.
fn parse_cfgs(cfg_text: &str) -> Vec<cargo_platform::Cfg> {
    cfg_text
        .lines()
        .filter_map(|line| line.trim().parse().ok())
        .collect()
}

/// Extracts the `target_feature="..."` values from `rustc --print=cfg` output.
///
/// `Platform::new_custom_cfg` parses the cfg text for target info but requires target
/// features to be passed separately. Supplying them (instead of
/// [TargetFeatures::Unknown]) matters because guppy treats an unknown result as
/// enabled, which would over-report dependencies gated on `cfg(target_feature = ...)`.
fn parse_target_features(cfg_text: &str) -> TargetFeatures {
    // `TargetFeatures::features` requires `Cow<'static, str>`, so the values must be
    // owned rather than borrowed from `cfg_text`.
    let features: BTreeSet<String> = cfg_text
        .lines()
        .filter_map(|line| line.trim().strip_prefix("target_feature="))
        .map(|value| value.trim_matches('"').to_owned())
        .collect();

    TargetFeatures::features(features)
}

/// Converts a guppy package into the [CrateId] used throughout `cargo-bazel`.
fn crate_id(package: &PackageMetadata<'_>) -> CrateId {
    CrateId::new(package.name().to_owned(), package.version().clone())
}

/// Folds a resolved feature set and its dependency edges into the per-crate shape
/// of [TreeResolverMetadata].
fn collect_tree_data<'g>(
    features: &FeatureSet<'g>,
    links: impl Iterator<Item = (PackageMetadata<'g>, PackageMetadata<'g>)>,
) -> BTreeMap<CrateId, CargoTreeEntry> {
    let mut tree_data = BTreeMap::<CrateId, CargoTreeEntry>::new();

    for feature_list in features.packages_with_features(DependencyDirection::Forward) {
        // `named_features` covers both features declared in `[features]` and the
        // implicit features created by optional dependencies, which is what Cargo
        // reports as a crate's features. The `dep:name` labels guppy also tracks are
        // deliberately excluded.
        tree_data
            .entry(crate_id(feature_list.package()))
            .or_default()
            .features
            .extend(feature_list.named_features().map(str::to_owned));
    }

    for (from, to) in links {
        tree_data
            .entry(crate_id(&from))
            .or_default()
            .deps
            .insert(crate_id(&to));
    }

    tree_data
}

/// The resolver version of the workspace manifest, as guppy names it.
///
/// Cargo picks this up implicitly from the manifest it is pointed at, so the
/// guppy resolver has to read it explicitly to match. Getting this wrong is not a
/// subtle error: the v1 resolver unions features across every platform and ignores
/// target-specific dependency filtering, so target-gated optional dependencies leak
/// onto platforms that should not have them. [resolve_behavior] applies Cargo's own
/// rules through its parser.
fn resolver_version(manifest_path: &Utf8Path) -> Result<CargoResolverVersion> {
    Ok(match resolve_behavior(manifest_path)? {
        ResolveBehavior::V1 => CargoResolverVersion::V1,
        ResolveBehavior::V2 => CargoResolverVersion::V2,
        // `ResolveBehavior` is `#[non_exhaustive]`; anything newer keeps the newest
        // resolver guppy knows about.
        _ => CargoResolverVersion::V3,
    })
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn parse_target_features_from_cfg() {
        let cfg_text = indoc::indoc! {r#"
            debug_assertions
            panic="unwind"
            target_arch="x86_64"
            target_endian="little"
            target_env="gnu"
            target_family="unix"
            target_feature="fxsr"
            target_feature="sse"
            target_feature="sse2"
            target_os="linux"
            target_pointer_width="64"
            unix
        "#};

        assert_eq!(
            TargetFeatures::features(["fxsr", "sse", "sse2"]),
            parse_target_features(cfg_text)
        );
    }

    #[test]
    fn parse_target_features_when_absent() {
        let cfg_text = indoc::indoc! {r#"
            target_arch="wasm32"
            target_endian="little"
            target_family="wasm"
            target_os="unknown"
            target_pointer_width="32"
        "#};

        assert_eq!(
            TargetFeatures::features(std::iter::empty::<&str>()),
            parse_target_features(cfg_text)
        );
    }

    /// Real `rustc --print=cfg --target=x86_64-unknown-linux-gnu` output.
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

    /// A platform built from `rustc --print=cfg` has to evaluate `cfg(...)`
    /// predicates exactly as Cargo does, since that is what decides whether a
    /// target-gated dependency is pulled in.
    #[test]
    fn custom_cfg_platform_evaluates_predicates() {
        let platform = Platform::new_custom_cfg(
            "x86_64-unknown-linux-gnu".to_owned(),
            X86_64_LINUX_GNU_CFG,
            parse_target_features(X86_64_LINUX_GNU_CFG),
        )
        .unwrap();

        for (spec, expected) in [
            (r#"cfg(target_os = "linux")"#, true),
            (r#"cfg(unix)"#, true),
            (r#"cfg(windows)"#, false),
            (r#"cfg(target_arch = "x86_64")"#, true),
            (r#"cfg(target_arch = "aarch64")"#, false),
            (r#"cfg(target_feature = "sse2")"#, true),
            (r#"cfg(target_feature = "avx512f")"#, false),
            // Unrecognized bare flags (`rustix_use_libc`, `miri`, ...) must be
            // false, not unknown, or every dependency gated behind one is pulled
            // in on every platform.
            (r#"cfg(rustix_use_libc)"#, false),
            (r#"cfg(not(rustix_use_libc))"#, true),
        ] {
            let parsed: target_spec::TargetSpec = spec.parse().unwrap();
            assert_eq!(
                Some(expected),
                parsed.eval(&platform),
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
            parse_cfgs(X86_64_LINUX_GNU_CFG),
        )]
    }

    #[test]
    fn lockfile_packages_all_resolved() {
        let package_graph = PackageGraph::from_json(NO_DEPS_METADATA).unwrap();
        let metadata: cargo_metadata::Metadata = serde_json::from_str(NO_DEPS_METADATA).unwrap();
        let lockfile: cargo_lock::Lockfile = indoc::indoc! {r#"
            version = 3

            [[package]]
            name = "no-deps"
            version = "0.1.0"
        "#}
        .parse()
        .unwrap();

        assert!(unresolved_dependencies(
            &metadata,
            &lockfile,
            &package_graph,
            &linux_platform_cfgs()
        )
        .is_empty());
    }

    #[test]
    fn unconditional_dependency_on_a_dropped_package_is_reported() {
        let package_graph = PackageGraph::from_json(NO_DEPS_METADATA).unwrap();
        let metadata = no_deps_metadata_depending_on_shellharden(false, None);
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        assert_eq!(
            vec!["no-deps 0.1.0 -> shellharden 4.3.2".to_owned()],
            unresolved_dependencies(&metadata, &lockfile, &package_graph, &linux_platform_cfgs()),
        );
    }

    /// An optional dependency nothing enables is never built, so a lockfile entry
    /// for it is not a discrepancy.
    #[test]
    fn optional_dependency_on_a_dropped_package_is_ignored() {
        let package_graph = PackageGraph::from_json(NO_DEPS_METADATA).unwrap();
        let metadata = no_deps_metadata_depending_on_shellharden(true, None);
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        assert!(unresolved_dependencies(
            &metadata,
            &lockfile,
            &package_graph,
            &linux_platform_cfgs()
        )
        .is_empty());
    }

    /// `cxx` declares `cxxbridge-cmd` under `[target."cfg(any())".build-dependencies]`
    /// purely to pin its version; no platform ever satisfies it.
    #[test]
    fn dependency_gated_on_an_unsatisfied_cfg_is_ignored() {
        let package_graph = PackageGraph::from_json(NO_DEPS_METADATA).unwrap();
        let lockfile: cargo_lock::Lockfile = NO_DEPS_WITH_SHELLHARDEN_LOCKFILE.parse().unwrap();

        let never = no_deps_metadata_depending_on_shellharden(false, Some("cfg(any())"));
        assert!(
            unresolved_dependencies(&never, &lockfile, &package_graph, &linux_platform_cfgs())
                .is_empty()
        );

        let windows_only = no_deps_metadata_depending_on_shellharden(false, Some("cfg(windows)"));
        assert!(unresolved_dependencies(
            &windows_only,
            &lockfile,
            &package_graph,
            &linux_platform_cfgs()
        )
        .is_empty());

        let unix_only = no_deps_metadata_depending_on_shellharden(false, Some("cfg(unix)"));
        assert_eq!(
            vec!["no-deps 0.1.0 -> shellharden 4.3.2".to_owned()],
            unresolved_dependencies(
                &unix_only,
                &lockfile,
                &package_graph,
                &linux_platform_cfgs()
            ),
        );
    }
}
