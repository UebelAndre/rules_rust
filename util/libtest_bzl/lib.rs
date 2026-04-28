// Copyright 2026 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#![cfg_attr(libtest_bzl_nightly, feature(test))]

#[cfg(libtest_bzl_nightly)]
extern crate test;

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::{env, fs, io, process};

const GUARD_ENV: &str = "_LIBTEST_BZL";

#[doc(hidden)]
pub fn _setup() {
    if env::var(GUARD_ENV).is_ok() {
        return;
    }

    let needs_sharding = env::var("TEST_TOTAL_SHARDS")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .is_some_and(|t| t > 1);
    let needs_xml = env::var("XML_OUTPUT_FILE").is_ok();

    if !needs_sharding && !needs_xml {
        return;
    }

    let exe = env::current_exe().expect("libtest_bzl: cannot determine test binary path");

    let shard_filters = if needs_sharding {
        compute_shard_filters(&exe)
    } else {
        vec![]
    };

    let mut cmd = process::Command::new(&exe);
    cmd.env(GUARD_ENV, "1");
    cmd.stderr(process::Stdio::inherit());

    if needs_xml {
        cmd.stdout(process::Stdio::piped());
    } else {
        cmd.stdout(process::Stdio::inherit());
    }

    if !shard_filters.is_empty() {
        cmd.arg("--exact");
        for test in &shard_filters {
            cmd.arg(test);
        }
    }

    for arg in env::args().skip(1) {
        cmd.arg(&arg);
    }

    let status = if needs_xml {
        let output = cmd.output().expect("libtest_bzl: failed to exec test binary");
        let stdout = String::from_utf8_lossy(&output.stdout);
        let results = parse_terse_output(&stdout);
        let xml = results_to_junit_xml(&results);

        if let Ok(path) = env::var("XML_OUTPUT_FILE") {
            fs::write(&path, &xml).expect("libtest_bzl: failed to write XML_OUTPUT_FILE");
        }

        io::stdout()
            .write_all(&output.stdout)
            .expect("libtest_bzl: failed to write stdout");
        output.status
    } else {
        cmd.status().expect("libtest_bzl: failed to exec test binary")
    };

    process::exit(status.code().unwrap_or(1));
}

fn compute_shard_filters(exe: &std::path::Path) -> Vec<String> {
    let total: usize = env::var("TEST_TOTAL_SHARDS").unwrap().parse().unwrap();
    let index: usize = env::var("TEST_SHARD_INDEX")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    if let Ok(path) = env::var("TEST_SHARD_STATUS_FILE") {
        let _ = fs::File::create(path);
    }

    let output = process::Command::new(exe)
        .arg("--list")
        .arg("--format=terse")
        .env(GUARD_ENV, "1")
        .output()
        .expect("libtest_bzl: failed to list tests");

    let tests: Vec<String> = std::str::from_utf8(&output.stdout)
        .unwrap_or("")
        .lines()
        .filter_map(|line| line.strip_suffix(": test").map(String::from))
        .collect();

    let filtered: Vec<String> = tests
        .into_iter()
        .filter(|name| {
            let mut h = DefaultHasher::new();
            name.hash(&mut h);
            (h.finish() as usize) % total == index
        })
        .collect();

    if filtered.is_empty() {
        if let Ok(path) = env::var("XML_OUTPUT_FILE") {
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
                       <testsuites>\n\
                       <testsuite name=\"\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\" time=\"0.0\"/>\n\
                       </testsuites>\n";
            let _ = fs::write(&path, xml);
        }
        process::exit(0);
    }

    filtered
}

struct TestResult {
    name: String,
    outcome: TestOutcome,
}

enum TestOutcome {
    Ok,
    Failed,
    Ignored,
}

