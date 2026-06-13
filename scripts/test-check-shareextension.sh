#!/usr/bin/env bash
# Tests for scripts/check-shareextension-in-release.sh.

set -uo pipefail

SCRIPT="scripts/check-shareextension-in-release.sh"
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

make_project_with_shareextension() {
    local path="$1"
    cat > "$path" << 'PBXEOF'
// !$*UTF8*$!
{
    objects = {
        ABCDEF01234567890000 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                ABCDEF01234567891111 /* ShareExtension.appex in Embed Foundation Extensions */,
                ABCDEF01234567892222 /* FinderSyncExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
    };
}
PBXEOF
}

make_project_without_shareextension() {
    local path="$1"
    cat > "$path" << 'PBXEOF'
// !$*UTF8*$!
{
    objects = {
        ABCDEF01234567890000 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                ABCDEF01234567892222 /* FinderSyncExtension.appex in Embed Foundation Extensions */,
                ABCDEF01234567893333 /* QuickLookExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
    };
}
PBXEOF
}

PROJECT_INCLUDED="$TMPDIR_ROOT/included.pbxproj"
PROJECT_MISSING="$TMPDIR_ROOT/missing.pbxproj"
make_project_with_shareextension "$PROJECT_INCLUDED"
make_project_without_shareextension "$PROJECT_MISSING"

echo "=== Configuration Gating ==="
assert_exits_zero \
    "Debug configuration is skipped regardless of project content" \
    bash -c "CONFIGURATION=Debug bash '$SCRIPT' '$PROJECT_MISSING' >/dev/null 2>&1"

echo ""
echo "=== Project File Checks ==="
assert_exits_zero \
    "Release project with ShareExtension.appex embedded passes" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_INCLUDED' >/dev/null 2>&1"

assert_exits_nonzero \
    "Release project without ShareExtension.appex embedded fails" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_MISSING' >/dev/null 2>&1"

assert_exits_nonzero \
    "Non-existent project file causes non-zero exit" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$TMPDIR_ROOT/does-not-exist.pbxproj' >/dev/null 2>&1"

echo ""
echo "=== App Bundle Checks ==="
BUNDLE_INCLUDED="$TMPDIR_ROOT/MacPGP-included.app"
BUNDLE_MISSING="$TMPDIR_ROOT/MacPGP-missing.app"
mkdir -p "$BUNDLE_INCLUDED/Contents/PlugIns/ShareExtension.appex"
mkdir -p "$BUNDLE_INCLUDED/Contents/PlugIns/FinderSyncExtension.appex"
mkdir -p "$BUNDLE_MISSING/Contents/PlugIns/FinderSyncExtension.appex"

assert_exits_zero \
    "App bundle with ShareExtension.appex passes bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_INCLUDED' '$BUNDLE_INCLUDED' >/dev/null 2>&1"

assert_exits_nonzero \
    "App bundle without ShareExtension.appex fails bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_INCLUDED' '$BUNDLE_MISSING' >/dev/null 2>&1"

assert_exits_nonzero \
    "Missing app bundle path fails bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_INCLUDED' '$TMPDIR_ROOT/no-such.app' >/dev/null 2>&1"

echo ""
echo "=== Output Messages ==="
PASS_MSG=$(CONFIGURATION=Release bash "$SCRIPT" "$PROJECT_INCLUDED" 2>&1 || true)
if echo "$PASS_MSG" | grep -q "guardrail passed"; then
    pass "Passing run outputs 'guardrail passed' message"
else
    fail "Passing run should output 'guardrail passed' but got: $PASS_MSG"
fi

FAIL_MSG=$(CONFIGURATION=Release bash "$SCRIPT" "$PROJECT_MISSING" 2>&1 || true)
if echo "$FAIL_MSG" | grep -q "must be embedded"; then
    pass "Failing run explains ShareExtension must be embedded"
else
    fail "Failing run should explain embedding requirement but got: $FAIL_MSG"
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
