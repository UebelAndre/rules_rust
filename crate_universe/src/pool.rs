//! Sharing crate repositories between hubs.
//!
//! Every hub of the `crate` module extension used to get its own repository for
//! every crate it resolved, so two hubs depending on the same `clap` fetched and
//! built it twice. Instead, each crate is identified by its *closure*: a hash of
//! everything that shapes its BUILD file - the crate's resolved context, the
//! closures of its dependencies, and the render settings which reach into crate
//! BUILD files. Crates with equal closures are the same compile unit no matter
//! which hub they came from, so they share one repository named after the crate
//! and its closure.
//!
//! Hubs then hold nothing but aliases into those repositories.

use std::collections::{BTreeMap, BTreeSet};

use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::config::{Config, CrateId};
use crate::context::crate_context::CrateDependency;
use crate::context::Context;
use crate::select::Select;
use crate::utils::sanitize_repository_name;

/// The length of the closure hash kept in repository names: ample for
/// distinguishing closures of one crate version, short enough to keep paths short.
const CLOSURE_HASH_LENGTH: usize = 10;

/// The render settings which reach into crate BUILD files, and so are part of
/// the identity of a crate's closure. Everything else in a hub's render config
/// only shapes the hub's own files.
#[derive(Serialize)]
struct RenderSettings<'a> {
    platforms_template: &'a str,
    generate_rules_license_metadata: bool,
    generate_cargo_toml_env_vars: bool,
    supported_platform_triples: &'a BTreeSet<crate::utils::target_triple::TargetTriple>,
}

/// Computes the closure hash of every crate in `context`.
///
/// Dev-dependencies are not part of a closure: they are only rendered for
/// workspace members, which are never shared.
pub(crate) fn closure_hashes(context: &Context, config: &Config) -> BTreeMap<CrateId, String> {
    let settings = serde_json::to_value(RenderSettings {
        platforms_template: &config.rendering.platforms_template,
        generate_rules_license_metadata: config.rendering.generate_rules_license_metadata,
        generate_cargo_toml_env_vars: config.rendering.generate_cargo_toml_env_vars,
        supported_platform_triples: &config.supported_platform_triples,
    })
    .expect("render settings are serializable");

    let mut hashes = BTreeMap::new();
    let mut in_progress = BTreeSet::new();
    for id in context.crates.keys() {
        closure_hash(id, context, &settings, &mut hashes, &mut in_progress);
    }
    hashes
}

fn closure_hash(
    id: &CrateId,
    context: &Context,
    settings: &serde_json::Value,
    hashes: &mut BTreeMap<CrateId, String>,
    in_progress: &mut BTreeSet<CrateId>,
) -> String {
    if let Some(hash) = hashes.get(id) {
        return hash.clone();
    }
    // Cargo's normal and build dependency graphs are acyclic, so this only
    // guards against malformed input; the cycle is hashed as such rather than
    // recursed into.
    if !in_progress.insert(id.clone()) {
        return "cycle".to_owned();
    }

    let krate = &context.crates[id];
    let mut dependency_hashes = BTreeMap::new();
    for dependency in dependencies(krate) {
        if dependency.id == *id || !context.crates.contains_key(&dependency.id) {
            continue;
        }
        let hash = closure_hash(&dependency.id, context, settings, hashes, in_progress);
        dependency_hashes.insert(dependency.id.clone(), hash);
    }

    #[derive(Serialize)]
    struct Payload<'a> {
        krate: &'a crate::context::CrateContext,
        dependencies: &'a BTreeMap<CrateId, String>,
        settings: &'a serde_json::Value,
    }
    let payload = serde_json::to_vec(&Payload {
        krate,
        dependencies: &dependency_hashes,
        settings,
    })
    .expect("crate contexts are serializable");
    let hash = hex::encode(Sha256::digest(payload));

    in_progress.remove(id);
    hashes.insert(id.clone(), hash.clone());
    hash
}

/// Every dependency which is rendered into a crate's BUILD file.
fn dependencies(krate: &crate::context::CrateContext) -> Vec<CrateDependency> {
    let mut deps = Vec::new();
    let mut extend = |select: &Select<BTreeSet<CrateDependency>>| deps.extend(select.values());
    extend(&krate.common_attrs.deps);
    extend(&krate.common_attrs.proc_macro_deps);
    if let Some(build_script) = &krate.build_script_attrs {
        extend(&build_script.deps);
        extend(&build_script.link_deps);
        extend(&build_script.proc_macro_deps);
    }
    deps
}

/// The name of the shared repository holding `id` at `closure`.
pub(crate) fn pool_repository_name(id: &CrateId, closure: &str) -> String {
    sanitize_repository_name(&format!(
        "{}-{}-{}",
        id.name,
        id.version,
        &closure[..CLOSURE_HASH_LENGTH.min(closure.len())]
    ))
}

#[cfg(test)]
mod test {
    use super::*;

    use camino::Utf8Path;
    use semver::Version;

    use crate::config::{CrateAnnotations, CrateNameAndVersionReq};
    use crate::metadata::Annotations;

    fn rendered_context(config: &Config) -> Context {
        let annotations = Annotations::new(
            crate::test::metadata::common(),
            &None,
            crate::test::lockfile::common(),
            Utf8Path::new("/tmp/bazelworkspace"),
        )
        .unwrap();
        Context::new(annotations, &config.supported_platform_triples)
            .unwrap()
            .for_rendering(config)
            .unwrap()
    }

    #[test]
    fn closure_hashes_are_stable_and_distinguish_closures() {
        let config = Config::default();
        let context = rendered_context(&config);
        let bitflags = CrateId::new("bitflags".to_owned(), Version::new(1, 3, 2));

        let first = closure_hashes(&context, &config);
        let second = closure_hashes(&context, &config);
        assert_eq!(first, second);
        assert_eq!(first[&bitflags].len(), 64);

        // An annotation on a crate changes that crate's closure and nothing
        // which does not depend on it.
        let mut annotated = Config::default();
        annotated.annotations.insert(
            CrateNameAndVersionReq::new("bitflags".to_owned(), "1.3.2".parse().unwrap()),
            CrateAnnotations {
                rustc_flags: Some(Select::from_value(vec!["--cfg=marker".to_owned()])),
                ..CrateAnnotations::default()
            },
        );
        let changed = closure_hashes(&rendered_context(&annotated), &annotated);
        assert_ne!(first[&bitflags], changed[&bitflags]);
        let cfg_if = CrateId::new("cfg-if".to_owned(), Version::new(1, 0, 0));
        assert_eq!(first[&cfg_if], changed[&cfg_if]);

        // Render settings which reach into crate BUILD files are part of the closure.
        let mut platforms = Config::default();
        platforms.rendering.platforms_template = "@my//platform:{triple}".to_owned();
        let changed = closure_hashes(&rendered_context(&platforms), &platforms);
        assert_ne!(first[&bitflags], changed[&bitflags]);
    }

    #[test]
    fn pool_repository_names_are_valid_and_short() {
        let id = CrateId::new(
            "semver".to_owned(),
            Version::parse("1.0.0+build.1").unwrap(),
        );
        assert_eq!(
            pool_repository_name(&id, "0123456789abcdef"),
            "semver-1.0.0-build.1-0123456789"
        );
    }
}
