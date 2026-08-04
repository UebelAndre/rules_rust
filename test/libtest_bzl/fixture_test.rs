//! Fixture test binary consumed by `verify_xml_test`. Note that it contains
//! no reference to the observer crate — the `experimental_use_libtest_bzl`
//! flag injects it invisibly. The fixture must pass under `bazel test` on its
//! own: failing behaviors are gated behind environment variables the verifier
//! sets when spawning it.

#[test]
fn always_passes() {
    assert_eq!(1 + 1, 2);
}

#[test]
fn also_passes() {
    let xs: Vec<i32> = (0..10).collect();
    assert_eq!(xs.len(), 10);
}

#[test]
#[should_panic]
fn expected_panic() {
    panic!("boom");
}

#[test]
#[should_panic(expected = "specific")]
fn expected_panic_with_message() {
    panic!("some specific message");
}

#[test]
#[ignore]
fn ignored_test() {
    unreachable!("this should not run without --include-ignored");
}

#[test]
fn env_conditioned_failure() {
    if std::env::var_os("LIBTEST_BZL_FIXTURE_FAIL").is_some() {
        panic!("intentional fixture failure");
    }
}

#[test]
fn env_conditioned_result_failure() -> Result<(), String> {
    if std::env::var_os("LIBTEST_BZL_FIXTURE_FAIL").is_some() {
        return Err("intentional fixture error".to_string());
    }
    Ok(())
}

// Declared last: with `--test-threads=1` every other selected test completes
// before this one takes the process down, which is what the crash-resilience
// verification relies on. The sleep gives the observer's tee thread time to
// drain earlier result lines from the pipe — an abort forfeits everything
// still in flight (no atexit, no unwind), and "everything up to roughly the
// moment of death" is exactly the guarantee being verified.
#[test]
fn zz_aborts_when_asked() {
    if std::env::var_os("LIBTEST_BZL_FIXTURE_ABORT").is_some() {
        std::thread::sleep(std::time::Duration::from_millis(1000));
        std::process::abort();
    }
}
