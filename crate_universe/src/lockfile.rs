//! Utility module for interacting with the cargo-bazel lockfile.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use anyhow::{Context as AnyhowContext, Result};
use hex::ToHex;
use serde::{Deserialize, Serialize};
use sha2::{Digest as Sha2Digest, Sha256};

use crate::context::Context;
use crate::splicing::{SplicingManifest, SplicingMetadata};
use crate::utils::target_triple::TargetTriple;

/// What produced a lockfile: the inputs to resolution which are neither in the
/// Cargo workspace nor in the splicing manifest. Recorded in the lockfile so a
/// difference between two of them can be explained, and hashed into the digest
/// so a change in any of them requires a repin.
///
/// The versions of `cargo` and `rustc` are deliberately absent. As with a
/// `Cargo.lock`, a toolchain upgrade does not change the resolution, so it
/// neither invalidates the lockfile nor requires the toolchain to be present
/// when the lockfile is checked.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Provenance {
    /// The version of `cargo-bazel`.
    pub(crate) cargo_bazel_version: String,

    /// The platforms resolved for.
    pub(crate) supported_platform_triples: BTreeSet<TargetTriple>,
}

impl Provenance {
    /// The provenance of a resolution performed now, with the given inputs.
    pub(crate) fn current(supported_platform_triples: &BTreeSet<TargetTriple>) -> Self {
        Self {
            cargo_bazel_version: env!("CARGO_PKG_VERSION").to_owned(),
            supported_platform_triples: supported_platform_triples.clone(),
        }
    }
}

pub(crate) fn lock_context(
    mut context: Context,
    supported_platform_triples: &BTreeSet<TargetTriple>,
    splicing_manifest: &SplicingManifest,
) -> Result<Context> {
    // Ensure there is no existing checksum or provenance which could impact the lockfile results
    context.checksum = None;
    context.provenance = None;

    let provenance = Provenance::current(supported_platform_triples);
    let checksum = Digest::new(&context, &provenance, splicing_manifest)
        .context("Failed to generate context digest")?;

    Ok(Context {
        checksum: Some(checksum),
        provenance: Some(provenance),
        ..context
    })
}

/// Write a [crate::context::Context] to disk
pub(crate) fn write_lockfile(lockfile: Context, path: &Path, dry_run: bool) -> Result<()> {
    let mut value = serde_json::to_value(&lockfile)?;
    compact_lockfile_value(&mut value);
    let content = format_lockfile(&value);

    if dry_run {
        println!("{content:#?}");
    } else {
        // Ensure the parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, content + "\n")
            .context(format!("Failed to write file to disk: {}", path.display()))?;
    }

    Ok(())
}

/// Width up to which an array or object of scalars is written on one line.
const INLINE_WIDTH: usize = 100;

/// Formats a lockfile one entry per line, except that arrays and objects whose
/// members are all scalars are written on one line when short. Diffs stay
/// per crate and per field while the file is well under half the size of
/// `serde_json`'s pretty output, most of which is whitespace around one-word
/// entries like a dependency's `id` and `target`.
pub(crate) fn format_lockfile(value: &serde_json::Value) -> String {
    let mut out = String::new();
    write_json(&mut out, value, 0);
    out
}

fn is_scalar(value: &serde_json::Value) -> bool {
    !matches!(
        value,
        serde_json::Value::Array(_) | serde_json::Value::Object(_)
    )
}

/// The one-line form of `value` if it is a scalar or a short container of scalars.
fn inline_json(value: &serde_json::Value) -> Option<String> {
    let text = match value {
        serde_json::Value::Array(items) if items.iter().all(is_scalar) => {
            let items: Vec<String> = items.iter().map(|item| item.to_string()).collect();
            format!("[{}]", items.join(", "))
        }
        serde_json::Value::Object(map) if map.values().all(is_scalar) => {
            let entries: Vec<String> = map
                .iter()
                .map(|(key, value)| format!("{}: {}", serde_json::Value::from(key.as_str()), value))
                .collect();
            format!("{{{}}}", entries.join(", "))
        }
        value if is_scalar(value) => value.to_string(),
        _ => return None,
    };
    (text.len() <= INLINE_WIDTH || is_scalar(value)).then_some(text)
}

fn write_json(out: &mut String, value: &serde_json::Value, depth: usize) {
    if let Some(text) = inline_json(value) {
        out.push_str(&text);
        return;
    }
    let indent = |out: &mut String, depth: usize| out.push_str(&"  ".repeat(depth));
    match value {
        serde_json::Value::Array(items) => {
            out.push_str("[\n");
            for (i, item) in items.iter().enumerate() {
                indent(out, depth + 1);
                write_json(out, item, depth + 1);
                out.push_str(if i + 1 < items.len() { ",\n" } else { "\n" });
            }
            indent(out, depth);
            out.push(']');
        }
        serde_json::Value::Object(map) => {
            out.push_str("{\n");
            for (i, (key, value)) in map.iter().enumerate() {
                indent(out, depth + 1);
                out.push_str(&serde_json::Value::from(key.as_str()).to_string());
                out.push_str(": ");
                write_json(out, value, depth + 1);
                out.push_str(if i + 1 < map.len() { ",\n" } else { "\n" });
            }
            indent(out, depth);
            out.push('}');
        }
        scalar => out.push_str(&scalar.to_string()),
    }
}

