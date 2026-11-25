#!/usr/bin/env bash
# Runs the no_std program and checks the exit status it computed:
# 64 bytes of 0x5a sum to 5760, which is 128 modulo 256.
set -u
"$1"
status=$?
if [[ "${status}" -ne 128 ]]; then
    echo >&2 "expected the program to exit with 128, got ${status}"
    exit 1
fi
