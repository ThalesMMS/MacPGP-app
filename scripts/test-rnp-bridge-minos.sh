#!/usr/bin/env bash
# Tests for Vendor/RNPBridge/scripts/check-rnp-bridge-minos.sh.

set -uo pipefail

SCRIPT="Vendor/RNPBridge/scripts/check-rnp-bridge-minos.sh"
BRIDGE_LIB="Vendor/RNPBridge/RNPBridge.xcframework/macos-arm64/libRNPBridge.a"
PASS=0
FAIL=0
FAILURES=()

pass() {
    PASS=$((PASS + 1))
    echo "  PASS  $1"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    echo "  FAIL  $1"
}

assert_exits_zero() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description (expected exit 0, got non-zero)"
    fi
}

assert_exits_nonzero() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$description (expected non-zero exit, got 0)"
    else
        pass "$description"
    fi
}

echo "Testing: $SCRIPT"
echo ""

if [[ ! -f "$SCRIPT" ]]; then
    echo "FATAL: Script not found: $SCRIPT"
    exit 1
fi

echo "=== Bridge minos checks ==="
assert_exits_zero \
    "Vendored bridge minos is compatible with macOS 26.2" \
    bash "$SCRIPT" 26.2 "$BRIDGE_LIB"

assert_exits_nonzero \
    "Vendored bridge minos is rejected for macOS 25.0" \
    bash "$SCRIPT" 25.0 "$BRIDGE_LIB"

assert_exits_nonzero \
    "Missing bridge archive causes non-zero exit" \
    bash "$SCRIPT" 26.2 "Vendor/RNPBridge/RNPBridge.xcframework/macos-arm64/missing.a"

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "All tests passed."
exit 0
