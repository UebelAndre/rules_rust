//! cargo_bazel integration tests that run Cargo to test generating metadata.

extern crate cargo_bazel;
extern crate serde_json;
extern crate tempfile;

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{ensure, Context, Result};
use camino::Utf8PathBuf;
use cargo_bazel::cli::{splice, SpliceOptions};
use serde_json::{json, Value};

fn should_skip_test() -> bool {
    // All test cases require network access to build pull crate metadata
    // so that we can actually run `cargo tree`. However, RBE (and perhaps
    // other environments) disallow or don't support this. In those cases,
    // we just skip this test case.
    use std::net::ToSocketAddrs;
    if "github.com:443".to_socket_addrs().is_err() {
        eprintln!("This test case requires network access.");
        true
    } else {
        false
    }
}

fn setup_cargo_env(rfiles: &runfiles::Runfiles) -> Result<(PathBuf, PathBuf)> {
    let cargo = runfiles::rlocation!(
        rfiles,
        env::var("CARGO").context("CARGO environment variable must be set.")?
    )
    .unwrap();
    let rustc = runfiles::rlocation!(
        rfiles,
        env::var("RUSTC").context("RUSTC environment variable must be set.")?
    )
    .unwrap();
    ensure!(cargo.exists());
    ensure!(rustc.exists());
    // If $RUSTC is a relative path it can cause issues with
    // `cargo_metadata::MetadataCommand`. Just to be on the safe side, we make
    // both of these env variables absolute paths.
    if cargo != Path::new(&env::var("CARGO").unwrap()) {
        env::set_var("CARGO", cargo.as_os_str());
    }
    if rustc != Path::new(&env::var("RUSTC").unwrap()) {
        env::set_var("RUSTC", rustc.as_os_str());
    }

    let cargo_home = PathBuf::from(
        env::var("TEST_TMPDIR").context("TEST_TMPDIR environment variable must be set.")?,
    )
    .join("cargo_home");
    env::set_var("CARGO_HOME", cargo_home.as_os_str());
    fs::create_dir_all(&cargo_home)?;

    println!("Environment:");
    println!("\tRUSTC={}", rustc.display());
    println!("\tCARGO={}", cargo.display());
    println!("\tCARGO_HOME={}", cargo_home.display());

    Ok((cargo, rustc))
}

/// The platform triples used by [run]. A small set which still covers a unix, a
/// windows and a non-native target.
const DEFAULT_TEST_TRIPLES: &[&str] = &[
    "wasm32-unknown-unknown",
    "x86_64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-linux-gnu",
];

fn run(repository_name: &str, manifests: HashMap<String, String>, lockfile: &str) -> Value {
    run_with(repository_name, manifests, lockfile, DEFAULT_TEST_TRIPLES)
}

fn run_with(
    repository_name: &str,
    manifests: HashMap<String, String>,
    lockfile: &str,
    supported_platform_triples: &[&str],
) -> Value {
    try_run_with(
        repository_name,
        manifests,
        lockfile,
        supported_platform_triples,
    )
    .unwrap()
}

/// Splices and resolves the given manifests, returning the resulting metadata or
/// the error splicing produced.
fn try_run_with(
    repository_name: &str,
    manifests: HashMap<String, String>,
    lockfile: &str,
    supported_platform_triples: &[&str],
) -> Result<Value> {
    let scratch = tempfile::tempdir().unwrap();
    let runfiles = runfiles::Runfiles::create().unwrap();

    let (cargo, rustc) = setup_cargo_env(&runfiles).unwrap();

    let splicing_manifest = scratch.path().join("splicing_manifest.json");
    fs::write(
        &splicing_manifest,
        serde_json::to_string(&json!({
            "manifests": manifests,
            "direct_packages": {},
            "resolver_version": "2",
        }))
        .unwrap(),
    )
    .unwrap();

    let config = scratch.path().join("config.json");
    fs::write(
        &config,
        serde_json::to_string(&json!({
            "generate_binaries": false,
            "generate_build_scripts": false,
            "rendering": {
                "generate_cargo_toml_env_vars": true,
                "repository_name": repository_name,
                "regen_command": "//crate_universe:cargo_integration_test"
            },
            "supported_platform_triples": supported_platform_triples,
        }))
        .unwrap(),
    )
    .unwrap();

    splice(SpliceOptions {
        splicing_manifest,
        cargo_lockfile: Some(runfiles::rlocation!(runfiles, lockfile).unwrap()),
        repin: None,
        workspace_dir: None,
        output_dir: scratch.path().join("out"),
        dry_run: false,
        cargo_config: None,
        config,
        cargo,
        rustc,
        repository_name: String::from("crates_index"),
        skip_cargo_lockfile_overwrite: false,
        nonhermetic_root_bazel_workspace_dir: Utf8PathBuf::from("/doesnotexist/unused/repo/root"),
    })?;

    let metadata = serde_json::from_str::<Value>(&fs::read_to_string(
        scratch.path().join("out").join("metadata.json"),
    )?)?;

    Ok(metadata)
}

