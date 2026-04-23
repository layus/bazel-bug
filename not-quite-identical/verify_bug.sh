#!/bin/bash
# Verify that the Bazel duplicate paths bug still reproduces.
# Runs bazel clean --expunge, builds //:root_target, asserts the
# "Duplicate paths" error, and asserts an empty-diff config pair exists.

set -uo pipefail

BAZEL="./bazelisk-linux-amd64"
TARGET="//:root_target"
LEAF="//:proto_definitions"

echo "=== Step 0: Clean expunge for fresh state ==="
$BAZEL clean --expunge 2>&1 | tail -2

echo "=== Step 1: Build and check for duplicate paths bug ==="
BUILD_OUTPUT=$($BAZEL build --keep_going $TARGET 2>&1 || true)

if echo "$BUILD_OUTPUT" | grep -q "Duplicate paths are only allowed for distinct shared artifacts"; then
    echo "PASS: Bug reproduces (Duplicate paths error)"
else
    echo "FAIL: Bug NOT reproduced!"
    echo "$BUILD_OUTPUT" | grep -E "ERROR|FATAL" | head -10
    exit 1
fi

# Extract the two colliding config directory names from the error
COLLIDE1=$(echo "$BUILD_OUTPUT" | grep -oP 'bazel-out/\K[^/]+(?=/bin\])' | head -1)
COLLIDE2=$(echo "$BUILD_OUTPUT" | grep -oP 'bazel-out/\K[^/]+(?=/bin\])' | tail -1)
echo "  Colliding dir 1: $COLLIDE1"
echo "  Colliding dir 2: $COLLIDE2"

echo ""
echo "=== Step 2: Get configs for $LEAF via cquery ==="
# cquery populates the config database and lists all configs for the leaf target.
CQUERY_OUTPUT=$($BAZEL cquery "$LEAF" --universe_scope="$TARGET" 2>&1)
CONFIGS=($(echo "$CQUERY_OUTPUT" | grep "^$LEAF" | grep -oP '\(\K[0-9a-f]+(?=\))'))

echo "  Found ${#CONFIGS[@]} configs: ${CONFIGS[*]}"

if [ "${#CONFIGS[@]}" -lt 2 ]; then
    echo "FAIL: Need at least 2 configs for $LEAF, got ${#CONFIGS[@]}"
    exit 1
fi

echo ""
echo "=== Step 3: Find the empty-diff config pair ==="
FOUND_EMPTY=false
EMPTY_A=""
EMPTY_B=""

for ((i=0; i<${#CONFIGS[@]}; i++)); do
    for ((j=i+1; j<${#CONFIGS[@]}; j++)); do
        A="${CONFIGS[$i]}"
        B="${CONFIGS[$j]}"
        DIFF_OUTPUT=$($BAZEL config "$A" "$B" 2>&1 || true)
        DIFF_LINES=$(echo "$DIFF_OUTPUT" | grep -v "^INFO\|^$\|^WARNING\|^Loading\|^Analyzing\|^Displaying diff")

        if [ -z "$DIFF_LINES" ]; then
            echo "  EMPTY diff: $A vs $B"
            FOUND_EMPTY=true
            EMPTY_A="$A"
            EMPTY_B="$B"
        else
            DIFF_COUNT=$(echo "$DIFF_LINES" | grep -c ":" || true)
            echo "  $A vs $B: $DIFF_COUNT flag(s) differ"
        fi
    done
done

echo ""
echo "=== Step 4: Assert empty diff exists ==="
if $FOUND_EMPTY; then
    echo "PASS: Found empty-diff config pair: $EMPTY_A vs $EMPTY_B"
    echo "  These configs have identical flag values but different ST hashes."
else
    echo "FAIL: No empty-diff config pair found among ${#CONFIGS[@]} configs."
    echo "  All pairs had non-empty diffs. The core bug condition is not met."
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "  Bug reproduces:    YES (Duplicate paths error)"
echo "  Colliding dirs:    $COLLIDE1 vs $COLLIDE2"
echo "  Empty-diff pair:   $EMPTY_A vs $EMPTY_B"
