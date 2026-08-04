//! JUnit XML rendering for parsed libtest results.

use std::fmt::Write;

use crate::parse::{Case, Outcome, Summary};

/// Render a JUnit XML document.
///
/// When per-test cases were parsed they are the source of truth. When only a
/// summary is available (e.g. the test ran with `--format=terse`), a
/// suite-level entry with aggregate counts is emitted instead.
pub(crate) fn render(
    suite_name: &str,
    cases: &[Case],
    summary: Option<&Summary>,
    suite_time_secs: f64,
) -> String {
    let (tests, failures, skipped) = if cases.is_empty() {
        match summary {
            Some(s) => (
                (s.passed + s.failed + s.ignored + s.measured) as usize,
                s.failed as usize,
                s.ignored as usize,
            ),
            None => (0, 0, 0),
        }
    } else {
        (
            cases.len(),
            cases
                .iter()
                .filter(|c| c.outcome == Outcome::Failed)
                .count(),
            cases
                .iter()
                .filter(|c| c.outcome == Outcome::Ignored)
                .count(),
        )
    };

    let mut out = String::with_capacity(256 + cases.len() * 128);
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    out.push_str("<testsuites>\n");
    let _ = writeln!(
        out,
        "  <testsuite name=\"{name}\" tests=\"{tests}\" failures=\"{failures}\" \
         errors=\"0\" skipped=\"{skipped}\" time=\"{time:.6}\">",
        name = escape_attr(suite_name),
        tests = tests,
        failures = failures,
        skipped = skipped,
        time = suite_time_secs,
    );
    for case in cases {
        let (classname, name) = split_classname(&case.name);
        let classname = if classname.is_empty() {
            suite_name
        } else {
            classname
        };
        match case.outcome {
            Outcome::Passed => {
                let _ = writeln!(
                    out,
                    "    <testcase classname=\"{cls}\" name=\"{n}\" time=\"0.000000\"/>",
                    cls = escape_attr(classname),
                    n = escape_attr(name),
                );
            }
            Outcome::Failed => {
                let detail = case.detail.as_deref().unwrap_or("");
                let message = detail
                    .lines()
                    .find(|l| !l.trim().is_empty())
                    .unwrap_or("test failed");
                let body = if detail.is_empty() { message } else { detail };
                let _ = writeln!(
                    out,
                    "    <testcase classname=\"{cls}\" name=\"{n}\" time=\"0.000000\">",
                    cls = escape_attr(classname),
                    n = escape_attr(name),
                );
                let _ = writeln!(
                    out,
                    "      <failure message=\"{msg}\">{body}</failure>",
                    msg = escape_attr(message),
                    body = escape_text(body),
                );
                out.push_str("    </testcase>\n");
            }
            Outcome::Ignored => {
                let _ = writeln!(
                    out,
                    "    <testcase classname=\"{cls}\" name=\"{n}\">",
                    cls = escape_attr(classname),
                    n = escape_attr(name),
                );
                out.push_str("      <skipped/>\n");
                out.push_str("    </testcase>\n");
            }
        }
    }
    out.push_str("  </testsuite>\n");
    out.push_str("</testsuites>\n");
    out
}

fn split_classname(fully_qualified: &str) -> (&str, &str) {
    match fully_qualified.rfind("::") {
        Some(idx) => (&fully_qualified[..idx], &fully_qualified[idx + 2..]),
        None => ("", fully_qualified),
    }
}

fn escape_attr(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            '\n' => out.push_str("&#10;"),
            '\r' => out.push_str("&#13;"),
            '\t' => out.push_str("&#9;"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "&#{};", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

fn escape_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            c if (c as u32) < 0x20 && c != '\n' && c != '\r' && c != '\t' => {
                let _ = write!(out, "&#{};", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn case(name: &str, outcome: Outcome, detail: Option<&str>) -> Case {
        Case {
            name: name.to_string(),
            outcome,
            detail: detail.map(str::to_string),
        }
    }

    #[test]
    fn renders_cases() {
        let cases = vec![
            case("always_passes", Outcome::Passed, None),
            case(
                "tests::nested_fail",
                Outcome::Failed,
                Some("thread panicked\nat somewhere"),
            ),
            case("skipped_one", Outcome::Ignored, None),
        ];
        let xml = render("my_suite", &cases, None, 1.25);
        assert!(xml.contains("tests=\"3\""), "{xml}");
        assert!(xml.contains("failures=\"1\""), "{xml}");
        assert!(xml.contains("skipped=\"1\""), "{xml}");
        assert!(xml.contains("time=\"1.250000\""), "{xml}");
        // Root-level tests fall back to the suite name as classname.
        assert!(
            xml.contains("<testcase classname=\"my_suite\" name=\"always_passes\""),
            "{xml}"
        );
        assert!(
            xml.contains("<testcase classname=\"tests\" name=\"nested_fail\""),
            "{xml}"
        );
        assert!(xml.contains("message=\"thread panicked\""), "{xml}");
        assert!(xml.contains("<skipped/>"), "{xml}");
    }

    #[test]
    fn renders_summary_only() {
        let summary = Summary {
            passed: 5,
            failed: 2,
            ignored: 1,
            measured: 0,
            filtered_out: 3,
        };
        let xml = render("my_suite", &[], Some(&summary), 0.5);
        assert!(xml.contains("tests=\"8\""), "{xml}");
        assert!(xml.contains("failures=\"2\""), "{xml}");
        assert!(xml.contains("skipped=\"1\""), "{xml}");
        assert!(!xml.contains("<testcase"), "{xml}");
    }

    #[test]
    fn escapes_special_characters() {
        let cases = vec![case(
            "quotes",
            Outcome::Failed,
            Some("expected \"a\" < \"b\" & more"),
        )];
        let xml = render("suite", &cases, None, 0.0);
        assert!(
            xml.contains("message=\"expected &quot;a&quot; &lt; &quot;b&quot; &amp; more\""),
            "{xml}"
        );
        assert!(
            xml.contains(">expected \"a\" &lt; \"b\" &amp; more</failure>"),
            "{xml}"
        );
    }
}