/// `shellharden` ships only a binary. `cargo metadata` drops such a dependency
/// with a warning; the package is put back from its downloaded source so its
/// binary can be built, and the dependent is linked to it in the resolve graph.
#[test]
fn binary_only_dependency_is_resolved() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let (manifests, lockfile) = test_input("bin_only_dep");

    let metadata = run_with("bin_only_dep", manifests, &lockfile, DEFAULT_TEST_TRIPLES);

    let packages = metadata["packages"].as_array().unwrap();
    let shellharden = packages
        .iter()
        .find(|pkg| pkg["name"] == "shellharden")
        .expect("the binary-only package should be in the metadata");
    assert_eq!(
        shellharden["id"],
        "registry+https://github.com/rust-lang/crates.io-index#shellharden@4.3.2"
    );
    assert_eq!(
        shellharden["source"],
        "registry+https://github.com/rust-lang/crates.io-index"
    );
    let target_kinds: Vec<&Value> = shellharden["targets"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|target| target["kind"].as_array().unwrap())
        .collect();
    assert!(target_kinds.contains(&&json!("bin")));
    assert!(!target_kinds.contains(&&json!("lib")));

    let nodes = metadata["resolve"]["nodes"].as_array().unwrap();
    assert!(nodes.iter().any(|node| node["id"] == shellharden["id"]));
    let root = nodes
        .iter()
        .find(|node| node["id"] == metadata["resolve"]["root"])
        .unwrap();
    let edge = root["deps"]
        .as_array()
        .unwrap()
        .iter()
        .find(|dep| dep["pkg"] == shellharden["id"])
        .expect("the workspace member should depend on the binary-only package");
    // Nothing links against a binary-only package, so the edge carries no
    // extern name, as Cargo reports for artifact dependencies.
    assert_eq!(edge["name"], "");
    assert_eq!(edge["dep_kinds"], json!([{"kind": null, "target": null}]));
}

