#!/usr/bin/env python3
"""Validate that an LCOV tracefile contains real coverage data.

`bazel coverage` writes `bazel-out/_coverage/_coverage_report.dat` even when
every test silently produced no data, in which case the report only holds the
zero-line baseline records. This script checks that coverage was actually
written: that sources with the expected extensions are present, that at least
one record has instrumented lines, and that specific sources known to be at
risk (for example crates with generated sources) carry line data.

Usage:

    validate_lcov_report.py --report bazel-out/_coverage/_coverage_report.dat \\
        --require-extension .rs \\
        --require-source test/generated_inputs/lib.rs

The exit code is 0 when every check passes and 1 otherwise, with a summary of
the report on stderr to make CI failures diagnosable without the file.
"""

import argparse
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Sequence

# Kept compatible with Python 3.6, the system interpreter of the oldest CI
# image this runs on, so no dataclasses or newer syntax.


class Record:
    """One `SF:` ... `end_of_record` block of an LCOV tracefile."""

    def __init__(self, source: str) -> None:
        self.source = source
        self.lines_found = None  # type: Optional[int]
        self.lines_hit = None  # type: Optional[int]
        self.da_lines = 0
        self.da_hit = 0

    @property
    def found(self) -> int:
        """Instrumented lines, from `LF:` or derived from `DA:` entries."""
        return self.lines_found if self.lines_found is not None else self.da_lines

    @property
    def hit(self) -> int:
        """Executed lines, from `LH:` or derived from `DA:` entries."""
        return self.lines_hit if self.lines_hit is not None else self.da_hit


def normalize_source(path: str) -> str:
    """Normalize a source path as written in an `SF:` line."""
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def parse_lcov(text: str) -> List[Record]:
    """Parse the records of an LCOV tracefile.

    Only the line-coverage fields are interpreted. Function and branch data
    are accepted and ignored. A record missing its `end_of_record` terminator
    is closed by the next `SF:` line or the end of the input.
    """
    records: List[Record] = []
    current: Optional[Record] = None

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("SF:"):
            if current is not None:
                records.append(current)
            current = Record(source=normalize_source(line[3:]))
            continue
        if line == "end_of_record":
            if current is not None:
                records.append(current)
                current = None
            continue
        if current is None:
            # `TN:` and anything else outside a record.
            continue
        try:
            if line.startswith("LF:"):
                current.lines_found = int(line[3:])
            elif line.startswith("LH:"):
                current.lines_hit = int(line[3:])
            elif line.startswith("DA:"):
                _, hits = line[3:].split(",")[:2]
                current.da_lines += 1
                if int(hits) > 0:
                    current.da_hit += 1
        except ValueError as err:
            raise ValueError(f"line {lineno}: malformed LCOV entry {line!r}") from err

    if current is not None:
        records.append(current)
    return records


def source_matches(record: Record, wanted: str) -> bool:
    """Whether a record is for `wanted`, tolerating prefixes such as `/proc/self/cwd/`."""
    wanted = normalize_source(wanted)
    return record.source == wanted or record.source.endswith("/" + wanted)


def validate(
    records: Sequence[Record],
    require_extensions: Iterable[str] = (),
    require_sources: Iterable[str] = (),
    require_hits: bool = False,
) -> List[str]:
    """Check a parsed report and return a list of human readable failures."""
    errors: List[str] = []

    if not records:
        errors.append("The report contains no coverage records.")
        return errors

    for extension in require_extensions:
        if not any(record.source.endswith(extension) for record in records):
            errors.append(f"No coverage records for sources ending in '{extension}'.")

    if not any(record.found > 0 for record in records):
        errors.append("No record has instrumented lines (LF is 0 everywhere); only baseline records were written.")

    for wanted in require_sources:
        matching = [record for record in records if source_matches(record, wanted)]
        if not matching:
            errors.append(f"No coverage record for '{wanted}'.")
        elif not any(record.found > 0 for record in matching):
            errors.append(
                f"'{wanted}' has no instrumented lines; coverage for it was silently dropped."
            )
        elif require_hits and not any(record.hit > 0 for record in matching):
            errors.append(f"'{wanted}' has instrumented lines but none were executed.")

    return errors


def summarize(records: Sequence[Record], max_records: int) -> str:
    """Render a compact table of the report for diagnostics."""
    total_found = sum(record.found for record in records)
    total_hit = sum(record.hit for record in records)
    lines = [f"{len(records)} records, {total_hit}/{total_found} lines hit"]
    width = max((len(record.source) for record in records[:max_records]), default=0)
    for record in records[:max_records]:
        lines.append(f"  {record.source.ljust(width)}  LF={record.found}  LH={record.hit}")
    if max_records and len(records) > max_records:
        lines.append(f"  ... {len(records) - max_records} more")
    return "\n".join(lines)


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("bazel-out/_coverage/_coverage_report.dat"),
        help="Path to the LCOV tracefile (default: %(default)s).",
    )
    parser.add_argument(
        "--require-extension",
        action="append",
        default=[],
        metavar="EXT",
        help="Require at least one record whose source ends in EXT (for example `.rs`). Repeatable.",
    )
    parser.add_argument(
        "--require-source",
        action="append",
        default=[],
        metavar="PATH",
        help="Require a record for PATH with at least one instrumented line. Repeatable.",
    )
    parser.add_argument(
        "--require-hits",
        action="store_true",
        help="Additionally require that each `--require-source` has executed lines.",
    )
    parser.add_argument(
        "--max-records",
        type=int,
        default=50,
        help="Maximum records to list in the diagnostic summary (default: %(default)s).",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)

    if not args.report.is_file():
        print(f"error: coverage report not found: {args.report}", file=sys.stderr)
        return 1

    try:
        records = parse_lcov(args.report.read_text())
    except ValueError as err:
        print(f"error: failed to parse {args.report}: {err}", file=sys.stderr)
        return 1

    errors = validate(
        records,
        require_extensions=args.require_extension,
        require_sources=args.require_source,
        require_hits=args.require_hits,
    )

    if errors:
        print(f"error: coverage validation failed for {args.report}:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print(summarize(records, args.max_records), file=sys.stderr)
        return 1

    print(f"Coverage report {args.report} is valid: {summarize(records, 0)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
