#!/usr/bin/env bash
# Tests for scripts/check-bridge-architectures.sh.

set -uo pipefail

SCRIPT="scripts/check-bridge-architectures.sh"
REAL_XCFRAMEWORK="Vendor/RNPBridge/RNPBridge.xcframework"
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

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Build a minimal xcframework Info.plist with the requested architectures.
make_xcframework() {
    local dir="$1"
    shift
    local archs_xml=""
    local arch
    for arch in "$@"; do
        archs_xml+="                <string>${arch}</string>\n"
    done
    mkdir -p "$dir"
    printf '%b' "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>BinaryPath</key>
            <string>libRNPBridge.a</string>
            <key>LibraryIdentifier</key>
            <string>macos-$(IFS=-; echo "$*")</string>
            <key>LibraryPath</key>
            <string>libRNPBridge.a</string>
            <key>SupportedArchitectures</key>
            <array>
${archs_xml}            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
</dict>
</plist>
" > "$dir/Info.plist"
}

ARM64_FW="$TMPDIR_ROOT/arm64.xcframework"
UNIVERSAL_FW="$TMPDIR_ROOT/universal.xcframework"
make_xcframework "$ARM64_FW" arm64
make_xcframework "$UNIVERSAL_FW" arm64 x86_64

echo "=== Default expected architecture set (arm64) ==="
assert_exits_zero \
    "arm64-only xcframework passes with default expectation" \
    bash -c "bash '$SCRIPT' '$ARM64_FW' >/dev/null 2>&1"

assert_exits_nonzero \
    "universal (arm64+x86_64) xcframework fails with default arm64 expectation" \
    bash -c "bash '$SCRIPT' '$UNIVERSAL_FW' >/dev/null 2>&1"

echo ""
echo "=== Explicit expected architecture set ==="
assert_exits_zero \
    "universal xcframework passes when arm64 x86_64 is explicitly expected" \
    bash -c "EXPECTED_ARCHS='arm64 x86_64' bash '$SCRIPT' '$UNIVERSAL_FW' >/dev/null 2>&1"

assert_exits_nonzero \
    "arm64-only xcframework fails when arm64 x86_64 is expected" \
    bash -c "EXPECTED_ARCHS='arm64 x86_64' bash '$SCRIPT' '$ARM64_FW' >/dev/null 2>&1"

echo ""
echo "=== Missing input ==="
assert_exits_nonzero \
    "Non-existent xcframework causes non-zero exit" \
    bash -c "bash '$SCRIPT' '$TMPDIR_ROOT/does-not-exist.xcframework' >/dev/null 2>&1"

echo ""
echo "=== Real vendored bridge ==="
if [[ -f "$REAL_XCFRAMEWORK/Info.plist" ]]; then
    assert_exits_zero \
        "Vendored RNPBridge.xcframework is arm64-only" \
        bash -c "bash '$SCRIPT' '$REAL_XCFRAMEWORK' >/dev/null 2>&1"
else
    echo "  SKIP  Vendored RNPBridge.xcframework not present"
fi

echo ""
echo "=== Output Messages ==="
PASS_MSG=$(bash "$SCRIPT" "$ARM64_FW" 2>&1 || true)
if echo "$PASS_MSG" | grep -q "guardrail passed"; then
    pass "Passing run outputs 'guardrail passed' message"
else
    fail "Passing run should output 'guardrail passed' but got: $PASS_MSG"
fi

FAIL_MSG=$(bash "$SCRIPT" "$UNIVERSAL_FW" 2>&1 || true)
if echo "$FAIL_MSG" | grep -q "do not match the documented support matrix"; then
    pass "Failing run explains the architecture mismatch"
else
    fail "Failing run should explain the mismatch but got: $FAIL_MSG"
fi

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
