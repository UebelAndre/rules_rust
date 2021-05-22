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

use std::{collections::BTreeSet, path::PathBuf};

use crate::settings::CrateSettings;
use semver::Version;
use serde::{Deserialize, Serialize};

/// A struct containing information about a crate's dependency that's buildable in Bazel
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct BuildableDependency {
    // Note: Buildifier-compliant BUILD file generation depends on correct sorting of collections
    // of this struct by `buildable_target`. Do not add fields preceding this field.
    pub buildable_target: String,

    ///
    pub name: String,

    ///
    pub version: Version,

    ///
    pub is_proc_macro: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct DependencyAlias {
    ///
    pub target: String,

    ///
    pub alias: String,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct BuildableTarget {
    ///
    pub kind: String,

    ///
    pub name: String,

    /// The path in Bazel's format (i.e. with forward slashes) to the target's entry point.
    pub path: String,

    ///
    pub edition: String,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Metadep {
    ///
    pub name: String,

    ///
    pub min_version: Version,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct LicenseData {
    /// The name of the license
    pub name: String,

    /// The rating of the licesce as described by 
    /// [Bazel's internal rating](https://github.com/bazelbuild/bazel/blob/a1f2a386b8bc16a10601c559ef36ae86d658f8c3/src/main/java/com/google/devtools/build/lib/packages/License.java#L52-L68)
    pub rating: String,
}

impl Default for LicenseData {
    fn default() -> Self {
        LicenseData {
            name: "no license".into(),
            rating: "restricted".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct GitRepo {
    /// The url of the git repository
    pub remote: String,

    /// A full git commit hash
    pub commit: String,

    /// Directory containing the crate's Cargo.toml file, relative to the git repo root.
    /// Will be None iff the crate lives at the root of the git repo.
    pub path_to_crate_root: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SourceDetails {
    pub git_data: Option<GitRepo>,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct CrateDependencyContext {
    ///
    pub dependencies: Vec<BuildableDependency>,

    ///
    pub proc_macro_dependencies: Vec<BuildableDependency>,

    /// data_dependencies can only be set when using cargo-raze as a library at the moment.
    pub data_dependencies: Vec<BuildableDependency>,

    ///
    pub build_dependencies: Vec<BuildableDependency>,

    ///
    pub build_proc_macro_dependencies: Vec<BuildableDependency>,

    /// build_data_dependencies can only be set when using cargo-raze as a library at the moment.
    pub build_data_dependencies: Vec<BuildableDependency>,

    ///
    pub dev_dependencies: Vec<BuildableDependency>,

    ///
    pub aliased_dependencies: BTreeSet<DependencyAlias>,
}

impl CrateDependencyContext {
    pub fn contains(&self, name: &str, version: Version) -> bool {
        let condition = |dep: &BuildableDependency| dep.name.eq(&name) && dep.version.eq(&version);
        self.dependencies.iter().any(condition)
            || self.proc_macro_dependencies.iter().any(condition)
            || self.build_dependencies.iter().any(condition)
            || self.build_proc_macro_dependencies.iter().any(condition)
            || self.dev_dependencies.iter().any(condition)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct CrateTargetedDepContext {
    ///
    pub target: String,

    ///
    pub deps: CrateDependencyContext,

    ///
    pub platform_targets: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct CrateContext {
    /// The crate's cargo package name
    pub pkg_name: String,

    /// The crate's version
    pub pkg_version: Version,

    /// The crate's edition
    pub edition: String,

    /// Additional settings associated with the crate's Cargo metadata
    pub crate_settings: CrateSettings,

    /// The dependencies of the current crate
    pub default_deps: CrateDependencyContext,

    /// Conditional dependencies of the current crate based on the target platform triple
    pub targeted_deps: Vec<CrateTargetedDepContext>,

    /// The license data of the crate
    pub license: LicenseData,

    /// A list of features to enable
    pub features: Vec<String>,

    /// A list of workspace members that depend on on the crate described 
    /// by this context as a normal dependency
    pub workspace_member_dependents: Vec<PathBuf>,

    /// A list of workspace members that depend on on the crate described
    /// by this context as a dev dependency
    pub workspace_member_dev_dependents: Vec<PathBuf>,

    /// A list of workspace members that depend on on the crate described 
    /// by this context as a build dependency
    pub workspace_member_build_dependents: Vec<PathBuf>,

    ///
    pub targets: Vec<BuildableTarget>,

    ///
    pub build_script_target: Option<BuildableTarget>,

    ///
    pub links: Option<String>,

    ///
    pub source_details: SourceDetails,

    /// The full sha256 digest of the crate expected at #registry_url
    pub sha256: Option<String>,

    /// The url where the crate can be downloaded
    pub registry_url: String,

    /// Whether or not the described crate is a workspace member
    pub is_workspace_member_dependency: bool,

    /// The intended Bazel label of the current crate
    pub label: String,

    /// The name of the main lib target for this crate (if present).
    /// Currently only one such lib can exist per crate.
    pub lib_target_name: Option<String>,

    /// This field tracks whether or not the lib target of `lib_target_name`
    /// is a proc_macro library or not.
    pub is_proc_macro: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize)]
pub struct WorkspaceContext {
    /// The bazel path prefix to the vendor directory
    pub workspace_path: String,

    /// The generated new_http_library Bazel workspace prefix.
    ///
    /// This has no effect unless the GenMode setting is Remote.
    pub gen_workspace_prefix: String,

    /// A list of relative paths from a Cargo workspace root to a Cargo package.
    pub workspace_members: Vec<PathBuf>,
}
