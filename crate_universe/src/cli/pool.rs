//! The `pool` subcommand: render the shared crate repositories and the hub
//! alias layers for every hub of a module extension. See [crate::pool].

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{bail, Context as AnyhowContext, Result};
use clap::Parser;
use serde::{Deserialize, Serialize};

use crate::config::{Config, CrateId, RenderConfig};
use crate::context::Context;
use crate::metadata::SourceAnnotation;
use crate::pool::{closure_hashes, pool_repository_name};
use crate::rendering::{render_module_label, Renderer};

/// The `repository_name` crate BUILD files are rendered under. Nothing in a
/// pooled crate's BUILD file may depend on the hub it was rendered for, so this
/// stands in for every hub.
const POOL_REPOSITORY_NAME: &str = "crate_universe";

/// The regeneration instructions written into pooled crate BUILD files.
const POOL_REGEN_COMMAND: &str = "repin any crate_universe repository depending on this crate";

#[derive(Parser, Debug)]
#[clap(about = "Command line options for the `pool` subcommand", version)]
pub struct PoolOptions {
    /// A JSON list of the hubs to pool: `[{"name": ..., "lockfile": ..., "config": ...}]`.
    #[clap(long)]
    pub hubs: PathBuf,

    /// The directory to write `pool.json`, the shared repositories' BUILD files
    /// and each hub's files into.
    #[clap(long)]
    pub output_dir: PathBuf,
}

/// One hub to pool.
#[derive(Debug, Deserialize)]
struct Hub {
    name: String,
    lockfile: PathBuf,
    config: PathBuf,
}

/// What the module extension needs to declare the repositories.
#[derive(Debug, Default, Serialize)]
struct PoolManifest {
    /// The shared repositories, keyed by name.
    repositories: BTreeMap<String, PoolRepository>,

    /// Each hub's files, keyed by hub name.
    hubs: BTreeMap<String, PoolHub>,
}

#[derive(Debug, Serialize)]
struct PoolRepository {
    name: String,
    version: String,
    repository: SourceAnnotation,
    /// The crate's BUILD file, relative to the output directory.
    build_file: String,
}

#[derive(Debug, Default, Serialize)]
struct PoolHub {
    /// The hub's files, relative to `hubs/<name>/` in the output directory.
    files: Vec<String>,
    /// The per-alias subpackages among them.
    hub_packages: Vec<String>,
}

pub fn pool(opt: PoolOptions) -> Result<()> {
    let hubs: Vec<Hub> = serde_json::from_str(
        &fs::read_to_string(&opt.hubs)
            .with_context(|| format!("Failed to read {}", opt.hubs.display()))?,
    )
    .context("Failed to parse the hubs to pool")?;

    let mut manifest = PoolManifest::default();
    let mut outputs: BTreeMap<PathBuf, String> = BTreeMap::new();

    for hub in hubs {
        let config = Config::try_from_path(&hub.config)
            .with_context(|| format!("Failed to load the config of hub `{}`", hub.name))?;
        let context = Context::try_from_path(&hub.lockfile)
            .with_context(|| format!("Failed to load the lockfile of hub `{}`", hub.name))?
            .for_rendering(&config)?;

        let hashes = closure_hashes(&context, &config);
        let pool_repositories: Arc<BTreeMap<CrateId, String>> = Arc::new(
            context
                .crates
                .iter()
                .filter(|(_, krate)| krate.repository.is_some())
                .map(|(id, _)| (id.clone(), pool_repository_name(id, &hashes[id])))
                .collect(),
        );
        let supported_platform_triples = Arc::new(config.supported_platform_triples.clone());
        let conditions = Arc::new(context.conditions.clone());

        // Crate BUILD files are rendered under a hub independent config, so equal
        // closures render identically whichever hub they came from.
        let pool_renderer = Renderer::with_pool_repositories(
            Arc::new(RenderConfig {
                repository_name: POOL_REPOSITORY_NAME.to_owned(),
                regen_command: POOL_REGEN_COMMAND.to_owned(),
                ..config.rendering.clone()
            }),
            Arc::clone(&supported_platform_triples),
            Arc::clone(&pool_repositories),
        );
        let platforms = pool_renderer.render_platform_labels(Arc::clone(&conditions));
        let engine = pool_renderer.create_engine(Arc::clone(&conditions));
        for (id, krate) in &context.crates {
            let Some(repository) = &krate.repository else {
                continue;
            };
            let repository_name = &pool_repositories[id];
            let build_file = PathBuf::from("pool")
                .join(repository_name)
                .join("BUILD.bazel");
            let content = pool_renderer
                .render_one_build_file(&engine, &platforms, krate)
                .with_context(|| format!("Failed to render the BUILD file of `{id}`"))?;

            match outputs.get(&build_file) {
                // The closure hash covers everything the BUILD file is rendered
                // from, so a second hub arriving at the same repository must
                // render the same file.
                Some(existing) if existing != &content => bail!(
                    "`{id}` renders differently in hub `{}` than in an earlier hub despite \
                     having the same closure `{repository_name}`; the closure hash is \
                     missing an input",
                    hub.name,
                ),
                Some(_) => {}
                None => {
                    manifest.repositories.insert(
                        repository_name.clone(),
                        PoolRepository {
                            name: krate.name.clone(),
                            version: krate.version.to_string(),
                            repository: repository.clone(),
                            build_file: build_file.to_string_lossy().into_owned(),
                        },
                    );
                    outputs.insert(build_file, content);
                }
            }
        }

        // The hub itself keeps its own render config: aliases, `defs.bzl` and
        // friends are what the hub's templates are for.
        let hub_renderer = Renderer::with_pool_repositories(
            Arc::new(config.rendering.clone()),
            supported_platform_triples,
            pool_repositories,
        );
        let rendered = hub_renderer
            .render_hub_files(&context, None)
            .with_context(|| format!("Failed to render hub `{}`", hub.name))?;

        // The hub's templates place its files under a package (`//<hub>:{file}`
        // by default); the hub repository wants them at its root.
        let module_dir = Renderer::label_to_path(&render_module_label(
            &config.rendering.crates_module_template,
            "BUILD.bazel",
        )?)
        .parent()
        .map(PathBuf::from)
        .unwrap_or_default();
        let mut files = Vec::new();
        for (path, content) in rendered.files {
            let relative = path
                .strip_prefix(&module_dir)
                .unwrap_or(&path)
                .to_path_buf();
            files.push(relative.to_string_lossy().into_owned());
            outputs.insert(
                PathBuf::from("hubs").join(&hub.name).join(relative),
                content,
            );
        }
        manifest.hubs.insert(
            hub.name,
            PoolHub {
                files,
                hub_packages: rendered.hub_packages,
            },
        );
    }

    outputs.insert(
        PathBuf::from("pool.json"),
        serde_json::to_string_pretty(&manifest)?,
    );
    for (path, content) in outputs {
        let path = opt.output_dir.join(path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, content).with_context(|| format!("Failed to write {}", path.display()))?;
    }

    Ok(())
}
