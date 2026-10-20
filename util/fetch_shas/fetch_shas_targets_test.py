"""Checks that `fetch_shas_TARGETS.txt` lists every platform `rules_rust` can describe.

The list is the superset of targets the releases publish; this makes sure
`ALL_PLATFORM_TRIPLES` never falls out of it.
"""

import sys
from pathlib import Path


def main() -> int:
    targets_file, platform_triples_file = (Path(arg) for arg in sys.argv[1:3])
    targets = set(targets_file.read_text().split())
    missing = sorted(set(platform_triples_file.read_text().split()) - targets)
    if missing:
        print(
            "{} is missing platforms rules_rust can describe: {}\n"
            "Run `bazel run //util/fetch_shas -- --update-targets` to refresh it.".format(
                targets_file.name, " ".join(missing)
            ),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
