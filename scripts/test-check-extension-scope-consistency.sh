#!/usr/bin/env bash
# Tests for scripts/check-extension-scope-consistency.sh.

set -uo pipefail

SCRIPT="scripts/check-extension-scope-consistency.sh"
REAL_PBXPROJ="MacPGP/MacPGP.xcodeproj/project.pbxproj"
REAL_SCOPE="docs/V1_SCOPE.md"
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

# Build a project file whose Embed Foundation Extensions phase contains the
# given extension base names.
make_pbxproj() {
    local path="$1"
    shift
    {
        echo "// !\$*UTF8*\$!"
        echo "{"
        echo "    objects = {"
        echo "        AAAA /* Embed Foundation Extensions */ = {"
        echo "            isa = PBXCopyFilesBuildPhase;"
        echo "            files = ("
        local ext
        for ext in "$@"; do
            echo "                BBBB /* ${ext}.appex in Embed Foundation Extensions */,"
        done
        echo "            );"
        echo "            name = \"Embed Foundation Extensions\";"
        echo "        };"
        echo "    };"
        echo "}"
    } > "$path"
}

# Build a V1_SCOPE-like doc with a "## Shipped Extensions" section listing the
# given extension base names as "### <name>" headings.
make_scope() {
    local path="$1"
    shift
    {
        echo "# Scope"
        echo ""
        echo "## Shipped Features"
        echo ""
        echo "### Encryption"
        echo ""
        echo "- Encrypt."
        echo ""
        echo "## Shipped Extensions"
        echo ""
        local ext
        for ext in "$@"; do
            echo "### ${ext}"
            echo ""
            echo "- Ships in v1.0."
            echo ""
        done
        echo "## Postponed to Future Release"
        echo ""
        echo "### Web of Trust"
        echo ""
        echo "- Status: postponed."
    } > "$path"
}

ALL4=(FinderSyncExtension QuickLookExtension ThumbnailExtension ShareExtension)
THREE=(FinderSyncExtension QuickLookExtension ThumbnailExtension)

PBX_ALL4="$TMPDIR_ROOT/all4.pbxproj"
SCOPE_ALL4="$TMPDIR_ROOT/all4.md"
SCOPE_THREE="$TMPDIR_ROOT/three.md"
SCOPE_EXTRA="$TMPDIR_ROOT/extra.md"
make_pbxproj "$PBX_ALL4" "${ALL4[@]}"
make_scope "$SCOPE_ALL4" "${ALL4[@]}"
make_scope "$SCOPE_THREE" "${THREE[@]}"
make_scope "$SCOPE_EXTRA" "${ALL4[@]}" ServicesExtension

echo "=== Matching sets ==="
assert_exits_zero \
    "Embedded set matches documented set (4 extensions)" \
    bash -c "bash '$SCRIPT' '$PBX_ALL4' '$SCOPE_ALL4' >/dev/null 2>&1"

echo ""
echo "=== Divergence detection (the issue #124 bug) ==="
assert_exits_nonzero \
    "Embedded ShareExtension but docs omit it -> fails" \
    bash -c "bash '$SCRIPT' '$PBX_ALL4' '$SCOPE_THREE' >/dev/null 2>&1"

assert_exits_nonzero \
    "Docs list an extension that is not embedded -> fails" \
    bash -c "bash '$SCRIPT' '$PBX_ALL4' '$SCOPE_EXTRA' >/dev/null 2>&1"

echo ""
echo "=== Missing input ==="
assert_exits_nonzero \
    "Missing project file -> non-zero exit" \
    bash -c "bash '$SCRIPT' '$TMPDIR_ROOT/none.pbxproj' '$SCOPE_ALL4' >/dev/null 2>&1"

assert_exits_nonzero \
    "Missing scope file -> non-zero exit" \
    bash -c "bash '$SCRIPT' '$PBX_ALL4' '$TMPDIR_ROOT/none.md' >/dev/null 2>&1"

echo ""
echo "=== Real repository state ==="
if [[ -f "$REAL_PBXPROJ" && -f "$REAL_SCOPE" ]]; then
    assert_exits_zero \
        "Repository project file and docs/V1_SCOPE.md are consistent" \
        bash -c "bash '$SCRIPT' '$REAL_PBXPROJ' '$REAL_SCOPE' >/dev/null 2>&1"
else
    echo "  SKIP  Repository project file or scope document not present"
fi

echo ""
echo "=== Output Messages ==="
PASS_MSG=$(bash "$SCRIPT" "$PBX_ALL4" "$SCOPE_ALL4" 2>&1 || true)
if echo "$PASS_MSG" | grep -q "consistency check passed"; then
    pass "Passing run outputs 'consistency check passed'"
else
    fail "Passing run should output success message but got: $PASS_MSG"
fi

FAIL_MSG=$(bash "$SCRIPT" "$PBX_ALL4" "$SCOPE_THREE" 2>&1 || true)
if echo "$FAIL_MSG" | grep -q "diverges from the release target configuration"; then
    pass "Failing run explains the divergence"
else
    fail "Failing run should explain divergence but got: $FAIL_MSG"
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
