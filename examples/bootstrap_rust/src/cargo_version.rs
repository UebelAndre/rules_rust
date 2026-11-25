//! Runs the Cargo built from source, which `CARGO` names, for its version.

use std::process::Command;

#[test]
fn cargo_reports_the_release() {
    let cargo = std::env::var("CARGO").expect("CARGO names the cargo_toolchain's binary");
    let output = Command::new(&cargo).arg("--version").output().expect("cargo runs");
    let version = String::from_utf8(output.stdout).expect("cargo prints UTF-8");
    assert!(output.status.success(), "{cargo} failed: {}", String::from_utf8_lossy(&output.stderr));
    assert!(version.starts_with("cargo 1.99"), "unexpected version: {version}");
}
