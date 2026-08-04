//! Incremental parser for libtest's default ("pretty") console output.
//!
//! The observer feeds this parser one line at a time as bytes flow through
//! the stdout tee. It recognizes:
//!
//! - result lines: `test <name> ... ok` / `FAILED` / `ignored[, reason]` /
//!   `bench: ...`, optionally with a `--report-time` suffix after the status
//! - failure detail blocks: `---- <name> stdout ----` followed by the
//!   captured output, terminated by the next block, the `failures:` list, or
//!   the summary line
//! - the summary line: `test result: ok. 5 passed; 0 failed; ...`
//!
//! Anything unrecognized (user test output, libtest banners) is ignored.
//! When only a summary is seen (e.g. the test was invoked with
//! `--format=terse`), the model degrades to suite-level counts.

/// The outcome of a single test as printed by libtest.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Outcome {
    Passed,
    Failed,
    Ignored,
}

/// A single test's parsed result.
#[derive(Clone, Debug)]
pub(crate) struct Case {
    /// Fully-qualified test name as printed by libtest (e.g. `tests::foo`).
    pub(crate) name: String,
    pub(crate) outcome: Outcome,
    /// Captured output from this test's `---- <name> stdout ----` block in
    /// the failures section, if one was printed.
    pub(crate) detail: Option<String>,
}

/// Counts from libtest's `test result:` summary line.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Summary {
    pub(crate) passed: u64,
    pub(crate) failed: u64,
    pub(crate) ignored: u64,
    pub(crate) measured: u64,
    pub(crate) filtered_out: u64,
}

#[derive(Default)]
pub(crate) struct Parser {
    cases: Vec<Case>,
    summary: Option<Summary>,
    capture: Option<Capture>,
}

struct Capture {
    case_index: usize,
    lines: Vec<String>,
}

impl Parser {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    pub(crate) fn cases(&self) -> &[Case] {
        &self.cases
    }

    pub(crate) fn summary(&self) -> Option<&Summary> {
        self.summary.as_ref()
    }

    /// Whether anything meaningful was parsed. Used to decide whether to
    /// write an XML file at all (if nothing parsed, defer to Bazel's own
    /// fallback XML generation).
    pub(crate) fn has_data(&self) -> bool {
        !self.cases.is_empty() || self.summary.is_some()
    }

    /// Feed one line (without its trailing newline). Returns `true` when the
    /// parsed model changed in a way that warrants rewriting the XML file.
    pub(crate) fn feed_line(&mut self, line: &str) -> bool {
        let line = line.strip_suffix('\r').unwrap_or(line);

        if self.capture.is_some() {
            // A detail block ends at the next block header, the trailing
            // `failures:` name list, or the summary line. All three are then
            // re-examined as ordinary lines.
            let terminates =
                is_block_header(line) || line == "failures:" || line.starts_with("test result:");
            if !terminates {
                if let Some(capture) = self.capture.as_mut() {
                    capture.lines.push(line.to_string());
                }
                return false;
            }
            self.flush_capture();
        }

        if let Some(rest) = line.strip_prefix("test ") {
            if let Some((name, status)) = rest.split_once(" ... ") {
                // `#[should_panic]` tests print as `test <name> - should panic ... ok`.
                let name = name.strip_suffix(" - should panic").unwrap_or(name);
                if is_test_name(name) {
                    if let Some(outcome) = parse_status(status) {
                        self.record(name, outcome);
                        return true;
                    }
                }
            }
        }

        if let Some(name) = parse_block_header(line) {
            let case_index = match self.cases.iter().position(|c| c.name == name) {
                Some(index) => index,
                None => {
                    // A detail block for a test whose result line was missed
                    // (e.g. mangled by `--nocapture` interleaving). Blocks are
                    // only printed for failures, so record it as one.
                    self.cases.push(Case {
                        name: name.to_string(),
                        outcome: Outcome::Failed,
                        detail: None,
                    });
                    self.cases.len() - 1
                }
            };
            self.capture = Some(Capture {
                case_index,
                lines: Vec::new(),
            });
            return false;
        }

        if let Some(rest) = line.strip_prefix("test result: ") {
            self.summary = Some(parse_summary(rest));
            return true;
        }

        false
    }

