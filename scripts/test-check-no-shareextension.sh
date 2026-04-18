#!/usr/bin/env bash
# test-check-no-shareextension.sh
#
# Tests for scripts/check-no-shareextension-in-release.sh.
#
# The manual testing guide (docs/MANUAL-TESTING-GUIDE.md) references this
# script in EXT-SHARE-1.2 and requires that it:
#   - passes for Release when ShareExtension.appex is not embedded
#   - fails if ShareExtension.appex IS embedded
#   - skips for non-Release configurations
#   - fails when the project file does not exist
#
# Usage:
#   bash scripts/test-check-no-shareextension.sh
#
# Exit code 0 when all tests pass; 1 otherwise.

set -uo pipefail

SCRIPT="scripts/check-no-shareextension-in-release.sh"
PASS=0
FAIL=0
FAILURES=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Guard: script must exist and be executable
# ---------------------------------------------------------------------------

echo "Testing: $SCRIPT"
echo ""

if [[ ! -f "$SCRIPT" ]]; then
    echo "FATAL: Script not found: $SCRIPT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Fixtures: temporary project files
# ---------------------------------------------------------------------------

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

make_project_with_shareextension() {
    # Minimal project.pbxproj that embeds ShareExtension.appex in the
    # "Embed Foundation Extensions" build phase - the pattern the script looks for.
    local path="$1"
    cat > "$path" << 'PBXEOF'
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 77;
    objects = {
        ABCDEF01234567890000 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            buildActionMask = 2147483647;
            dstPath = "";
            dstSubfolderSpec = 13;
            files = (
                ABCDEF01234567891111 /* ShareExtension.appex in Embed Foundation Extensions */,
                ABCDEF01234567892222 /* FinderSyncExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
            runOnlyForDeploymentPostprocessing = 0;
        };
    };
}
PBXEOF
}

make_project_without_shareextension() {
    # Minimal project.pbxproj that embeds other extensions but NOT ShareExtension.appex.
    local path="$1"
    cat > "$path" << 'PBXEOF'
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 77;
    objects = {
        ABCDEF01234567890000 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            buildActionMask = 2147483647;
            dstPath = "";
            dstSubfolderSpec = 13;
            files = (
                ABCDEF01234567892222 /* FinderSyncExtension.appex in Embed Foundation Extensions */,
                ABCDEF01234567893333 /* QuickLookExtension.appex in Embed Foundation Extensions */,
                ABCDEF01234567894444 /* ThumbnailExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
            runOnlyForDeploymentPostprocessing = 0;
        };
    };
}
PBXEOF
}

make_empty_project() {
    local path="$1"
    cat > "$path" << 'PBXEOF'
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {};
    objectVersion = 77;
    objects = {};
}
PBXEOF
}

# ---------------------------------------------------------------------------
# Test 1: Non-Release configuration is skipped (exits 0)
# ---------------------------------------------------------------------------

echo "=== Configuration Gating ==="

PROJECT_CLEAN="$TMPDIR_ROOT/clean.pbxproj"
PROJECT_DIRTY="$TMPDIR_ROOT/dirty.pbxproj"
make_project_without_shareextension "$PROJECT_CLEAN"
make_project_with_shareextension "$PROJECT_DIRTY"

assert_exits_zero \
    "Debug configuration is skipped regardless of project content" \
    bash -c "CONFIGURATION=Debug bash '$SCRIPT' '$PROJECT_DIRTY' >/dev/null 2>&1"

assert_exits_zero \
    "Unset CONFIGURATION defaults to Release and is not skipped (clean project passes)" \
    env -u CONFIGURATION bash "$SCRIPT" "$PROJECT_CLEAN"

# ---------------------------------------------------------------------------
# Test 2: Missing project file causes non-zero exit
# ---------------------------------------------------------------------------

echo ""
echo "=== Missing Project File ==="

assert_exits_nonzero \
    "Non-existent project file causes non-zero exit" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$TMPDIR_ROOT/does-not-exist.pbxproj' >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# Test 3: Clean project (no ShareExtension embedded) passes
# ---------------------------------------------------------------------------

echo ""
echo "=== Clean Project (No ShareExtension) ==="

assert_exits_zero \
    "Release build without ShareExtension.appex passes" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' >/dev/null 2>&1"

# Empty project has no embed phase at all, so ShareExtension cannot be
# found there - script should pass (exit 0 from the awk END block).
EMPTY_PROJECT="$TMPDIR_ROOT/empty.pbxproj"
make_empty_project "$EMPTY_PROJECT"
assert_exits_zero \
    "Empty project file with no embed phase passes" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$EMPTY_PROJECT' >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# Test 4: Dirty project (ShareExtension embedded) fails
# ---------------------------------------------------------------------------

echo ""
echo "=== Dirty Project (ShareExtension Embedded) ==="

assert_exits_nonzero \
    "Release build with ShareExtension.appex embedded fails" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_DIRTY' >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# Test 5: App bundle checks
# ---------------------------------------------------------------------------

echo ""
echo "=== App Bundle Checks ==="

# Build a fake app bundle without ShareExtension.appex
BUNDLE_CLEAN="$TMPDIR_ROOT/MacPGP-clean.app"
mkdir -p "$BUNDLE_CLEAN/Contents/PlugIns/FinderSyncExtension.appex"
mkdir -p "$BUNDLE_CLEAN/Contents/PlugIns/QuickLookExtension.appex"
mkdir -p "$BUNDLE_CLEAN/Contents/PlugIns/ThumbnailExtension.appex"

assert_exits_zero \
    "App bundle without ShareExtension.appex passes bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' '$BUNDLE_CLEAN' >/dev/null 2>&1"

assert_exits_zero \
    "APP_BUNDLE without ShareExtension.appex passes bundle check" \
    bash -c "APP_BUNDLE='$BUNDLE_CLEAN' CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' >/dev/null 2>&1"

# Build a fake app bundle WITH ShareExtension.appex
BUNDLE_DIRTY="$TMPDIR_ROOT/MacPGP-dirty.app"
mkdir -p "$BUNDLE_DIRTY/Contents/PlugIns/ShareExtension.appex"
mkdir -p "$BUNDLE_DIRTY/Contents/PlugIns/FinderSyncExtension.appex"

assert_exits_nonzero \
    "App bundle with ShareExtension.appex embedded fails bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' '$BUNDLE_DIRTY' >/dev/null 2>&1"

assert_exits_nonzero \
    "APP_BUNDLE with ShareExtension.appex embedded fails bundle check" \
    bash -c "APP_BUNDLE='$BUNDLE_DIRTY' CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' >/dev/null 2>&1"

assert_exits_zero \
    "APP_BUNDLE clean bundle takes precedence over dirty positional bundle" \
    bash -c "APP_BUNDLE='$BUNDLE_CLEAN' CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' '$BUNDLE_DIRTY' >/dev/null 2>&1"

assert_exits_nonzero \
    "APP_BUNDLE dirty bundle takes precedence over clean positional bundle" \
    bash -c "APP_BUNDLE='$BUNDLE_DIRTY' CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' '$BUNDLE_CLEAN' >/dev/null 2>&1"

# Passing an empty app bundle path (project-only check) still passes on clean project
assert_exits_zero \
    "Empty app_bundle argument does not trigger bundle check" \
    bash -c "CONFIGURATION=Release bash '$SCRIPT' '$PROJECT_CLEAN' '' >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# Test 6: Output messages
# ---------------------------------------------------------------------------

echo ""
echo "=== Output Messages ==="

PASS_MSG=$(CONFIGURATION=Release bash "$SCRIPT" "$PROJECT_CLEAN" 2>&1 || true)
if echo "$PASS_MSG" | grep -q "guardrail passed"; then
    pass "Passing run outputs 'guardrail passed' message"
else
    fail "Passing run should output 'guardrail passed' but got: $PASS_MSG"
fi

FAIL_MSG=$(CONFIGURATION=Release bash "$SCRIPT" "$PROJECT_DIRTY" 2>&1 || true)
if echo "$FAIL_MSG" | grep -q "ShareExtension.appex"; then
    pass "Failing run mentions ShareExtension.appex in output"
else
    fail "Failing run should mention ShareExtension.appex but got: $FAIL_MSG"
fi

SKIP_MSG=$(CONFIGURATION=Debug bash "$SCRIPT" "$PROJECT_DIRTY" 2>&1 || true)
if echo "$SKIP_MSG" | grep -q "Skipping"; then
    pass "Non-Release configuration outputs 'Skipping' message"
else
    fail "Non-Release configuration should output 'Skipping' but got: $SKIP_MSG"
fi

MISSING_MSG=$(CONFIGURATION=Release bash "$SCRIPT" "$TMPDIR_ROOT/no-such-file.pbxproj" 2>&1 || true)
if echo "$MISSING_MSG" | grep -qiE "not found|cannot check"; then
    pass "Missing project file outputs a clear error message"
else
    fail "Missing project file should output a clear error but got: $MISSING_MSG"
fi

# ---------------------------------------------------------------------------
# Test 7: Edge cases in project file content
# ---------------------------------------------------------------------------

echo ""
echo "=== Edge Cases in Project File Content ==="

# ShareExtension reference outside the Embed Foundation Extensions block
# should NOT trigger a false positive.
EDGE_OUTSIDE="$TMPDIR_ROOT/edge-outside.pbxproj"
cat > "$EDGE_OUTSIDE" << 'PBXEOF'
// !$*UTF8*$!
{
    objects = {
        /* ShareExtension.appex is referenced here but NOT inside the embed phase */
        SOMEREF /* ShareExtension.appex */ = {
            isa = PBXFileReference;
            path = ShareExtension.appex;
        };
        EMBED01 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                /* no ShareExtension here */
                AABBCC /* FinderSyncExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
    };
}
PBXEOF

if CONFIGURATION=Release bash "$SCRIPT" "$EDGE_OUTSIDE" >/dev/null 2>&1; then
    pass "ShareExtension reference outside embed phase does not false-positive"
else
    fail "ShareExtension reference outside embed phase should pass but failed"
fi

# ShareExtension inside the Embed Foundation Extensions block triggers failure.
EDGE_INSIDE="$TMPDIR_ROOT/edge-inside.pbxproj"
cat > "$EDGE_INSIDE" << 'PBXEOF'
// !$*UTF8*$!
{
    objects = {
        EMBED01 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                AABBCC /* ShareExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
    };
}
PBXEOF

if ! CONFIGURATION=Release bash "$SCRIPT" "$EDGE_INSIDE" >/dev/null 2>&1; then
    pass "ShareExtension inside embed phase triggers failure"
else
    fail "ShareExtension inside embed phase should fail but passed"
fi

# Multiple embed phases: ShareExtension only in the second phase still triggers.
EDGE_MULTI="$TMPDIR_ROOT/edge-multi.pbxproj"
cat > "$EDGE_MULTI" << 'PBXEOF'
// !$*UTF8*$!
{
    objects = {
        EMBED01 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                AABBCC /* FinderSyncExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
        EMBED02 /* Embed Foundation Extensions */ = {
            isa = PBXCopyFilesBuildPhase;
            files = (
                DDEEFF /* ShareExtension.appex in Embed Foundation Extensions */,
            );
            name = "Embed Foundation Extensions";
        };
    };
}
PBXEOF

if ! CONFIGURATION=Release bash "$SCRIPT" "$EDGE_MULTI" >/dev/null 2>&1; then
    pass "ShareExtension in second embed phase triggers failure"
else
    fail "ShareExtension in second embed phase should fail but passed"
fi

# Case: the file only has a ShareExtension appex directory in the bundle but
# the project file is clean - bundle check catches it independently.
BUNDLE_ONLY_DIRTY="$TMPDIR_ROOT/bundle-only-dirty.app"
mkdir -p "$BUNDLE_ONLY_DIRTY/Contents/PlugIns/ShareExtension.appex"
if ! CONFIGURATION=Release bash "$SCRIPT" "$PROJECT_CLEAN" "$BUNDLE_ONLY_DIRTY" >/dev/null 2>&1; then
    pass "ShareExtension.appex in bundle directory fails even when project file is clean"
else
    fail "ShareExtension.appex in bundle directory should fail but passed"
fi

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------

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
