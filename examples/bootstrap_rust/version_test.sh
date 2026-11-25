#!/usr/bin/env bash
# Runs a tool for its version and checks what it reports starts as expected:
# the tool starts, finds what it loads, and is the release it was built from.
set -euo pipefail
tool="$1"
expected="$2"
version="$("${tool}" --version)"
echo "${version}"
if [[ "${version}" != "${expected}"* ]]; then
    echo >&2 "expected the version to start with '${expected}'"
    exit 1
fi
