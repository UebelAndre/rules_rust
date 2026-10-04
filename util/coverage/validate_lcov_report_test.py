"""Tests for `validate_lcov_report.py`."""

import textwrap
import unittest

from util.coverage import validate_lcov_report as v


def _lcov(*blocks: str) -> str:
    return "\n".join(textwrap.dedent(block).strip() + "\nend_of_record" for block in blocks) + "\n"


class ParseTest(unittest.TestCase):
    def test_parses_lf_lh(self):
        records = v.parse_lcov(_lcov("SF:test/lib.rs\nLH:2\nLF:3"))
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].source, "test/lib.rs")
        self.assertEqual(records[0].found, 3)
        self.assertEqual(records[0].hit, 2)

    def test_derives_counts_from_da_when_totals_missing(self):
        records = v.parse_lcov(_lcov("SF:a.rs\nDA:1,0\nDA:2,5\nDA:3,1"))
        self.assertEqual(records[0].found, 3)
        self.assertEqual(records[0].hit, 2)

    def test_tolerates_missing_end_of_record_and_test_names(self):
        text = "TN:\nSF:a.rs\nLF:1\nSF:b.rs\nLF:2\n"
        records = v.parse_lcov(text)
        self.assertEqual([record.source for record in records], ["a.rs", "b.rs"])

    def test_normalizes_sources(self):
        self.assertEqual(v.normalize_source("./a/b.rs"), "a/b.rs")
        self.assertEqual(v.normalize_source("a\\b.rs"), "a/b.rs")

    def test_rejects_malformed_counts(self):
        with self.assertRaises(ValueError):
            v.parse_lcov(_lcov("SF:a.rs\nLF:many"))


class ValidateTest(unittest.TestCase):
    GOOD = _lcov(
        "SF:test/generated_inputs/lib.rs\nLH:4\nLF:9",
        "SF:test/unit/coverage/test.rs\nLH:3\nLF:3",
        "SF:test/cc_shared_library/lib.c\nLH:0\nLF:0",
    )

    def test_accepts_real_coverage(self):
        records = v.parse_lcov(self.GOOD)
        self.assertEqual(
            v.validate(records, require_extensions=[".rs"], require_sources=["test/generated_inputs/lib.rs"], require_hits=True),
            [],
        )

    def test_rejects_empty_report(self):
        self.assertTrue(v.validate([], require_extensions=[".rs"]))

    def test_rejects_missing_extension(self):
        records = v.parse_lcov(_lcov("SF:main.c\nLH:1\nLF:1"))
        errors = v.validate(records, require_extensions=[".rs"])
        self.assertEqual(len(errors), 1)
        self.assertIn("'.rs'", errors[0])

    def test_rejects_baseline_only_report(self):
        records = v.parse_lcov(_lcov("SF:a.rs\nLH:0\nLF:0", "SF:b.rs\nLH:0\nLF:0"))
        errors = v.validate(records, require_extensions=[".rs"])
        self.assertEqual(len(errors), 1)
        self.assertIn("LF is 0 everywhere", errors[0])

    def test_rejects_missing_required_source(self):
        records = v.parse_lcov(self.GOOD)
        errors = v.validate(records, require_sources=["does/not/exist.rs"])
        self.assertEqual(errors, ["No coverage record for 'does/not/exist.rs'."])

    def test_rejects_required_source_without_lines(self):
        records = v.parse_lcov(self.GOOD)
        errors = v.validate(records, require_sources=["test/cc_shared_library/lib.c"])
        self.assertEqual(len(errors), 1)
        self.assertIn("silently dropped", errors[0])

    def test_rejects_required_source_without_hits_when_requested(self):
        records = v.parse_lcov(_lcov("SF:a.rs\nLH:0\nLF:5"))
        self.assertEqual(v.validate(records, require_sources=["a.rs"]), [])
        errors = v.validate(records, require_sources=["a.rs"], require_hits=True)
        self.assertEqual(len(errors), 1)
        self.assertIn("none were executed", errors[0])

    def test_required_source_matches_with_path_prefix(self):
        records = v.parse_lcov(_lcov("SF:/proc/self/cwd/test/lib.rs\nLH:1\nLF:1"))
        self.assertEqual(v.validate(records, require_sources=["test/lib.rs"]), [])
        self.assertTrue(v.validate(records, require_sources=["lib.rs"]) == [])
        self.assertTrue(v.validate(records, require_sources=["b.rs"]))


class MainTest(unittest.TestCase):
    def test_main_reports_missing_file(self):
        self.assertEqual(v.main(["--report", "/nonexistent/report.dat"]), 1)


if __name__ == "__main__":
    unittest.main()
