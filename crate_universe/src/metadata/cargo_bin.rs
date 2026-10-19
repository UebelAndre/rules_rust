//! Tools for invoking Cargo subcommands.

use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};

use anyhow::{anyhow, bail, Context, Result};
use cargo_metadata::MetadataCommand;
use semver::Version;

use crate::metadata::rustc_shim::{self, RustcShim};

/// Cargo encapsulates a path to a `cargo` binary.
/// Any invocations of `cargo` (either as a `std::process::Command` or via `cargo_metadata`) should
/// go via this wrapper to ensure that any environment variables needed are set appropriately.
///
/// Cargo runs without a `rustc`: unless one is given, `RUSTC` points at this
/// very executable, which answers Cargo's questions about the toolchain from
/// Cargo's own version and the recorded `cfg` table. See
/// [rustc_shim](crate::metadata::rustc_shim).
#[derive(Debug, Clone)]
pub(crate) struct Cargo {
    path: PathBuf,
    rustc_path: Option<PathBuf>,
    full_version: Arc<Mutex<Option<String>>>,
    shim: Arc<Mutex<Option<RustcShim>>>,
    cargo_home: Option<PathBuf>,
}

impl Cargo {
    /// A cargo at `path`. `rustc` is the compiler to pair it with; `None`
    /// stands in for one, which is all resolving needs.
    pub(crate) fn new(path: PathBuf, rustc: Option<PathBuf>) -> Cargo {
        Cargo {
            path,
            rustc_path: rustc,
            full_version: Arc::new(Mutex::new(None)),
            shim: Arc::new(Mutex::new(None)),
            cargo_home: None,
        }
    }

    /// The `rustc` binary paired with this cargo, when a real one was given.
    pub(crate) fn rustc_path(&self) -> Option<&Path> {
        self.rustc_path.as_deref()
    }

    /// What this cargo's stand-in for `rustc` answers from.
    fn shim(&self) -> Result<RustcShim> {
        let mut shim = self.shim.lock().unwrap();
        if shim.is_none() {
            *shim = Some(RustcShim::for_cargo(&self.path)?);
        }
        Ok(shim.clone().unwrap())
    }

    /// The `CARGO_HOME` this cargo works in: the one set here, else the
    /// environment's, else Cargo's default.
    pub(crate) fn cargo_home(&self) -> Result<PathBuf> {
        if let Some(cargo_home) = &self.cargo_home {
            return Ok(cargo_home.clone());
        }
        if let Some(cargo_home) = std::env::var_os("CARGO_HOME") {
            return Ok(PathBuf::from(cargo_home));
        }
        let user_home = std::env::var_os("HOME")
            .or_else(|| std::env::var_os("USERPROFILE"))
            .ok_or_else(|| anyhow!("Neither `CARGO_HOME` nor `HOME` is set"))?;
        Ok(PathBuf::from(user_home).join(".cargo"))
    }

    /// Returns a new `Command` for running this cargo.
    pub(crate) fn command(&self) -> Result<Command> {
        let mut command = Command::new(&self.path);
        command.envs(self.env()?);
        if self.is_nightly()? {
            command.arg("-Zbindeps");
        }
        Ok(command)
    }

    /// Returns a new `MetadataCommand` using this cargo.
    /// `manifest_path`, `current_dir`, and `other_options` should not be called on the resturned MetadataCommand - instead pass them as the relevant args.
    pub(crate) fn metadata_command_with_options(
        &self,
        manifest_path: &Path,
        other_options: Vec<String>,
    ) -> Result<MetadataCommand> {
        let mut command = MetadataCommand::new();
        command.cargo_path(&self.path);
        for (k, v) in self.env()? {
            command.env(k, v);
        }

        command.manifest_path(manifest_path);
        // Cargo detects config files based on `pwd` when running so
        // to ensure user provided Cargo config files are used, it's
        // critical to set the working directory to the manifest dir.
        let manifest_dir = manifest_path
            .parent()
            .ok_or_else(|| anyhow::anyhow!("manifest_path {:?} must have parent", manifest_path))?;
        command.current_dir(manifest_dir);

        let mut other_options = other_options;
        if self.is_nightly()? {
            other_options.push("-Zbindeps".to_owned());
        }
        command.other_options(other_options);
        Ok(command)
    }