    /// Signal end of input, flushing any detail block still being captured.
    pub(crate) fn finish(&mut self) {
        self.flush_capture();
    }

    fn record(&mut self, name: &str, outcome: Outcome) {
        // Result lines are unique per test in a single run; an existing entry
        // means the earlier one was a false positive (test output mimicking a
        // result line) or a synthesized failure from a detail block. Either
        // way the newest libtest-printed outcome wins.
        if let Some(case) = self.cases.iter_mut().find(|c| c.name == name) {
            case.outcome = outcome;
        } else {
            self.cases.push(Case {
                name: name.to_string(),
                outcome,
                detail: None,
            });
        }
    }

    fn flush_capture(&mut self) {
        let Some(capture) = self.capture.take() else {
            return;
        };
        let mut lines: &[String] = &capture.lines;
        while let Some(first) = lines.first() {
            if first.is_empty() {
                lines = &lines[1..];
            } else {
                break;
            }
        }
        while let Some(last) = lines.last() {
            if last.is_empty() {
                lines = &lines[..lines.len() - 1];
            } else {
                break;
            }
        }
        if lines.is_empty() {
            return;
        }
        if let Some(case) = self.cases.get_mut(capture.case_index) {
            case.detail = Some(lines.join("\n"));
        }
    }
}

fn is_test_name(name: &str) -> bool {
    !name.is_empty() && !name.contains(char::is_whitespace)
}

fn parse_status(status: &str) -> Option<Outcome> {
    // `--report-time` (and future additions) append after the status word;
    // match on the first token only.
    let first = status.split_whitespace().next()?;
    match first {
        "ok" => Some(Outcome::Passed),
        "FAILED" => Some(Outcome::Failed),
        "ignored" | "ignored," => Some(Outcome::Ignored),
        // `test x ... bench:   1,234 ns/iter (+/- 56)`
        "bench:" => Some(Outcome::Passed),
        _ => {
            if status.starts_with("ignored,") {
                Some(Outcome::Ignored)
            } else {
                None
            }
        }
    }
}

fn is_block_header(line: &str) -> bool {
    parse_block_header(line).is_some()
}

/// Parse `---- <name> stdout ----` (or `stderr`), returning the test name.
fn parse_block_header(line: &str) -> Option<&str> {
    let inner = line.strip_prefix("---- ")?.strip_suffix(" ----")?;
    let name = inner
        .strip_suffix(" stdout")
        .or_else(|| inner.strip_suffix(" stderr"))
        .unwrap_or(inner);
    let name = name.strip_suffix(" - should panic").unwrap_or(name);
    if is_test_name(name) {
        Some(name)
    } else {
        None
    }
}

