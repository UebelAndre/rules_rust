//! A stand-in for `rustc` so that Cargo runs without one.
//!
//! Cargo asks `rustc` two things before it will resolve a workspace: its
//! version and host (`rustc -vV`), and the file names, sysroot and `cfg`
//! values of the host platform (one `--print` probe, run by
//! `RustcTargetData::new`). Plain `cargo metadata` makes no use of the
//! answers beyond parsing them, since it is not filtering by platform, and
//! the resolver only reads the version, as the `rust-version` cap of a
//! workspace which declares none. Neither needs a compiler.
//!
//! So `cargo-bazel` answers them itself. [Cargo](super::cargo_bin::Cargo)
//! sets `RUSTC` to its own executable and [ENV] to what the answers are
//! built from, and `main` hands such invocations to [run]. The version and
//! host come from the Cargo being run, and the `cfg` values from the table
//! recorded in [rustc_cfgs](super::rustc_cfgs), the same one `cfg(...)`
//! dependencies are evaluated against. The probe's arguments are answered
//! in the order Cargo asks, and an unknown `--print` is an error rather than
//! a guess, so a change to Cargo's probe fails loudly.

use std::io::Write;
use std::path::Path;
use std::process::Command;

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::metadata::rustc_cfgs::RustcCfgs;

/// The environment variable carrying a serialized [RustcShim] to the
/// invocation `cargo-bazel` is asked to answer as `rustc`.
pub(crate) const ENV: &str = "CARGO_BAZEL_RUSTC_SHIM";

/// The environment variable naming the executable to run as `rustc` in place
/// of the current one. Tests set it to a `cargo-bazel` binary, since a test
/// binary's `main` is not [run].
pub(crate) const EXECUTABLE_ENV: &str = "CARGO_BAZEL_RUSTC_SHIM_EXECUTABLE";

/// The executable Cargo is given as `rustc`: this process, or the one named
/// by [EXECUTABLE_ENV].
pub(crate) fn executable() -> Result<std::path::PathBuf> {
    match std::env::var_os(EXECUTABLE_ENV) {
        Some(exe) => std::fs::canonicalize(&exe).with_context(|| {
            format!(
                "`{EXECUTABLE_ENV}` names `{}`, which does not exist",
                Path::new(&exe).display()
            )
        }),
        None => std::env::current_exe()
            .context("Failed to locate the running cargo-bazel to stand in for rustc"),
    }
}

/// What the shim answers from: the identity of the Cargo it stands next to.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct RustcShim {
    /// The host triple, as `cargo -vV` reports it.
    pub(crate) host: String,

    /// The release, e.g. `1.98.0` or `1.99.0-nightly`.
    pub(crate) release: String,

    /// The commit hash of the toolchain, when `cargo -vV` reports one.
    pub(crate) commit_hash: Option<String>,

    /// The commit date of the toolchain, when `cargo -vV` reports one.
    pub(crate) commit_date: Option<String>,
}

