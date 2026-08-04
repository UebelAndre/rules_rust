//! Invisible JUnit XML observer for Bazel `rust_test` targets.
//!
//! This crate is injected as a private dependency of every `rust_test` when
//! the `//rust/settings:experimental_use_libtest_bzl` flag is enabled. Test
//! code never references it; the rule links the rlib whole (via rustc's
//! `-l static:+whole-archive,+verbatim` modifiers) so a pre-`main`
//! constructor survives dead-code elimination and activates an observer
//! when `XML_OUTPUT_FILE` is set. The observer tees the process's stdout —
//! the user-visible output passes through byte-for-byte — while parsing
//! libtest's default `pretty` format to write JUnit XML for Bazel's test
//! metadata collection.
//!
//! Because it observes libtest itself rather than the `#[test]` attribute,
//! everything libtest handles is reported faithfully: `#[should_panic]`,
//! `#[ignore]`, `Result`-returning tests, filtering, threading, and any
//! macro that expands to `#[test]` (`#[tokio::test]`, `#[rstest]`, ...).
//! No wrapper process is created, so `--run_under`, `valgrind`, and debugger
//! workflows see a single ordinary process; without `XML_OUTPUT_FILE` (e.g.
//! `bazel run`) the constructor does nothing at all.
//!
//! # Limitations
//!
//! - Results are parsed from libtest's default `pretty` output. Passing
//!   `--format=terse` (or `-q`) degrades the XML to suite-level counts;
//!   unrecognized formats produce no XML, leaving Bazel's fallback intact.
//! - Per-test durations are not present in stable libtest output and are
//!   reported as zero; the suite-level time is measured by the observer.
//! - Tests filtered out on the command line are not listed (libtest only
//!   prints their count).
//! - Targets without an OS process model (wasm, wasi, emscripten, no_std)
//!   compile this crate to a no-op; the rule skips injection there anyway.
//!
//! Set `RULES_RUST_NO_JUNIT=1` to disable the observer at runtime, e.g. when
//! debugging under `bazel test`.

// On targets without the observer (wasm and friends) the parser and renderer
// are compiled but unreferenced.
#![cfg_attr(
    not(any(
        all(target_family = "unix", not(target_os = "emscripten")),
        target_os = "windows"
    )),
    allow(dead_code)
)]

mod junit;
mod parse;

#[cfg(any(
    all(target_family = "unix", not(target_os = "emscripten")),
    target_os = "windows"
))]
mod observer;
