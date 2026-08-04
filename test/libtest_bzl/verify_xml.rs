//! Spawns the fixture binary (built with the observer injected via the
//! `experimental_use_libtest_bzl` flag) under various conditions and inspects
//! the JUnit XML it writes to `XML_OUTPUT_FILE`.

use std::path::PathBuf;
use std::process::Command;

use runfiles::{rlocation, Runfiles};

fn fixture_path() -> PathBuf {
    let r = Runfiles::create().expect("runfiles setup");
    rlocation!(r, "rules_rust/test/libtest_bzl/fixture_test").expect("fixture runfile lookup")
}

fn xml_output_path(tag: &str) -> PathBuf {
    std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("libtest_bzl_{}.xml", tag))
}

fn run_fixture_with(
    tag: &str,
    extra_args: &[&str],
    envs: &[(&str, &str)],
    expect_success: bool,
) -> String {
    let out = xml_output_path(tag);
    let _ = std::fs::remove_file(&out);
    let mut command = Command::new(fixture_path());
    command.args(extra_args).env("XML_OUTPUT_FILE", &out);
    for (key, value) in envs {
        command.env(key, value);
    }
    let status = command.status().expect("fixture spawn");
    assert_eq!(
        status.success(),
        expect_success,
        "fixture exited with {:?}",
        status
    );
    std::fs::read_to_string(&out).expect("read XML output")
}

fn run_fixture(tag: &str, extra_args: &[&str]) -> String {
    run_fixture_with(tag, extra_args, &[], true)
}

/// Extract the `<testcase ...>` element (self-closing or not) for a name,
/// including its terminator.
fn testcase<'a>(xml: &'a str, name: &str) -> &'a str {
    let needle = format!("name=\"{}\"", name);
    let idx = xml
        .find(&needle)
        .unwrap_or_else(|| panic!("{} not present in xml:\n{}", name, xml));
    let after = &xml[idx..];
    let end = match (after.find("/>"), after.find("</testcase>")) {
        (Some(s), Some(f)) if s < f => s + "/>".len(),
        (_, Some(f)) => f + "</testcase>".len(),
        (Some(s), None) => s + "/>".len(),
        (None, None) => panic!("no case terminator for {}:\n{}", name, after),
    };
    &after[..end]
}

#[test]
fn reports_expected_counts() {
    let xml = run_fixture("counts", &[]);
    assert!(xml.contains("tests=\"8\""), "xml=\n{}", xml);
    assert!(xml.contains("failures=\"0\""), "xml=\n{}", xml);
    assert!(xml.contains("errors=\"0\""), "xml=\n{}", xml);
    assert!(xml.contains("skipped=\"1\""), "xml=\n{}", xml);
}

#[test]
fn ignored_test_appears_as_skipped() {
    let xml = run_fixture("ignored", &[]);
    let case = testcase(&xml, "ignored_test");
    assert!(
        case.contains("<skipped/>"),
        "expected <skipped/> in ignored_test case:\n{}",
        case
    );
}

#[test]
fn should_panic_reports_as_passing() {
    let xml = run_fixture("should_panic", &[]);
    for name in ["expected_panic", "expected_panic_with_message"] {
        let case = testcase(&xml, name);
        assert!(
            !case.contains("<failure"),
            "unexpected <failure> for {}:\n{}",
            name,
            case
        );
    }
}

#[test]
fn passing_tests_have_classname_and_suite_time() {
    let xml = run_fixture("passing", &[]);
    for name in ["always_passes", "also_passes"] {
        let needle = format!("name=\"{}\"", name);
        assert!(xml.contains(&needle), "{} missing from xml:\n{}", name, xml);
    }
    // Root-level tests use the binary name as their classname.
    assert!(
        xml.contains("classname=\"fixture_test\""),
        "expected classname=\"fixture_test\" in xml:\n{}",
        xml
    );
    assert!(
        xml.contains("time=\""),
        "expected time attribute in xml:\n{}",
        xml
    );
}

#[test]
fn filtered_run_reports_only_matching_tests() {
    let xml = run_fixture("filter", &["always_passes"]);
    // libtest only prints a count for filtered-out tests, so the XML lists
    // just the test that ran.
    assert!(xml.contains("tests=\"1\""), "xml=\n{}", xml);
    assert!(
        xml.contains("name=\"always_passes\""),
        "always_passes should be present:\n{}",
        xml
    );
    assert!(
        !xml.contains("name=\"also_passes\""),
        "also_passes should not be listed when filtered out:\n{}",
        xml
    );
}

#[test]
fn failures_are_reported_with_detail() {
    let xml = run_fixture_with("failures", &[], &[("LIBTEST_BZL_FIXTURE_FAIL", "1")], false);
    assert!(xml.contains("failures=\"2\""), "xml=\n{}", xml);

    let case = testcase(&xml, "env_conditioned_failure");
    assert!(case.contains("<failure"), "expected <failure>:\n{}", case);
    assert!(
        case.contains("intentional fixture failure"),
        "expected panic message in failure detail:\n{}",
        case
    );

    let case = testcase(&xml, "env_conditioned_result_failure");
    assert!(case.contains("<failure"), "expected <failure>:\n{}", case);
    assert!(
        case.contains("intentional fixture error"),
        "expected Err message in failure detail:\n{}",
        case
    );
}

#[test]
fn terse_format_degrades_to_suite_counts() {
    let xml = run_fixture("terse", &["--format=terse"]);
    assert!(xml.contains("tests=\"8\""), "xml=\n{}", xml);
    assert!(xml.contains("failures=\"0\""), "xml=\n{}", xml);
    assert!(xml.contains("skipped=\"1\""), "xml=\n{}", xml);
    assert!(
        !xml.contains("<testcase"),
        "terse output should degrade to suite-level counts:\n{}",
        xml
    );
}

#[test]
fn abort_mid_suite_leaves_partial_xml() {
    // Run two tests sequentially; the second aborts the process (no atexit,
    // no unwind). The incrementally-written XML must still report the test
    // that completed.
    let xml = run_fixture_with(
        "abort",
        &["--test-threads=1", "always_passes", "zz_aborts_when_asked"],
        &[("LIBTEST_BZL_FIXTURE_ABORT", "1")],
        false,
    );
    assert!(
        xml.contains("name=\"always_passes\""),
        "completed test missing from partial xml:\n{}",
        xml
    );
}