/// Recursively rewrite `{"common": X, "selects": {}}` patterns in a lockfile
/// JSON value to just `X`.
///
/// [`crate::select::Select`] always serializes to the verbose two-field shape
/// because the Tera-based rendering templates (see
/// `src/rendering/templates/`) index `deps_set.common` / `deps_set.selects`
/// directly on a `serde_json::Value` and would break if handed a bare array.
/// The on-disk lockfile has no such consumer — its readers all go through
/// `Select`'s own `Deserialize` impl, which accepts both shapes — so we
/// collapse the empty-`selects` case here for a substantial size win. The
/// verbose shape is preserved when `selects` is non-empty because that shape
/// is meaningful (multiple platform-specific values).
pub(crate) fn compact_lockfile_value(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            // Only collapse when the object is exactly `{"common": _, "selects": {}}`.
            // Extra keys (or a missing key) mean this isn't a `Select` and we
            // must leave it alone.
            let is_empty_select = map.len() == 2
                && map.contains_key("common")
                && map
                    .get("selects")
                    .and_then(|s| s.as_object())
                    .is_some_and(|s| s.is_empty());
            if is_empty_select {
                let mut common = map.remove("common").unwrap();
                compact_lockfile_value(&mut common);
                *value = common;
            } else {
                for v in map.values_mut() {
                    compact_lockfile_value(v);
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                compact_lockfile_value(item);
            }
        }
        _ => {}
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Clone)]
pub(crate) struct Digest(String);

impl Digest {
    /// The digest of a resolution: its context (without the checksum and provenance
    /// it will be stored with), what produced it, and the splicing inputs.
    pub(crate) fn new(
        context: &Context,
        provenance: &Provenance,
        splicing_manifest: &SplicingManifest,
    ) -> Result<Self> {
        let splicing_metadata = SplicingMetadata::try_from((*splicing_manifest).clone())?;
        let context = Context {
            checksum: None,
            provenance: None,
            ..context.clone()
        };
        Ok(Self::compute(&context, provenance, &splicing_metadata))
    }

    /// A helper for generating a hash and logging it's contents.
    fn compute_single_hash(data: &str, id: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        hasher.update(b"\0");
        let hash = hasher.finalize().encode_hex::<String>();
        tracing::debug!("{} digest: {}", id, hash);
        hash
    }

    fn compute(
        context: &Context,
        provenance: &Provenance,
        splicing_metadata: &SplicingMetadata,
    ) -> Self {
        // Since this method is private, it should be expected that context is
        // always None. This then allows us to have this method not return a
        // Result.
        debug_assert!(context.checksum.is_none());
        debug_assert!(context.provenance.is_none());

        let mut hasher = Sha256::new();

        // The lockfile context (typically `cargo-bazel-lock.json`).
        hasher.update(Digest::compute_single_hash(
            &serde_json::to_string(context).unwrap(),
            "lockfile context",
        ));
        hasher.update(b"\0");

        // The toolchain and platforms the context was produced with.
        hasher.update(Digest::compute_single_hash(
            &serde_json::to_string(provenance).unwrap(),
            "provenance",
        ));
        hasher.update(b"\0");

        // Data collected about Cargo manifests and configs that feed into dependency generation. This file
        // is also generated by Bazel behind the scenes based on user inputs.
        hasher.update(Digest::compute_single_hash(
            &serde_json::to_string(splicing_metadata).unwrap(),
            "splicing manifest",
        ));
        hasher.update(b"\0");

        let hash = hasher.finalize().encode_hex::<String>();
        tracing::debug!("Digest hash: {}", hash);

        Self(hash)
    }
}

impl PartialEq<str> for Digest {
    fn eq(&self, other: &str) -> bool {
        self.0 == other
    }
}

impl PartialEq<String> for Digest {
    fn eq(&self, other: &String) -> bool {
        &self.0 == other
    }
}

#[cfg(test)]
mod test {
    use std::collections::BTreeMap;

    use crate::splicing::cargo_config::{AdditionalRegistry, CargoConfig, Registry};
    use crate::utils::target_triple::TargetTriple;

    use super::*;

    fn provenance() -> Provenance {
        Provenance {
            cargo_bazel_version: "0.1.0".to_owned(),
            supported_platform_triples: BTreeSet::from([
                TargetTriple::from_bazel("aarch64-apple-darwin".to_owned()),
                TargetTriple::from_bazel("x86_64-unknown-linux-gnu".to_owned()),
            ]),
        }
    }