impl RustcShim {
    /// Describes the toolchain of `cargo` from the output of `cargo -vV`.
    pub(crate) fn for_cargo(cargo: &Path) -> Result<Self> {
        let output = Command::new(cargo)
            .arg("-vV")
            .output()
            .with_context(|| format!("Failed to run `{} -vV`", cargo.display()))?;
        if !output.status.success() {
            bail!(
                "`{} -vV` failed: {}\n{}",
                cargo.display(),
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        Self::parse_verbose_version(&String::from_utf8(output.stdout)?)
    }

    /// Parses the `key: value` lines of `cargo -vV`.
    fn parse_verbose_version(text: &str) -> Result<Self> {
        let field = |name: &str| {
            text.lines()
                .find_map(|line| {
                    line.strip_prefix(name)
                        .and_then(|rest| rest.strip_prefix(": "))
                })
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
        };
        let host =
            field("host").ok_or_else(|| anyhow!("`cargo -vV` reported no `host`:\n{text}"))?;
        let release = field("release")
            .ok_or_else(|| anyhow!("`cargo -vV` reported no `release`:\n{text}"))?;
        Ok(Self {
            host,
            release,
            commit_hash: field("commit-hash").filter(|hash| hash != "unknown"),
            commit_date: field("commit-date").filter(|date| date != "unknown"),
        })
    }

    /// The value of [ENV] which makes `cargo-bazel` answer as this toolchain.
    pub(crate) fn to_env(&self) -> String {
        serde_json::to_string(self).expect("a shim serializes")
    }

    /// The output of `rustc -vV` for this toolchain.
    fn verbose_version(&self) -> String {
        let mut text = format!(
            "rustc {} ({} {})\nbinary: rustc\ncommit-hash: {}\ncommit-date: {}\nhost: {}\nrelease: {}\n",
            self.release,
            self.commit_hash.as_deref().unwrap_or("unknown"),
            self.commit_date.as_deref().unwrap_or("unknown"),
            self.commit_hash.as_deref().unwrap_or("unknown"),
            self.commit_date.as_deref().unwrap_or("unknown"),
            self.host,
            self.release,
        );
        if !text.ends_with('\n') {
            text.push('\n');
        }
        text
    }

    /// Answers one `rustc` invocation with the given arguments, writing to
    /// `out` what `rustc` would print.
    pub(crate) fn answer(
        &self,
        args: &[String],
        cfgs: &RustcCfgs,
        out: &mut dyn Write,
    ) -> Result<()> {
        let args = expand_argfiles(args)?;

        if args.iter().any(|arg| arg == "-vV" || arg == "--version") {
            out.write_all(self.verbose_version().as_bytes())?;
            return Ok(());
        }

        let probe = Probe::parse(&args)?;
        let triple = probe.target.as_deref().unwrap_or(&self.host);
        for request in &probe.prints {
            match request.as_str() {
                "file-names" => {
                    for crate_type in &probe.crate_types {
                        let (prefix, suffix) = file_name_affixes(crate_type, triple);
                        writeln!(out, "{prefix}{}{suffix}", probe.crate_name)?;
                    }
                }
                // Cargo derives `lib/rustlib/<triple>/lib` from this for the
                // compiler's use; nothing is read from it when resolving.
                "sysroot" => writeln!(out, "{}", sysroot(cfgs))?,
                "split-debuginfo" => writeln!(out, "off")?,
                "crate-name" => writeln!(out, "{}", probe.crate_name)?,
                "cfg" => {
                    let text = cfgs.cfg_text(triple).ok_or_else(|| {
                        anyhow!(
                            "No `rustc --print=cfg` is recorded for `{triple}`; resolving needs a \
                             rustc only for this, so `host_tools` can name a repository providing one"
                        )
                    })?;
                    writeln!(out, "{text}")?;
                }
                other => bail!(
                    "Cargo asked rustc for `--print={other}`, which cargo-bazel does not know how \
                     to answer without a rustc. Cargo's probe has changed; cargo-bazel needs an update."
                ),
            }
        }
        Ok(())
    }
}

/// The parts of a `rustc` probe that decide its answer.
#[derive(Debug, Default, PartialEq, Eq)]
struct Probe {
    /// The `--print` requests, in order.
    prints: Vec<String>,
    /// The `--crate-type` arguments, in order.
    crate_types: Vec<String>,
    /// `--crate-name`, or rustc's default for input from stdin.
    crate_name: String,
    /// `--target`, if any.
    target: Option<String>,
}

impl Probe {
    fn parse(args: &[String]) -> Result<Self> {
        let mut probe = Probe {
            crate_name: "rust_out".to_owned(),
            ..Default::default()
        };
        let mut args = args.iter();
        while let Some(arg) = args.next() {
            let mut value_of = |flag: &str| -> Result<Option<String>> {
                if let Some(value) = arg.strip_prefix(&format!("{flag}=")) {
                    return Ok(Some(value.to_owned()));
                }
                if arg == flag {
                    return args
                        .next()
                        .cloned()
                        .map(Some)
                        .ok_or_else(|| anyhow!("`{flag}` is missing its value"));
                }
                Ok(None)
            };
            if let Some(print) = value_of("--print")? {
                probe.prints.push(print);
            } else if let Some(crate_type) = value_of("--crate-type")? {
                probe
                    .crate_types
                    .extend(crate_type.split(',').map(str::to_owned));
            } else if let Some(name) = value_of("--crate-name")? {
                probe.crate_name = name;
            } else if let Some(target) = value_of("--target")? {
                probe.target = Some(target);
            }
            // Everything else (`-`, rustflags, `-Wwarnings`) does not change
            // the answer.
        }
        Ok(probe)
    }
}

/// Replaces `@file` arguments by the lines of the file, as rustc does and as
/// Cargo relies on when a command line grows too long.
fn expand_argfiles(args: &[String]) -> Result<Vec<String>> {
    let mut expanded = Vec::with_capacity(args.len());
    for arg in args {
        match arg.strip_prefix('@') {
            Some(path) if Path::new(path).is_file() => {
                let text = std::fs::read_to_string(path)
                    .with_context(|| format!("Failed to read the argfile `{path}`"))?;
                expanded.extend(text.lines().map(str::to_owned));
            }
            _ => expanded.push(arg.clone()),
        }
    }
    Ok(expanded)
}

/// The prefix and suffix rustc gives the output file of a crate type on a
/// platform, e.g. `lib` and `.rlib`.
fn file_name_affixes(crate_type: &str, triple: &str) -> (&'static str, &'static str) {
    let windows = triple.contains("-windows-");
    let msvc = triple.ends_with("-msvc");
    let apple = triple.contains("-apple-");
    let wasm = triple.starts_with("wasm");
    match crate_type {
        "bin" => (
            "",
            if windows {
                ".exe"
            } else if wasm {
                ".wasm"
            } else {
                ""
            },
        ),
        "lib" | "rlib" => ("lib", ".rlib"),
        "dylib" | "cdylib" | "proc-macro" => {
            if windows {
                ("", ".dll")
            } else if apple {
                ("lib", ".dylib")
            } else if wasm {
                ("", ".wasm")
            } else {
                ("lib", ".so")
            }
        }
        "staticlib" => {
            if msvc {
                ("", ".lib")
            } else {
                ("lib", ".a")
            }
        }
        // rustc would reject an unknown crate type; Cargo only asks about the
        // ones above.
        _ => ("lib", ".rlib"),
    }
}

/// A sysroot path for the probe. Cargo joins `lib/rustlib/<triple>/lib`
/// onto it and never reads the result while resolving, so any absolute path
/// does; the recorded table's location keeps it recognizable.
fn sysroot(_cfgs: &RustcCfgs) -> String {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf))
        .unwrap_or_default()
        .join("cargo-bazel-sysroot")
        .display()
        .to_string()
}