    /// Returns the output of running `cargo --version`, trimming any leading or trailing whitespace.
    fn full_version(&self) -> Result<String> {
        let mut full_version = self.full_version.lock().unwrap();
        if full_version.is_none() {
            let observed_version = bin_version(&self.path)?;
            *full_version = Some(observed_version);
        }
        Ok(full_version.clone().unwrap())
    }

    pub(crate) fn is_nightly(&self) -> Result<bool> {
        let full_version = self.full_version()?;
        let version_str = full_version.split(' ').nth(1);
        if let Some(version_str) = version_str {
            let version = Version::parse(version_str).context("Failed to parse cargo version")?;
            return Ok(version.pre.as_str() == "nightly");
        }
        bail!("Couldn't parse cargo version");
    }

    pub(crate) fn use_sparse_registries_for_crates_io(&self) -> Result<bool> {
        let full_version = self.full_version()?;
        let version_str = full_version.split(' ').nth(1);
        if let Some(version_str) = version_str {
            let version = Version::parse(version_str).context("Failed to parse cargo version")?;
            return Ok(version.major >= 1 && version.minor >= 68);
        }
        bail!("Couldn't parse cargo version");
    }

    /// Determine if Cargo is expected to be using the new package_id spec. For
    /// details see <https://github.com/rust-lang/cargo/pull/13311>
    #[cfg(test)]
    pub(crate) fn uses_new_package_id_format(&self) -> Result<bool> {
        let full_version = self.full_version()?;
        let version_str = full_version.split(' ').nth(1);
        if let Some(version_str) = version_str {
            let version = Version::parse(version_str).context("Failed to parse cargo version")?;
            return Ok(version.major >= 1 && version.minor >= 77);
        }
        bail!("Couldn't parse cargo version");
    }

    /// Determine if Cargo is on a version which uses new hashing behavior
    /// introduced in Rust 1.86.0. For details see <https://github.com/frewsxcv/rust-crates-index/issues/182>
    pub(crate) fn uses_stable_registry_hash(&self) -> Result<bool> {
        let full_version = self.full_version()?;
        let version_str = full_version.split(' ').nth(1);
        if let Some(version_str) = version_str {
            let version = Version::parse(version_str).context("Failed to parse cargo version")?;
            return Ok(version.major >= 1 && version.minor >= 85);
        }
        bail!("Couldn't parse cargo version");
    }

    fn env(&self) -> Result<BTreeMap<String, OsString>> {
        let mut map = BTreeMap::new();

        match &self.rustc_path {
            Some(rustc) => {
                map.insert("RUSTC".into(), rustc.as_os_str().to_owned());
            }
            None => {
                map.insert("RUSTC".into(), rustc_shim::executable()?.into_os_string());
                map.insert(rustc_shim::ENV.into(), self.shim()?.to_env().into());
                // Cargo caches what rustc answered in `target/.rustc_info.json`,
                // keyed by the rustc binary's path and mtime alone. The stand-in's
                // answers follow the Cargo it runs next to, not its own binary, so
                // a reused target directory must not serve a previous Cargo's.
                map.insert("CARGO_CACHE_RUSTC_INFO".into(), "0".into());
            }
        }

        if self.use_sparse_registries_for_crates_io()? {
            map.insert(
                "CARGO_REGISTRIES_CRATES_IO_PROTOCOL".into(),
                "sparse".into(),
            );
        }

        if let Some(cargo_home) = &self.cargo_home {
            map.insert("CARGO_HOME".into(), cargo_home.as_os_str().to_owned());
        }

        Ok(map)
    }
}

/// The output of `<binary> --version`, run in an environment scrubbed of
/// everything but what the binary needs to start.
fn bin_version(binary: &Path) -> Result<String> {
    let safe_vars = [
        OsStr::new("HOME"),
        OsStr::new("HOMEDRIVE"),
        OsStr::new("PATHEXT"),
        OsStr::new("NIX_LD"),
        OsStr::new("NIX_LD_LIBRARY_PATH"),
    ];
    let env = std::env::vars_os().filter(|(var, _)| safe_vars.contains(&var.as_os_str()));

    let output = Command::new(binary)
        .arg("--version")
        .env_clear()
        .envs(env)
        .output()
        .with_context(|| format!("Failed to run {} to get its version", binary.display()))?;

    if !output.status.success() {
        eprintln!("{}", String::from_utf8_lossy(&output.stdout));
        eprintln!("{}", String::from_utf8_lossy(&output.stderr));
        bail!("Failed to query cargo version")
    }

    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}