    #[test]
    fn simple_digest() {
        let digest = Digest::compute(
            &Context::default(),
            &provenance(),
            &SplicingMetadata::default(),
        );

        assert_eq!(
            Digest("bff9b6a4d9774e4805af7a3d4886280efab5621b8c35efd06bec881df06d6461".to_owned()),
            digest,
        );
    }

    /// Every field of the provenance is an input to resolution.
    #[test]
    fn digest_changes_with_provenance() {
        let base = Digest::compute(
            &Context::default(),
            &provenance(),
            &SplicingMetadata::default(),
        );
        for changed in [
            Provenance {
                cargo_bazel_version: "0.2.0".to_owned(),
                ..provenance()
            },
            Provenance {
                supported_platform_triples: BTreeSet::from([TargetTriple::from_bazel(
                    "aarch64-apple-darwin".to_owned(),
                )]),
                ..provenance()
            },
        ] {
            assert_ne!(
                base,
                Digest::compute(&Context::default(), &changed, &SplicingMetadata::default()),
                "{changed:?}"
            );
        }
    }

    #[test]
    fn digest_with_splicing_metadata() {
        let splicing_metadata = SplicingMetadata {
            direct_packages: BTreeMap::from([(
                "rustonomicon".to_owned(),
                cargo_toml::DependencyDetail {
                    version: Some("1.0.0".to_owned()),
                    ..cargo_toml::DependencyDetail::default()
                },
            )]),
            manifests: BTreeMap::new(),
            cargo_config: None,
            resolver_version: cargo_toml::Resolver::V2,
            experimental_cargo_free: false,
        };

        let digest = Digest::compute(&Context::default(), &provenance(), &splicing_metadata);

        assert_eq!(
            Digest("c418d1b836b1c2fa5430d916a2cbf77188c1735adb83840ca2980ecd49949b69".to_owned()),
            digest,
        );
    }

    #[test]
    fn digest_with_cargo_config() {
        let cargo_config = CargoConfig {
            registries: BTreeMap::from([
                (
                    "art-crates-remote".to_owned(),
                    AdditionalRegistry {
                        index: "https://artprod.mycompany/artifactory/git/cargo-remote.git"
                            .to_owned(),
                        token: None,
                    },
                ),
                (
                    "crates-io".to_owned(),
                    AdditionalRegistry {
                        index: "https://github.com/rust-lang/crates.io-index".to_owned(),
                        token: None,
                    },
                ),
            ]),
            registry: Registry {
                default: "art-crates-remote".to_owned(),
                token: None,
            },
            source: BTreeMap::new(),
        };

        let splicing_metadata = SplicingMetadata {
            cargo_config: Some(cargo_config),
            resolver_version: cargo_toml::Resolver::V2,
            experimental_cargo_free: false,
            ..SplicingMetadata::default()
        };

        let digest = Digest::compute(&Context::default(), &provenance(), &splicing_metadata);

        assert_eq!(
            Digest("fa82dd5c4cffcfece4da6d269e4818698af4166e925839dba6a36e90779c8bc5".to_owned()),
            digest,
        );
    }

    /// The digest covers the context's resolution, not its checksum or provenance
    /// fields, so a lockfile read back from disk hashes to its own checksum.
    #[test]
    fn digest_ignores_stored_checksum_and_provenance() {
        let context = Context::default();
        let expected = Digest::new(&context, &provenance(), &SplicingManifest::default()).unwrap();

        let stored = Context {
            checksum: Some(expected.clone()),
            provenance: Some(provenance()),
            ..context
        };
        assert_eq!(
            expected,
            Digest::new(&stored, &provenance(), &SplicingManifest::default()).unwrap()
        );
    }

    #[test]
    fn lockfile_format_is_dense_and_round_trips() {
        let value = serde_json::json!({
            "crates": {
                "serde 1.0.0": {
                    "common_attrs": {
                        "crate_features": ["default", "std"],
                        "deps": [{"id": "serde_core 1.0.0", "target": "serde_core"}],
                    },
                    "name": "serde",
                    "targets": [{"Library": {"crate_name": "serde", "crate_root": "src/lib.rs"}}],
                }
            },
            "direct_deps": [],
            "long": (0..40).map(|i| format!("entry-number-{i}")).collect::<Vec<_>>(),
        });

        let text = format_lockfile(&value);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&text).unwrap(),
            value
        );
        assert!(text.contains(r#""crate_features": ["default", "std"]"#));
        assert!(text.contains(r#"{"id": "serde_core 1.0.0", "target": "serde_core"}"#));
        assert!(text.contains(r#""direct_deps": []"#));
        // Long arrays and nested containers still go one entry per line.
        assert!(text.contains("\"entry-number-0\",\n"));
        assert!(text.contains("\"targets\": [\n"));
        assert!(text.len() < serde_json::to_string_pretty(&value).unwrap().len());
    }
}