/// Answers the current process's arguments as `rustc` when [ENV] is set.
///
/// Returns `None` when this process was not started as the shim, so `main`
/// proceeds with its own command line.
pub fn run() -> Option<Result<()>> {
    let shim = std::env::var(ENV).ok()?;
    Some((|| {
        let shim: RustcShim = serde_json::from_str(&shim)
            .with_context(|| format!("`{ENV}` is not a shim description"))?;
        let args: Vec<String> = std::env::args().skip(1).collect();
        let mut out = Vec::new();
        shim.answer(&args, RustcCfgs::recorded(), &mut out)?;
        std::io::stdout().write_all(&out)?;
        Ok(())
    })())
}

#[cfg(test)]
mod test {
    use std::collections::BTreeMap;

    use super::*;

    fn shim() -> RustcShim {
        RustcShim {
            host: "x86_64-unknown-linux-gnu".to_owned(),
            release: "1.98.0".to_owned(),
            commit_hash: Some("797e8a9bcd5dd8bb0d8a6a9d1d8b2c7bd4c43b4a".to_owned()),
            commit_date: Some("2026-08-05".to_owned()),
        }
    }

    fn table() -> RustcCfgs {
        RustcCfgs {
            rustc: "rustc 1.98.0".to_owned(),
            cfgs: BTreeMap::from([
                (
                    "x86_64-unknown-linux-gnu".to_owned(),
                    vec!["target_arch=\"x86_64\"".to_owned(), "unix".to_owned()],
                ),
                (
                    "x86_64-pc-windows-msvc".to_owned(),
                    vec!["target_arch=\"x86_64\"".to_owned(), "windows".to_owned()],
                ),
            ]),
        }
    }