// See crate_universe/test_data/metadata/target_features/Cargo.toml for input.
#[test]
fn feature_generator() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();
    let metadata = run(
        "target_feature_test",
        HashMap::from([(
            runfiles::rlocation!(
                r,
                "rules_rust/crate_universe/test_data/metadata/target_features/Cargo.toml"
            )
            .unwrap()
            .to_string_lossy()
            .to_string(),
            "//:test_input".to_string(),
        )]),
        "rules_rust/crate_universe/test_data/metadata/target_features/Cargo.lock",
    );

    assert_eq!(
        json!({
            "common": {
                "deps": [
                    "arrayvec 0.7.2",
                    "bitflags 1.3.2",
                    "fxhash 0.2.1",
                    "log 0.4.17",
                    "naga 0.10.0",
                    "parking_lot 0.12.1",
                    "profiling 1.0.7",
                    "raw-window-handle 0.5.0",
                    "thiserror 1.0.37",
                    "wgpu-types 0.14.1",
                ],
                "features": [
                    "default",
                ],
            },
            "selects": {
                "x86_64-apple-darwin": {
                    "deps": [
                        "block 0.1.6",
                        "core-graphics-types 0.1.1",
                        "foreign-types 0.3.2",
                        "metal 0.24.0",
                        "objc 0.2.7",
                    ],
                    "features": [
                        "block",
                        "foreign-types",
                        "metal",
                    ],
                },
                "x86_64-pc-windows-msvc": {
                    "deps": [
                        "ash 0.37.1+1.3.235",
                        "bit-set 0.5.3",
                        "d3d12 0.5.0",
                        "gpu-alloc 0.5.3",
                        "gpu-descriptor 0.2.3",
                        "libloading 0.7.4",
                        "range-alloc 0.1.2",
                        "renderdoc-sys 0.7.1",
                        "smallvec 1.10.0",
                        "winapi 0.3.9",
                    ],
                    "features": [
                        "ash",
                        "bit-set",
                        "dx11",
                        "dx12",
                        "gpu-alloc",
                        "gpu-descriptor",
                        "libloading",
                        "native",
                        "range-alloc",
                        "renderdoc",
                        "renderdoc-sys",
                        "smallvec",
                        "vulkan",
                    ],
                },
                "x86_64-unknown-linux-gnu": {
                    "deps": [
                        "ash 0.37.1+1.3.235",
                        "glow 0.11.2",
                        "gpu-alloc 0.5.3",
                        "gpu-descriptor 0.2.3",
                        "khronos-egl 4.1.0",
                        "libloading 0.7.4",
                        "renderdoc-sys 0.7.1",
                        "smallvec 1.10.0",
                    ],
                    "features": [
                        "ash",
                        "egl",
                        "gles",
                        "glow",
                        "gpu-alloc",
                        "gpu-descriptor",
                        "libloading",
                        "renderdoc",
                        "renderdoc-sys",
                        "smallvec",
                        "vulkan",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["wgpu-hal 0.14.1"],
    );
}

// See crate_universe/test_data/metadata/target_cfg_features/Cargo.toml for input.
#[test]
fn feature_generator_cfg_features() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();
    let metadata = run(
        "target_cfg_features_test",
        HashMap::from([(
            runfiles::rlocation!(
                r,
                "rules_rust/crate_universe/test_data/metadata/target_cfg_features/Cargo.toml"
            )
            .unwrap()
            .to_string_lossy()
            .to_string(),
            "//:test_input".to_string(),
        )]),
        "rules_rust/crate_universe/test_data/metadata/target_cfg_features/Cargo.lock",
    );

    assert_eq!(
        json!({
            "autocfg 1.1.0": {
                "selects": {},
            },
            "pin-project-lite 0.2.9": {
                "selects": {},
            },
            "target_cfg_features 0.1.0": {
                "common": {
                    "deps": [
                        "tokio 1.25.0",
                    ],
                },
                "selects": {},
            },
            "tokio 1.25.0": {
                "common": {
                    "deps": [
                        "autocfg 1.1.0",
                        "pin-project-lite 0.2.9",
                    ],
                    "features": [
                        "default",
                    ],
                },
                // Note: "x86_64-pc-windows-msvc" is *not* here, despite
                // being included in `supported_platform_triples` above!
                "selects": {
                    "x86_64-apple-darwin": {
                        "features": [
                            "fs",
                        ],
                    },
                    "x86_64-unknown-linux-gnu": {
                        "features": [
                            "fs",
                        ],
                    },
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"],
    );
}

#[test]
fn feature_generator_workspace() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();
    let metadata = run(
        "workspace_test",
        HashMap::from([
            (
                runfiles::rlocation!(
                    r,
                    "rules_rust/crate_universe/test_data/metadata/workspace/Cargo.toml"
                )
                .unwrap()
                .to_string_lossy()
                .to_string(),
                "//:test_input".to_string(),
            ),
            (
                runfiles::rlocation!(
                    r,
                    "rules_rust/crate_universe/test_data/metadata/workspace/child/Cargo.toml"
                )
                .unwrap()
                .to_string_lossy()
                .to_string(),
                "//crate_universe:test_data/metadata/workspace/child/Cargo.toml".to_string(),
            ),
        ]),
        "rules_rust/crate_universe/test_data/metadata/workspace/Cargo.lock",
    );

    assert!(!metadata["metadata"]["cargo-bazel"]["tree_metadata"]["wgpu 0.14.0"].is_null());
}

#[test]
fn feature_generator_crate_combined_features() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();
    let metadata = run(
        "crate_combined_features",
        HashMap::from([(
            runfiles::rlocation!(
                r,
                "rules_rust/crate_universe/test_data/metadata/crate_combined_features/Cargo.toml"
            )
            .unwrap()
            .to_string_lossy()
            .to_string(),
            "//:test_input".to_string(),
        )]),
        "rules_rust/crate_universe/test_data/metadata/crate_combined_features/Cargo.lock",
    );

    // serde appears twice in the list of dependencies, with and without derive features
    assert_eq!(
        json!({
            "deps": [
                "serde_derive 1.0.158",
            ],
            "features": [
                "default",
                "derive",
                "serde_derive",
                "std",
            ],
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["serde 1.0.158"]["common"],
    );
}

// See crate_universe/test_data/metadata/target_cfg_features/Cargo.toml for input.
#[test]
fn resolver_2_deps() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();
    let metadata = run(
        "resolver_2_deps_test",
        HashMap::from([(
            runfiles::rlocation!(
                r,
                "rules_rust/crate_universe/test_data/metadata/resolver_2_deps/Cargo.toml"
            )
            .unwrap()
            .to_string_lossy()
            .to_string(),
            "//:test_input".to_string(),
        )]),
        "rules_rust/crate_universe/test_data/metadata/resolver_2_deps/Cargo.lock",
    );

    assert_eq!(
        json!({
            "common": {
                "deps": [
                    "bytes 1.6.0",
                    "pin-project-lite 0.2.14",
                ],
                "features": [
                    "bytes",
                    "default",
                    "io-util",
                ],
            },
            // Note that there is no `wasm32-unknown-unknown` entry since all it's dependencies
            // are common. Also note that `mio` is unique to these platforms as it's something
            // that should be excluded from Wasm platforms.
            "selects": {
                "x86_64-apple-darwin": {
                    "deps": [
                        "libc 0.2.153",
                        "mio 0.8.11",
                        "socket2 0.5.7",
                    ],
                    "features": [
                        "io-std",
                        "libc",
                        "mio",
                        "net",
                        "rt",
                        "socket2",
                        "sync",
                        "time",
                    ],
                },
                "x86_64-pc-windows-msvc": {
                    "deps": [
                        "mio 0.8.11",
                        "socket2 0.5.7",
                        "windows-sys 0.48.0",
                    ],
                    "features": [
                        "io-std",
                        "libc",
                        "mio",
                        "net",
                        "rt",
                        "socket2",
                        "sync",
                        "time",
                        "windows-sys",
                    ],
                },
                "x86_64-unknown-linux-gnu": {
                    "deps": [
                        "libc 0.2.153",
                        "mio 0.8.11",
                        "socket2 0.5.7",
                    ],
                    "features": [
                        "io-std",
                        "libc",
                        "mio",
                        "net",
                        "rt",
                        "socket2",
                        "sync",
                        "time",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["tokio 1.37.0"],
    );

    assert_eq!(
        json!({
            // Note linux is not present since linux has no unique dependencies or features
            // for this crate.
            "selects": {
                "wasm32-unknown-unknown": {
                    "deps": [
                        "js-sys 0.3.69",
                        "wasm-bindgen 0.2.92",
                    ],
                },
                "x86_64-apple-darwin": {
                    "deps": [
                        "core-foundation-sys 0.8.6",
                    ],
                },
                "x86_64-pc-windows-msvc": {
                    "deps": [
                        "windows-core 0.52.0",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["iana-time-zone 0.1.60"],
    );
}

#[test]
fn host_specific_build_deps() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let r = runfiles::Runfiles::create().unwrap();

    let src_cargo_toml = runfiles::rlocation!(
        r,
        "rules_rust/crate_universe/test_data/metadata/host_specific_build_deps/Cargo.toml"
    )
    .unwrap();

    // Put Cargo.toml into writable directory structure and create target/ directory to verify that
    // cargo does not incorrectly cache rustc info in target/.rustc_info.json file.
    let scratch = tempfile::tempdir().unwrap();
    let cargo_toml = scratch.path().join("Cargo.toml");
    fs::copy(src_cargo_toml, &cargo_toml).unwrap();
    fs::create_dir(scratch.path().join("target")).unwrap();

    let metadata = run(
        "host_specific_build_deps",
        HashMap::from([(
            cargo_toml.to_string_lossy().to_string(),
            "//:test_input".to_string(),
        )]),
        "rules_rust/crate_universe/test_data/metadata/host_specific_build_deps/Cargo.lock",
    );

    assert_eq!(
        json!({
            "common": {
                "deps": [
                    "bitflags 2.6.0",
                ],
                "features": [
                    "alloc",
                    "default",
                    "fs",
                    "libc-extra-traits",
                    "std",
                    "use-libc-auxv",
                ],
            },
            // Note that there is no `wasm32-unknown-unknown` or `x86_64-pc-windows-msvc` entry
            // since these platforms do not depend on `rustix`. The chain breaks due to the
            // conditions here: https://github.com/Stebalien/tempfile/blob/v3.11.0/Cargo.toml#L25-L33
            "selects": {
                "x86_64-apple-darwin": {
                    "deps": [
                        "errno 0.3.9",
                        "libc 0.2.158",
                    ],
                },
                "x86_64-unknown-linux-gnu": {
                    "deps": [
                        "linux-raw-sys 0.4.14",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["rustix 0.38.36"],
    );

    assert_eq!(
        json!({
            "common": {
                "deps": [
                    "cfg-if 1.0.0",
                    "fastrand 2.1.1",
                    "once_cell 1.19.0",
                ],
            },
            // Note that windows does not contain `rustix` and instead `windows-sys`.
            // This shows correct detection of exec platform constraints.
            "selects": {
                "x86_64-apple-darwin": {
                    "deps": [
                        "rustix 0.38.36",
                    ],
                },
                "x86_64-pc-windows-msvc": {
                    "deps": [
                        "windows-sys 0.59.0",
                    ],
                },
                "x86_64-unknown-linux-gnu": {
                    "deps": [
                        "rustix 0.38.36",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["tempfile 3.12.0"],
    );
}

/// Every platform triple `rules_rust` supports, passed through from
/// `SUPPORTED_PLATFORM_TRIPLES` in `//rust/platform:triple_mappings.bzl` by the
/// `cargo_integration_test` target so the two cannot drift.
///
/// `aarch64-unknown-nixos-gnu` and `x86_64-unknown-nixos-gnu` are Bazel-only
/// spellings which `TargetTriple::to_cargo` remaps onto their `linux` equivalents;
/// every other entry is a triple `rustc` knows.
fn all_supported_triples() -> Vec<&'static str> {
    env!("SUPPORTED_PLATFORM_TRIPLES").split(',').collect()
}

/// The manifests and lockfile of a `crate_universe/test_data/metadata` directory.
fn test_input(name: &str) -> (HashMap<String, String>, String) {
    let r = runfiles::Runfiles::create().unwrap();
    let manifests = HashMap::from([(
        runfiles::rlocation!(
            r,
            format!("rules_rust/crate_universe/test_data/metadata/{name}/Cargo.toml")
        )
        .unwrap()
        .to_string_lossy()
        .to_string(),
        "//:test_input".to_string(),
    )]);

    (
        manifests,
        format!("rules_rust/crate_universe/test_data/metadata/{name}/Cargo.lock"),
    )
}

/// The `target_features` test data, which pulls in `wgpu` and so resolves very
/// differently per platform.
const TARGET_FEATURES: &str = "target_features";

/// The workspace member of the `target_features` test data.
const TARGET_FEATURES_ROOT: &str = "target_features 0.1.0";

/// The subset of [DEFAULT_TEST_TRIPLES] which ship host tools, and so can be used
/// on their own: resolution always needs a host to build proc-macros and build
/// scripts with.
const DEFAULT_TEST_HOST_TRIPLES: &[&str] = &[
    "x86_64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-linux-gnu",
];

/// The deps and features a crate resolves to on a single platform.
struct Resolution {
    deps: BTreeSet<String>,
    features: BTreeSet<String>,
}

/// Flattens the resolution of a single crate for a single platform.
///
/// `tree_metadata` entries are stored as a `Select`: whatever is common to every
/// platform the crate is built for, plus per-platform additions. Which bucket an
/// entry lands in depends on the whole platform list, so comparisons across
/// different platform lists have to be made on the union of the two.
///
/// Note that this is only meaningful for a platform the crate is actually built
/// for. A `Select` does not record which platforms an entry covers, so this
/// happily returns the `common` bucket for a platform that never builds the crate
/// at all, and `common` shifts as platforms are added and removed. A crate only
/// ever built for the exec platform, such as a proc-macro's dependencies, has
/// entries under host triples and none under the targets being built for.
fn flatten_for(entry: &Value, triple: &str) -> Resolution {
    let common = &entry["common"];
    let selected = &entry["selects"][triple];

    let union = |key: &str| -> BTreeSet<String> {
        [common.get(key), selected.get(key)]
            .into_iter()
            .flatten()
            .filter_map(Value::as_array)
            .flatten()
            .map(|item| item.as_str().unwrap().to_owned())
            .collect()
    };

    Resolution {
        deps: union("deps"),
        features: union("features"),
    }
}

/// Reconstructs what a single platform actually resolves to, by walking the
/// dependency edges reachable from `root`.
///
/// `tree_metadata` holds an entry for every crate on every platform that builds
/// it, so a crate that is only built on Windows still has an entry visible from a
/// wasm build. Walking from the root package is what makes the per-platform view
/// well defined: it is also what the rendered `BUILD` files express, since a crate
/// nothing depends on for a platform is never built for it.
fn resolution_for(tree_metadata: &Value, triple: &str, root: &str) -> BTreeMap<String, Resolution> {
    let mut resolved = BTreeMap::new();
    let mut stack = vec![root.to_owned()];

    while let Some(crate_id) = stack.pop() {
        let Some(entry) = tree_metadata.get(&crate_id) else {
            continue;
        };
        if resolved.contains_key(&crate_id) {
            continue;
        }

        let resolution = flatten_for(entry, triple);
        stack.extend(resolution.deps.iter().cloned());
        resolved.insert(crate_id, resolution);
    }

    resolved
}

/// Resolution has to cover every supported platform, not just the ones the machine
/// running the generator happens to build for: dependencies pinned on a macOS host
/// must be buildable on a Windows or Linux host targeting, say,
/// `wasm32-unknown-unknown`.
///
/// This resolves against every triple in [all_supported_triples], the full
/// `{hosts with tools} * {targets}` matrix.
#[test]
fn all_supported_platforms_resolve() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let (manifests, lockfile) = test_input(TARGET_FEATURES);

    let all_triples = all_supported_triples();

    let wide = run_with("all_platforms", manifests.clone(), &lockfile, &all_triples);

    let wide = &wide["metadata"]["cargo-bazel"]["tree_metadata"];

    // A platform only reachable with the wider list resolves its own dependencies,
    // rather than being dropped or given another platform's.
    let ios = resolution_for(wide, "aarch64-apple-ios", TARGET_FEATURES_ROOT);
    assert!(
        ios.contains_key("metal 0.24.0"),
        "aarch64-apple-ios should resolve the metal backend, got {:?}",
        ios.keys().collect::<Vec<_>>(),
    );
    assert!(
        !ios.contains_key("d3d12 0.5.0"),
        "aarch64-apple-ios should not resolve a windows backend",
    );

    let android = resolution_for(wide, "aarch64-linux-android", TARGET_FEATURES_ROOT);
    assert!(
        android.contains_key("ash 0.37.1+1.3.235"),
        "aarch64-linux-android should resolve the vulkan backend, got {:?}",
        android.keys().collect::<Vec<_>>(),
    );

    // Widening the platform list shifts entries between `common` and `selects`, and
    // a crate built only for the exec platform gains entries as hosts are added, but
    // no platform may gain or lose a crate.
    let narrow = run_with(
        "all_platforms",
        manifests.clone(),
        &lockfile,
        DEFAULT_TEST_TRIPLES,
    );
    let narrow = &narrow["metadata"]["cargo-bazel"]["tree_metadata"];

    for triple in DEFAULT_TEST_TRIPLES {
        assert_eq!(
            resolution_for(narrow, triple, TARGET_FEATURES_ROOT)
                .into_keys()
                .collect::<BTreeSet<_>>(),
            resolution_for(wide, triple, TARGET_FEATURES_ROOT)
                .into_keys()
                .collect::<BTreeSet<_>>(),
            "the crates resolved for `{triple}` changed when the supported platform \
             list was widened from {} to {} triples",
            DEFAULT_TEST_TRIPLES.len(),
            all_triples.len(),
        );
    }

    // Whichever machine runs the generator, every platform must come out resolved
    // as though it had been resolved on its own. Resolving a single triple pins
    // host and target together, which is the one case where a `Select` is
    // unambiguous: `common` holds the whole resolution and `selects` is empty.
    for host in DEFAULT_TEST_HOST_TRIPLES {
        let alone = run_with("all_platforms", manifests.clone(), &lockfile, &[host]);
        let alone = &alone["metadata"]["cargo-bazel"]["tree_metadata"];

        for (crate_id, entry) in alone.as_object().unwrap() {
            let alone = flatten_for(entry, host);
            let Some(entry) = wide.get(crate_id) else {
                panic!(
                    "`{crate_id}` is resolved when `{host}` is the only supported \
                     platform, but is missing entirely from the {}-platform resolution",
                    all_triples.len(),
                );
            };
            let wide = flatten_for(entry, host);

            assert!(
                alone.deps.is_subset(&wide.deps),
                "`{crate_id}` depends on {:?} on `{host}`, but those edges are lost once \
                 the supported platform list is widened to {} triples",
                alone.deps.difference(&wide.deps),
                all_triples.len(),
            );
            assert!(
                alone.features.is_subset(&wide.features),
                "`{crate_id}` enables {:?} on `{host}`, but those features are lost once \
                 the supported platform list is widened to {} triples",
                alone.features.difference(&wide.features),
                all_triples.len(),
            );
        }
    }
}

/// A crate depended on both by the target and, for a build script, by the host can
/// legitimately resolve to two different feature sets. Cargo's v2 resolver keeps
/// them apart and builds the crate twice; `crate_universe` renders one target per
/// crate version, so the two sets get unioned under the host's triple.
///
/// This pins that behaviour rather than endorsing it. `TreeResolverMetadata` is
/// keyed by platform triple alone, so it has nowhere to record "these are the
/// features this crate has when built for the exec platform" separately from "these
/// are the features it has when built for this target". Both resolvers therefore
/// unify host and target features whenever the two triples coincide, which is what
/// Cargo's *v1* resolver did, whatever resolver version the manifest asks for.
///
/// Note that the cross-compile case comes out right: `wasm32-unknown-unknown` never
/// builds the build script, so it gets the target's feature set and nothing else.
/// Only a native build over-approximates.
#[test]
fn host_and_target_features_are_unified_per_triple() {
    if should_skip_test() {
        eprintln!("Skipping!");
        return;
    }

    let (manifests, lockfile) = test_input("host_target_feature_split");
    let metadata = run("host_target_feature_split", manifests, &lockfile);

    assert_eq!(
        json!({
            "common": {
                "deps": [
                    "cfg-if 1.0.0",
                ],
            },
            "selects": {
                // `std` belongs to the build script's copy of `log`, which is built
                // for the exec platform. The target's copy asks for no features at
                // all, but shares this entry.
                "x86_64-apple-darwin": {
                    "features": [
                        "std",
                    ],
                },
                "x86_64-pc-windows-msvc": {
                    "features": [
                        "std",
                    ],
                },
                "x86_64-unknown-linux-gnu": {
                    "features": [
                        "std",
                    ],
                },
            },
        }),
        metadata["metadata"]["cargo-bazel"]["tree_metadata"]["log 0.4.17"],
    );
}
