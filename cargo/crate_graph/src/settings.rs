// Copyright 2018 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::PathBuf,
};

use semver::VersionReq;
use serde::{Deserialize, Serialize};

use crate::metadata::{DEFAULT_CRATE_INDEX_URL, DEFAULT_CRATE_REGISTRY_URL};

/// Configuration settings for the `planning` phase
#[derive(Debug, Clone, Deserialize)]
pub struct PlanningSettings {
    /// The path to write BUILD file outputs to.
    ///
    /// This may be a workspace-relative path (e.g. `//foo/bar`) or a path relative to the `Cargo.toml` file's directory
    /// (e.g. if the Cargo metadata file is `//foo:Cargo.toml`, this could be `third_party` to put
    /// outputs in `//foo/third_party`.)
    pub workspace_path: String,

    /// A list of targets to generate BUILD rules for.
    ///
    /// Each item comes in the form of a "triple", such as "x86_64-unknown-linux-gnu"
    #[serde(default)]
    pub targets: Option<HashSet<String>>,

    /// Prefix for generated Bazel workspaces (from workspace_rules)
    ///
    /// This is only useful with remote genmode. It prefixes the names of the workspaces for
    /// dependencies (@PREFIX_crateName_crateVersion) as well as the name of the repository function
    /// generated in crates.bzl (PREFIX_fetch_remote_crates()).
    #[serde(default = "default_planning_settings_field_gen_workspace_prefix")]
    pub gen_workspace_prefix: String,

    /// How to generate the dependencies. See GenMode for details.
    #[serde(default = "default_planning_settings_field_genmode")]
    pub genmode: GenMode,

    /// Default value for per-crate gen_buildrs setting if it's not explicitly for a crate.
    ///
    /// See [crate::settings::CrateSettings::gen_buildrs] for more information.
    #[serde(default = "default_planning_settings_field_gen_buildrs")]
    pub default_gen_buildrs: bool,

    /// Any crate-specific configuration. See CrateSettings for details.
    #[serde(default)]
    pub crates: HashMap<String, CrateSettingsPerVersion>,

    /// The default crates registry.
    ///
    /// The patterns `{crate}` and `{version}` will be used to fill
    /// in the package's name (eg: rand) and version (eg: 0.7.1).
    /// See https://doc.rust-lang.org/cargo/reference/registries.html#index-format
    #[serde(default = "default_planning_settings_field_registry")]
    pub registry: String,

    /// The index url to use for Binary dependencies
    #[serde(default = "default_planning_settings_field_index_url")]
    pub index_url: String,
}

fn default_planning_settings_field_gen_workspace_prefix() -> String {
    "crate_graph__".to_owned()
}

fn default_planning_settings_field_genmode() -> GenMode {
    GenMode::Unspecified
}

fn default_planning_settings_field_gen_buildrs() -> bool {
    true
}

fn default_planning_settings_field_registry() -> String {
    format!(
        "{}/{}",
        DEFAULT_CRATE_REGISTRY_URL, "api/v1/crates/{crate}/{version}/download"
    )
}

fn default_planning_settings_field_index_url() -> String {
    DEFAULT_CRATE_INDEX_URL.to_owned()
}

pub type CrateSettingsPerVersion = HashMap<VersionReq, CrateSettings>;

