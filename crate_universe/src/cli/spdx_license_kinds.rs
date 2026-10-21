//! The `spdx-license-kinds` subcommand: records the `license_kind` targets
//! rules_license declares for SPDX identifiers. See [crate::rendering].

use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::Parser;

/// Command line options for the `spdx-license-kinds` subcommand
#[derive(Parser, Debug)]
#[clap(
    about = "Record the SPDX `license_kind` targets rules_license declares",
    version
)]
pub struct SpdxLicenseKindsOptions {
    /// The `BUILD` file of rules_license's `licenses/spdx` package.
    #[clap(long)]
    pub build_file: PathBuf,

    /// Where to write the sorted JSON list of kind names.
    #[clap(long)]
    pub output: PathBuf,
}

/// Writes the names of the `license_kind` targets in `build_file` as a JSON list.
pub fn spdx_license_kinds(opt: SpdxLicenseKindsOptions) -> Result<()> {
    let text = fs::read_to_string(&opt.build_file)
        .with_context(|| format!("Failed to read {}", opt.build_file.display()))?;
    let kinds = license_kind_names(&text);
    fs::write(&opt.output, serde_json::to_string_pretty(&kinds)? + "\n")
        .with_context(|| format!("Failed to write {}", opt.output.display()))?;
    Ok(())
}

/// The `name` of every `license_kind(...)` call in a BUILD file.
fn license_kind_names(text: &str) -> BTreeSet<String> {
    let mut kinds = BTreeSet::new();
    let mut in_kind = false;
    for line in text.lines() {
        if line.starts_with("license_kind(") {
            in_kind = true;
        }
        if !in_kind {
            continue;
        }
        if let Some(rest) = line.trim().strip_prefix("name = \"") {
            if let Some(end) = rest.find('"') {
                kinds.insert(rest[..end].to_owned());
                in_kind = false;
            }
        }
    }
    kinds
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn only_license_kind_names_are_recorded() {
        let text = r#"
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "standard_package",
    srcs = glob(["**"]),
)

license_kind(
    name = "0BSD",
    conditions = [],
    url = "https://spdx.org/licenses/0BSD.html",
)

license_kind(
    name = "Apache-2.0",
    conditions = ["notice"],
)
"#;
        assert_eq!(
            license_kind_names(text),
            BTreeSet::from(["0BSD".to_owned(), "Apache-2.0".to_owned()])
        );
    }
}