// Parses libtest's default terse output. Each test line looks like:
//   test test_name ... ok
//   test test_name ... FAILED
//   test test_name ... ignored
fn parse_terse_output(output: &str) -> Vec<TestResult> {
    let mut results = Vec::new();
    for line in output.lines() {
        let line = line.trim();
        if !line.starts_with("test ") {
            continue;
        }
        if let Some(rest) = line.strip_prefix("test ") {
            if let Some(name) = rest.strip_suffix(" ... ok") {
                results.push(TestResult {
                    name: name.to_string(),
                    outcome: TestOutcome::Ok,
                });
            } else if let Some(name) = rest.strip_suffix(" ... FAILED") {
                results.push(TestResult {
                    name: name.to_string(),
                    outcome: TestOutcome::Failed,
                });
            } else if let Some(name) = rest.strip_suffix(" ... ignored") {
                results.push(TestResult {
                    name: name.to_string(),
                    outcome: TestOutcome::Ignored,
                });
            }
        }
    }
    results
}

fn results_to_junit_xml(results: &[TestResult]) -> String {
    let total = results.len();
    let failures = results
        .iter()
        .filter(|r| matches!(r.outcome, TestOutcome::Failed))
        .count();
    let skipped = results
        .iter()
        .filter(|r| matches!(r.outcome, TestOutcome::Ignored))
        .count();

    let mut xml = String::new();
    xml.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<testsuites>\n");
    xml.push_str(&format!(
        "<testsuite name=\"\" tests=\"{}\" failures=\"{}\" errors=\"0\" skipped=\"{}\">\n",
        total, failures, skipped
    ));

    for result in results {
        let escaped_name = xml_escape(&result.name);
        match &result.outcome {
            TestOutcome::Ok => {
                xml.push_str(&format!("<testcase name=\"{}\"/>\n", escaped_name));
            }
            TestOutcome::Failed => {
                xml.push_str(&format!("<testcase name=\"{}\">\n", escaped_name));
                xml.push_str("<failure message=\"test failed\"/>\n");
                xml.push_str("</testcase>\n");
            }
            TestOutcome::Ignored => {
                xml.push_str(&format!("<testcase name=\"{}\">\n", escaped_name));
                xml.push_str("<skipped message=\"ignored\"/>\n");
                xml.push_str("</testcase>\n");
            }
        }
    }

    xml.push_str("</testsuite>\n");
    xml.push_str("</testsuites>\n");
    xml
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

/// Nightly test runner used via `#![test_runner(::libtest_bzl::runner)]`.
/// Injected automatically by `-Zcrate-attr` when the toolchain is nightly.
/// Handles sharding and JUnit XML, then delegates to `test::test_main_static`.
#[cfg(libtest_bzl_nightly)]
pub fn runner(tests: &[&test::TestDescAndFn]) {
    if env::var(GUARD_ENV).is_ok() {
        test::test_main_static(tests);
        return;
    }

    let needs_sharding = env::var("TEST_TOTAL_SHARDS")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .is_some_and(|t| t > 1);
    let needs_xml = env::var("XML_OUTPUT_FILE").is_ok();

    if !needs_sharding && !needs_xml {
        test::test_main_static(tests);
        return;
    }

    _setup();
}

/// Register a pre-main constructor that handles Bazel test sharding and
/// JUnit XML output. Place this at module scope in your test crate:
///
/// ```ignore
/// libtest_bzl::init!();
/// ```
#[macro_export]
macro_rules! init {
    () => {
        #[cfg(test)]
        mod __libtest_bzl_init {
            #[used]
            #[cfg_attr(target_os = "linux", link_section = ".init_array")]
            #[cfg_attr(target_os = "freebsd", link_section = ".init_array")]
            #[cfg_attr(target_os = "macos", link_section = "__DATA,__mod_init_func")]
            #[cfg_attr(
                all(target_os = "windows", target_env = "msvc"),
                link_section = ".CRT$XCU"
            )]
            #[cfg_attr(
                all(target_os = "windows", target_env = "gnu"),
                link_section = ".ctors"
            )]
            static __INIT: unsafe extern "C" fn() = {
                unsafe extern "C" fn __libtest_bzl_ctor() {
                    ::libtest_bzl::_setup();
                }
                __libtest_bzl_ctor
            };
        }
    };
}