/// Parse the tail of a summary line, e.g.
/// `ok. 5 passed; 0 failed; 1 ignored; 0 measured; 2 filtered out; finished in 0.02s`.
fn parse_summary(rest: &str) -> Summary {
    let mut summary = Summary::default();
    let tokens: Vec<&str> = rest.split_whitespace().collect();
    for pair in tokens.windows(2) {
        let Ok(count) = pair[0].parse::<u64>() else {
            continue;
        };
        match pair[1].trim_end_matches([';', '.']) {
            "passed" => summary.passed = count,
            "failed" => summary.failed = count,
            "ignored" => summary.ignored = count,
            "measured" => summary.measured = count,
            "filtered" => summary.filtered_out = count,
            _ => {}
        }
    }
    summary
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed(parser: &mut Parser, text: &str) {
        for line in text.lines() {
            parser.feed_line(line);
        }
        parser.finish();
    }

    #[test]
    fn parses_a_passing_run() {
        let mut parser = Parser::new();
        feed(
            &mut parser,
            "\nrunning 3 tests\n\
             test always_passes ... ok\n\
             test tests::nested ... ok\n\
             test skipme ... ignored\n\
             \n\
             test result: ok. 2 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.01s\n",
        );
        assert_eq!(parser.cases().len(), 3);
        assert_eq!(parser.cases()[0].name, "always_passes");
        assert_eq!(parser.cases()[0].outcome, Outcome::Passed);
        assert_eq!(parser.cases()[1].name, "tests::nested");
        assert_eq!(parser.cases()[2].outcome, Outcome::Ignored);
        let summary = parser.summary().expect("summary");
        assert_eq!(summary.passed, 2);
        assert_eq!(summary.ignored, 1);
    }

    #[test]
    fn parses_failure_detail() {
        let mut parser = Parser::new();
        feed(
            &mut parser,
            "running 2 tests\n\
             test good ... ok\n\
             test bad ... FAILED\n\
             \n\
             failures:\n\
             \n\
             ---- bad stdout ----\n\
             \n\
             thread 'bad' panicked at src/lib.rs:10:9:\n\
             assertion failed: false\n\
             note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace\n\
             \n\
             \n\
             failures:\n\
                 bad\n\
             \n\
             test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n",
        );
        let bad = parser
            .cases()
            .iter()
            .find(|c| c.name == "bad")
            .expect("bad case");
        assert_eq!(bad.outcome, Outcome::Failed);
        let detail = bad.detail.as_deref().expect("detail");
        assert!(detail.contains("panicked at src/lib.rs:10:9"));
        assert!(detail.contains("assertion failed: false"));
        assert_eq!(parser.summary().expect("summary").failed, 1);
    }

    #[test]
    fn multiple_detail_blocks() {
        let mut parser = Parser::new();
        feed(
            &mut parser,
            "test a ... FAILED\n\
             test b ... FAILED\n\
             \n\
             failures:\n\
             \n\
             ---- a stdout ----\n\
             first failure\n\
             \n\
             ---- b stdout ----\n\
             second failure\n\
             \n\
             failures:\n\
                 a\n\
                 b\n",
        );
        assert_eq!(parser.cases()[0].detail.as_deref(), Some("first failure"));
        assert_eq!(parser.cases()[1].detail.as_deref(), Some("second failure"));
    }

    #[test]
    fn should_panic_suffix_is_stripped() {
        let mut parser = Parser::new();
        assert!(parser.feed_line("test expected_panic - should panic ... ok"));
        assert!(parser.feed_line("test tests::no_panic - should panic ... FAILED"));
        assert_eq!(parser.cases()[0].name, "expected_panic");
        assert_eq!(parser.cases()[0].outcome, Outcome::Passed);
        assert_eq!(parser.cases()[1].name, "tests::no_panic");
        assert_eq!(parser.cases()[1].outcome, Outcome::Failed);
    }

    #[test]
    fn report_time_suffix_and_reasons() {
        let mut parser = Parser::new();
        parser.feed_line("test timed ... ok <0.123s>");
        parser.feed_line("test reason ... ignored, not supported here");
        parser.feed_line("test bench_x ... bench:      12,345 ns/iter (+/- 67)");
        assert_eq!(parser.cases()[0].outcome, Outcome::Passed);
        assert_eq!(parser.cases()[1].outcome, Outcome::Ignored);
        assert_eq!(parser.cases()[2].outcome, Outcome::Passed);
    }

    #[test]
    fn ignores_lookalike_user_output() {
        let mut parser = Parser::new();
        assert!(!parser.feed_line("test with spaces in name ... ok"));
        assert!(!parser.feed_line("test name ... exploded"));
        assert!(!parser.feed_line("testing something ... ok"));
        assert!(!parser.feed_line("some ordinary println output"));
        assert!(parser.cases().is_empty());
    }

    #[test]
    fn terse_output_yields_summary_only() {
        let mut parser = Parser::new();
        feed(
            &mut parser,
            "........\n\
             test result: ok. 8 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n",
        );
        assert!(parser.cases().is_empty());
        assert!(parser.has_data());
        assert_eq!(parser.summary().expect("summary").passed, 8);
    }

    #[test]
    fn no_data_without_libtest_output() {
        let mut parser = Parser::new();
        feed(&mut parser, "hello world\nnot a test\n");
        assert!(!parser.has_data());
    }
}
