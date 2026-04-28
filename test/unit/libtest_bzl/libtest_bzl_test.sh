#!/bin/sh

set -eu

TEST_BINARY="$1"

TMPDIR="${TEST_TMPDIR:-/tmp}"

# --- Test 1: TEST_SHARD_STATUS_FILE is created when sharding ---

SHARD_STATUS="$TMPDIR/shard_status"
rm -f "$SHARD_STATUS"

TEST_TOTAL_SHARDS=2 \
TEST_SHARD_INDEX=0 \
TEST_SHARD_STATUS_FILE="$SHARD_STATUS" \
"$TEST_BINARY"

if [ ! -f "$SHARD_STATUS" ]; then
    echo "FAIL: TEST_SHARD_STATUS_FILE was not created"
    exit 1
fi
echo "PASS: TEST_SHARD_STATUS_FILE was created"

# --- Test 2: XML_OUTPUT_FILE is created ---

XML_OUTPUT="$TMPDIR/test_output.xml"
rm -f "$XML_OUTPUT"

XML_OUTPUT_FILE="$XML_OUTPUT" \
"$TEST_BINARY"

if [ ! -f "$XML_OUTPUT" ]; then
    echo "FAIL: XML_OUTPUT_FILE was not created"
    exit 1
fi

if ! grep -q '<testsuites>' "$XML_OUTPUT"; then
    echo "FAIL: XML_OUTPUT_FILE does not contain valid JUnit XML"
    cat "$XML_OUTPUT"
    exit 1
fi

if ! grep -q '<testcase' "$XML_OUTPUT"; then
    echo "FAIL: XML_OUTPUT_FILE contains no test cases"
    cat "$XML_OUTPUT"
    exit 1
fi
echo "PASS: XML_OUTPUT_FILE was created with valid JUnit XML"

# --- Test 3: Both sharding + XML together ---

SHARD_STATUS2="$TMPDIR/shard_status2"
XML_OUTPUT2="$TMPDIR/test_output2.xml"
rm -f "$SHARD_STATUS2" "$XML_OUTPUT2"

TEST_TOTAL_SHARDS=2 \
TEST_SHARD_INDEX=1 \
TEST_SHARD_STATUS_FILE="$SHARD_STATUS2" \
XML_OUTPUT_FILE="$XML_OUTPUT2" \
"$TEST_BINARY"

if [ ! -f "$SHARD_STATUS2" ]; then
    echo "FAIL: TEST_SHARD_STATUS_FILE was not created (combined test)"
    exit 1
fi

if [ ! -f "$XML_OUTPUT2" ]; then
    echo "FAIL: XML_OUTPUT_FILE was not created (combined test)"
    exit 1
fi

if ! grep -q '<testsuites>' "$XML_OUTPUT2"; then
    echo "FAIL: XML_OUTPUT_FILE does not contain valid JUnit XML (combined test)"
    cat "$XML_OUTPUT2"
    exit 1
fi
echo "PASS: Combined sharding + XML works"

echo "All tests passed."
