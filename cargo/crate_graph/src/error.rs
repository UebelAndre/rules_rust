// Copyright 2020 Google Inc.
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

use std::fmt;

pub(crate) const PLEASE_FILE_A_BUG: &str =
    "Please file an issue at github.com/bazelbuild/rules_rust with details.";

#[derive(Debug)]
pub enum GraphError {
    // Generic(String),
    Internal(String),
    Config {
        field_path_opt: Option<String>,
        message: String,
    },
    Planning {
        dependency_name_opt: Option<String>,
        message: String,
    },
}

impl std::error::Error for GraphError {}

impl fmt::Display for GraphError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match &self {
            Self::Internal(s) => write!(
                f,
                "crate_graph failed unexpectedly with cause: \"{}\". {}",
                s, PLEASE_FILE_A_BUG
            ),
            Self::Config {
                field_path_opt: Some(field_path_opt),
                message,
            } => write!(
                f,
                "crate_graph config problem in field \"{}\" with cause: \"{}\"",
                field_path_opt, message
            ),
            Self::Config {
                field_path_opt: None,
                message,
            } => write!(f, "crate_graph config problem with cause: \"{}\"", message),
            Self::Planning {
                dependency_name_opt: Some(dependency_name_opt),
                message,
            } => write!(
                f,
                "Planning failed to plan crate \"{}\" with cause: \"{}\"",
                dependency_name_opt, message
            ),
            Self::Planning {
                dependency_name_opt: None,
                message,
            } => write!(f, "Planning failed to render with cause: \"{}\"", message),
        }
    }
}
