//! wasm-bindgen test runner

use std::collections::BTreeMap;
use std::env;
use std::process::{exit, Command};

use runfiles::{rlocation, Runfiles};

#[cfg(target_os = "windows")]
const PATH_SEPARATOR: &str = ";";

#[cfg(not(target_os = "windows"))]
const PATH_SEPARATOR: &str = ":";

fn main() {
    let runfiles = Runfiles::create().expect("Failed to locate runfiles");

    let browser = rlocation!(
        runfiles,
        env::var("BROWSER").expect("Failed to find BROWSER env var.")
    );
    let test_bin = rlocation!(
        runfiles,
        env::var("TEST_WASM_BINARY").expect("Failed to find test binary")
    );

    // Determine the directory to inject into PATH
    let browser_path = browser
        .parent()
        .expect("Runfiles should always have parents")
        .to_string_lossy()
        .to_string();

    // Update any existing environment variables.
    let mut env = env::vars().collect::<BTreeMap<_, _>>();
    env.entry("PATH".to_owned())
        .and_modify(|v| *v = format!("{}{}{}", browser_path, PATH_SEPARATOR, v))
        .or_insert(browser_path);

    // Run the test
    let result = Command::new(test_bin)
        .envs(env)
        .args(env::args())
        .status()
        .expect("Failed to spawn test");

    if !result.success() {
        exit(
            result
                .code()
                .expect("Completed processes will always have exit codes."),
        )
    }
}
