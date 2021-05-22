use std::{collections::HashMap, fs::File, io::Write};

use indoc::{formatdoc, indoc};

use tempfile::TempDir;

use crate::{
    metadata::{
        tests::{mock_raze_metadata_fetcher, DummyCargoMetadataFetcher},
        CrateMetadata, DEFAULT_CRATE_INDEX_URL, DEFAULT_CRATE_REGISTRY_URL,
    },
    settings::{GenMode, PlanningSettings},
};

/// A module containing constants for each metadata template
pub mod templates {
    pub const BASIC_METADATA: &str = "basic_metadata.json.template";
    pub const MOCK_MODIFIED_METADATA: &str = "mock_modified_metadata.json.template";
    pub const PLAN_BUILD_PRODUCES_ALIASED_DEPENDENCIES: &str =
        "plan_build_produces_aliased_dependencies.json.template";
    pub const PLAN_BUILD_PRODUCES_BUILD_PROC_MACRO_DEPENDENCIES: &str =
        "plan_build_produces_build_proc_macro_dependencies.json.template";
    pub const PLAN_BUILD_PRODUCES_PROC_MACRO_DEPENDENCIES: &str =
        "plan_build_produces_proc_macro_dependencies.json.template";
    pub const SEMVER_MATCHING: &str = "semver_matching.json.template";
    pub const SUBPLAN_PRODUCES_CRATE_ROOT_WITH_FORWARD_SLASH: &str =
        "subplan_produces_crate_root_with_forward_slash.json.template";
}

pub const fn basic_toml_contents() -> &'static str {
    indoc! { r#"
    [package]
    name = "test"
    version = "0.0.1"
  
    [lib]
    path = "not_a_file.rs"
  "# }
}

pub const fn basic_lock_contents() -> &'static str {
    indoc! { r#"
    [[package]]
    name = "test"
    version = "0.0.1"
    dependencies = [
    ]
  "# }
}

pub const fn advanced_toml_contents() -> &'static str {
    indoc! { r#"
    [package]
    name = "cargo-raze-test"
    version = "0.1.0"

    [lib]
    path = "not_a_file.rs"

    [dependencies]
    proc-macro2 = "1.0.24"
  "# }
}

pub const fn advanced_lock_contents() -> &'static str {
    indoc! { r#"
    # This file is automatically @generated by Cargo.
    # It is not intended for manual editing.
    [[package]]
    name = "cargo-raze-test"
    version = "0.1.0"
    dependencies = [
      "proc-macro2",
    ]

    [[package]]
    name = "proc-macro2"
    version = "1.0.24"
    source = "registry+https://github.com/rust-lang/crates.io-index"
    checksum = "1e0704ee1a7e00d7bb417d0770ea303c1bccbabf0ef1667dae92b5967f5f8a71"
    dependencies = [
      "unicode-xid",
    ]

    [[package]]
    name = "unicode-xid"
    version = "0.2.1"
    source = "registry+https://github.com/rust-lang/crates.io-index"
    checksum = "f7fe0bb3479651439c9112f72b6c505038574c9fbb575ed1bf3b797fa39dd564"
  "# }
}

pub fn named_toml_contents(name: &str, version: &str) -> String {
    formatdoc! { r#"
    [package]
    name = "{name}"
    version = "{version}"

    [lib]
    path = "not_a_file.rs"

  "#, name = name, version = version }
}

pub fn make_workspace(toml_file: &str, lock_file: Option<&str>) -> TempDir {
    let dir = TempDir::new().unwrap();
    // Create Cargo.toml
    {
        let path = dir.path().join("Cargo.toml");
        let mut toml = File::create(&path).unwrap();
        toml.write_all(toml_file.as_bytes()).unwrap();
    }

    if let Some(lock_file) = lock_file {
        let path = dir.path().join("Cargo.lock");
        let mut lock = File::create(&path).unwrap();
        lock.write_all(lock_file.as_bytes()).unwrap();
    }

    File::create(dir.as_ref().join("WORKSPACE.bazel")).unwrap();
    dir
}

pub fn make_basic_workspace() -> TempDir {
    make_workspace(basic_toml_contents(), Some(basic_lock_contents()))
}

pub fn make_workspace_with_dependency() -> TempDir {
    make_workspace(advanced_toml_contents(), Some(advanced_lock_contents()))
}

/// Generate CrateMetadata from a cargo metadata template
pub fn template_raze_metadata(template_path: &str) -> CrateMetadata {
    let dir = make_basic_workspace();
    let mut fetcher = mock_raze_metadata_fetcher();

    // Always render basic metadata
    fetcher.set_metadata_fetcher(Box::new(DummyCargoMetadataFetcher {
        metadata_template: Some(template_path.to_string()),
    }));

    fetcher.fetch_metadata(dir.as_ref(), None).unwrap()
}

pub fn mock_graph_settings() -> PlanningSettings {
    PlanningSettings {
        workspace_path: "//cargo".to_owned(),
        // package_aliases_dir: "cargo".to_owned(),
        // render_package_aliases: default_render_package_aliases(),
        // target: Some("x86_64-unknown-linux-gnu".to_owned()),
        targets: None,
        crates: HashMap::new(),
        gen_workspace_prefix: "crate_graph_test".to_owned(),
        genmode: GenMode::Remote,
        // output_buildfile_suffix: "BUILD".to_owned(),
        default_gen_buildrs: true,
        registry: format!(
            "{}/{}",
            DEFAULT_CRATE_REGISTRY_URL, "api/v1/crates/{crate}/{version}/download"
        ),
        index_url: DEFAULT_CRATE_INDEX_URL.to_owned(),
        // rust_rules_workspace_name: default_raze_settings_rust_rules_workspace_name(),
        // vendor_dir: default_raze_settings_vendor_dir(),
        // experimental_api: default_raze_settings_experimental_api(),
    }
}