    fn answer(args: &[&str]) -> String {
        let mut out = Vec::new();
        shim()
            .answer(
                &args.iter().map(|arg| arg.to_string()).collect::<Vec<_>>(),
                &table(),
                &mut out,
            )
            .unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn parses_cargo_verbose_version() {
        let parsed = RustcShim::parse_verbose_version(
            "cargo 1.98.0 (797e8a9bc 2026-08-05)\nrelease: 1.98.0\ncommit-hash: 797e8a9bcd5dd8bb0d8a6a9d1d8b2c7bd4c43b4a\ncommit-date: 2026-08-05\nhost: x86_64-unknown-linux-gnu\nlibgit2: 1.9.1 (sys:0.20.2 vendored)\nos: Ubuntu 24.04 (noble) [64-bit]\n",
        )
        .unwrap();
        assert_eq!(parsed, shim());

        let unknown = RustcShim::parse_verbose_version(
            "cargo 1.99.0-nightly\nrelease: 1.99.0-nightly\ncommit-hash: unknown\ncommit-date: unknown\nhost: aarch64-apple-darwin\n",
        )
        .unwrap();
        assert_eq!(unknown.commit_hash, None);
        assert_eq!(unknown.release, "1.99.0-nightly");
    }

    #[test]
    fn verbose_version_has_what_cargo_reads() {
        let text = answer(&["-vV"]);
        assert!(
            text.lines().any(|l| l == "host: x86_64-unknown-linux-gnu"),
            "{text}"
        );
        assert!(text.lines().any(|l| l == "release: 1.98.0"), "{text}");
        assert!(text.starts_with("rustc 1.98.0 ("), "{text}");
    }

    #[test]
    fn answers_cargos_probe_in_order() {
        // The probe `RustcTargetData::new` runs for the host.
        let text = answer(&[
            "-",
            "--crate-name",
            "___",
            "--print=file-names",
            "--crate-type",
            "bin",
            "--crate-type",
            "rlib",
            "--crate-type",
            "dylib",
            "--crate-type",
            "cdylib",
            "--crate-type",
            "staticlib",
            "--crate-type",
            "proc-macro",
            "--print=sysroot",
            "--print=split-debuginfo",
            "--print=crate-name",
            "--print=cfg",
            "-Wwarnings",
        ]);
        let mut lines = text.lines();
        assert_eq!(lines.next(), Some("___"));
        assert_eq!(lines.next(), Some("lib___.rlib"));
        assert_eq!(lines.next(), Some("lib___.so"));
        assert_eq!(lines.next(), Some("lib___.so"));
        assert_eq!(lines.next(), Some("lib___.a"));
        assert_eq!(lines.next(), Some("lib___.so"));
        assert!(Path::new(lines.next().unwrap()).is_absolute());
        assert_eq!(lines.next(), Some("off"));
        assert_eq!(lines.next(), Some("___"));
        assert_eq!(lines.next(), Some("target_arch=\"x86_64\""));
        assert_eq!(lines.next(), Some("unix"));
        assert_eq!(lines.next(), None);
    }

    #[test]
    fn answers_for_a_target() {
        let text = answer(&[
            "-",
            "--crate-name",
            "___",
            "--print=file-names",
            "--target",
            "x86_64-pc-windows-msvc",
            "--crate-type",
            "bin",
            "--crate-type",
            "staticlib",
            "--print=cfg",
        ]);
        assert_eq!(text, "___.exe\n___.lib\ntarget_arch=\"x86_64\"\nwindows\n");
    }

    #[test]
    fn unknown_requests_fail() {
        let mut out = Vec::new();
        let args = ["--print=target-libdir".to_owned()];
        let err = shim().answer(&args, &table(), &mut out).unwrap_err();
        assert!(err.to_string().contains("target-libdir"), "{err}");

        let args = [
            "--print=cfg".to_owned(),
            "--target=mips-unknown-nowhere".to_owned(),
        ];
        let err = shim().answer(&args, &table(), &mut out).unwrap_err();
        assert!(err.to_string().contains("mips-unknown-nowhere"), "{err}");
    }

    #[test]
    fn env_round_trips() {
        let shim = shim();
        let parsed: RustcShim = serde_json::from_str(&shim.to_env()).unwrap();
        assert_eq!(parsed, shim);
    }
}
