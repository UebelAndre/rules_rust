//! This script collects code coverage data for Rust sources, after the tests
//! were executed
//!
//! By taking advantage of Bazel C++ code coverage collection, this script is
//! able to be executed by the existing coverage collection mechanics.
//!
//! Bazel uses the lcov tool for gathering coverage data. There is also
//! an experimental support for clang llvm coverage, which uses the .profraw
//! data files to compute the coverage report.
//!
//! This script assumes the following environment variables are set:
//! - COVERAGE_DIR            Directory containing metadata files needed for
//!                           coverage collection (e.g. gcda files, profraw).
//! - COVERAGE_OUTPUT_FILE    The coverage action output path.
//! - ROOT                    Location from where the code coverage collection
//!                           was invoked.
//! - RUNFILES_DIR            Location of the test's runfiles.
//! - VERBOSE_COVERAGE        Print debug info from the coverage scripts
//!
//! The script looks in $COVERAGE_DIR for the Rust metadata coverage files
//! (profraw) and uses lcov to get the coverage data. The coverage data
//! is placed in $COVERAGE_DIR as a `coverage.dat` file.

use std::env;
use std::fs;
use std::io;
use std::io::Read;
use std::path::PathBuf;
use std::process;

fn main() {
    let coverage_dir = PathBuf::from(env::var("COVERAGE_DIR").unwrap());
    let execroot = PathBuf::from(env::var("ROOT").unwrap());
    let mut runfiles_dir = PathBuf::from(env::var("RUNFILES_DIR").unwrap());

    if !runfiles_dir.is_absolute() {
        runfiles_dir = execroot.join(runfiles_dir);
    }

    let coverage_output_file = coverage_dir.join("coverage.dat");
    let profdata_file = coverage_dir.join("coverage.profdata");
    let llvm_profdata = runfiles_dir.join(env::var("RUST_LLVM_PROFDATA").unwrap());
    let llvm_cov = runfiles_dir.join(env::var("RUST_LLVM_COV").unwrap());
    let test_binary = runfiles_dir
        .join(env::var("TEST_WORKSPACE").unwrap())
        .join(env::var("TEST_BINARY").unwrap());

    let profraw_files: Vec<PathBuf> = fs::read_dir(coverage_dir)
        .unwrap()
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if let Some(ext) = path.extension() {
                if ext == "profraw" {
                    return Some(path);
                }
            }
            None
        })
        .collect();

    let status = process::Command::new(llvm_profdata)
        .arg("merge")
        .arg("--sparse")
        .args(profraw_files)
        .arg("--output")
        .arg(&profdata_file)
        .status()
        .expect("Failed to spawn llvm-profdata process");

    if !status.success() {
        process::exit(status.code().unwrap_or(1));
    }

    let mut child = process::Command::new(llvm_cov)
        .arg("export")
        .arg("-format=lcov")
        .arg("-instr-profile")
        .arg(&profdata_file)
        .arg("-ignore-filename-regex='.*external/.+'")
        .arg("-ignore-filename-regex='/tmp/.+'")
        .arg(format!("-path-equivalence=.,'{}'", execroot.display()))
        .arg(test_binary)
        .stdout(process::Stdio::piped())
        .spawn()
        .expect("Failed to spawn llvm-cov process");

    child.wait().expect("llvm-cov process failed");

    // Parse the child process's stdout to a string now that it's complete.
    let stdout = child.stdout.unwrap();
    let mut report_str = String::new();
    io::BufReader::new(stdout)
        .read_to_string(&mut report_str)
        .unwrap();

    fs::write(
        coverage_output_file,
        report_str
            .replace("#/proc/self/cwd/", "")
            .replace(&execroot.display().to_string(), ""),
    )
    .unwrap();

    // Destroy the intermediate binary file so lcov_merger doesn't parse twice.
    fs::remove_file(profdata_file).unwrap();
}