/// Override settings for individual crates (as part of `RazeSettings`).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct CrateSettings {
    /// Dependencies to be added to a crate.
    ///
    /// Importantly, the format of dependency references depends on the genmode.
    /// Remote: @{gen_workspace_prefix}__{dep_name}__{dep_version_sanitized}/:{dep_name}
    /// Vendored: //{workspace_path}/vendor/{dep_name}-{dep_version}:{dep_name}
    ///
    /// In addition, the added deps must be accessible from a remote workspace under Remote GenMode.
    /// Usually, this means they _also_ need to be remote, but a "local" build path prefixed with
    /// "@", in the form "@//something_local" may work.
    #[serde(default)]
    pub additional_deps: Vec<String>,

    /// Dependencies to be removed from a crate, in the form "{dep-name}-{dep-version}"
    ///
    /// This is applied during Cargo analysis, so it uses Cargo-style labeling
    #[serde(default)]
    pub skipped_deps: Vec<String>,

    /// Library targets that should be aliased in the root BUILD file.
    ///
    /// This is useful to facilitate using binary utility crates, such as bindgen, as part of genrules.
    #[serde(default)]
    pub extra_aliased_targets: Vec<String>,

    /// Flags to be added to the crate compilation process, in the form "--flag".
    #[serde(default)]
    pub additional_flags: Vec<String>,

    /// Environment variables to be added to the crate compilation process.
    #[serde(default)]
    pub additional_env: BTreeMap<String, String>,

    /// Whether or not to generate the build script that goes with this crate.
    ///
    /// Many build scripts will not function, as they will still be built hermetically. However, build
    /// scripts that merely generate files into OUT_DIR may be fully functional.
    #[serde(default = "default_crate_settings_field_gen_buildrs")]
    pub gen_buildrs: Option<bool>,

    // N.B. Build scripts are always provided all crate files for their `data` attr.
    /// The verbatim `data` clause to be included for the generated build targets.
    #[serde(default = "default_crate_settings_field_data_attr")]
    pub data_attr: Option<String>,

    /// A list of targets for the `data` attribute of a Rust target
    #[serde(default)]
    pub data_dependencies: Vec<String>,

    /// The verbatim `compile_data` clause to be included for the generated build targets.
    #[serde(default)]
    pub compile_data_attr: Option<String>,

    /// The `data` attribute for buildrs targets
    #[serde(default)]
    pub build_data_dependencies: Vec<String>,

    /// Additional environment variables to add when running the build script.
    #[serde(default)]
    pub buildrs_additional_environment_variables: BTreeMap<String, String>,

    /// Additional dependencies for buildrs targets. See `additional_deps`
    #[serde(default)]
    pub buildrs_additional_deps: Vec<String>,

    /// The arguments given to the patch tool.
    ///
    /// Defaults to `-p0`, however `-p1` will usually be needed for patches generated by git.
    ///
    /// If multiple `-p` arguments are specified, the last one will take effect.
    /// If arguments other than `-p` are specified, Bazel will fall back to use patch command line
    /// tool instead of the Bazel-native patch implementation.
    ///
    /// When falling back to `patch` command line tool and `patch_tool` attribute is not specified,
    /// `patch` will be used.
    #[serde(default)]
    pub patch_args: Vec<String>,

    /// Sequence of Bash commands to be applied on Linux/Macos after patches are applied.
    #[serde(default)]
    pub patch_cmds: Vec<String>,

    /// Sequence of Powershell commands to be applied on Windows after patches are applied.
    ///
    /// If this attribute is not set, patch_cmds will be executed on Windows, which requires Bash
    /// binary to exist.
    #[serde(default)]
    pub patch_cmds_win: Vec<String>,

    /// The `patch(1)` utility to use.
    ///
    /// If this is specified, Bazel will use the specified patch tool instead of the Bazel-native patch
    /// implementation.
    #[serde(default)]
    pub patch_tool: Option<String>,

    /// A list of files that are to be applied as patches after extracting the archive.
    ///
    /// By default, it uses the Bazel-native patch implementation which doesn't support fuzz match and
    /// binary patch, but Bazel will fall back to use patch command line tool if `patch_tool`
    /// attribute is specified or there are arguments other than `-p` in `patch_args` attribute.
    #[serde(default)]
    pub patches: Vec<String>,

    /// Path to a file to be included as part of the generated BUILD file.
    ///
    /// For example, some crates include non-Rust code typically built through a build.rs script. They
    /// can be made compatible by manually writing appropriate Bazel targets, and including them into
    /// the crate through a combination of additional_build_file and additional_deps.
    ///
    /// Note: This field should be a path to a file relative to the Cargo workspace root. For more
    /// context, see https://doc.rust-lang.org/cargo/reference/workspaces.html#root-package
    #[serde(default)]
    pub additional_build_file: Option<PathBuf>,
}

impl Default for CrateSettings {
    fn default() -> Self {
        Self {
            additional_deps: Vec::new(),
            skipped_deps: Vec::new(),
            extra_aliased_targets: Vec::new(),
            additional_flags: Vec::new(),
            additional_env: BTreeMap::new(),
            gen_buildrs: default_crate_settings_field_gen_buildrs(),
            data_attr: default_crate_settings_field_data_attr(),
            data_dependencies: Vec::new(),
            compile_data_attr: None,
            build_data_dependencies: Vec::new(),
            buildrs_additional_deps: Vec::new(),
            buildrs_additional_environment_variables: BTreeMap::new(),
            patch_args: Vec::new(),
            patch_cmds: Vec::new(),
            patch_cmds_win: Vec::new(),
            patch_tool: None,
            patches: Vec::new(),
            additional_build_file: None,
        }
    }
}

fn default_crate_settings_field_gen_buildrs() -> Option<bool> {
    None
}

fn default_crate_settings_field_data_attr() -> Option<String> {
    None
}

/// Describes how dependencies should be managed in tree.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub enum GenMode {
    /// This mode assumes that files are vendored (into vendor/), and generates BUILD files
    /// accordingly
    Vendored,
    /// This mode assumes that files are not locally vendored, and generates a workspace-level
    /// function that can bring them in.
    Remote,
    /// A representation of a GenMode that has not yet been specified
    Unspecified,
}
