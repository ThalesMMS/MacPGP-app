#!/usr/bin/env bash
# Tests for scripts/check-localization-parity.sh.

set -uo pipefail

SCRIPT="scripts/check-localization-parity.sh"
PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL  $1"; }

assert_exits_zero() {
    local description="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$description"; else fail "$description (expected 0, got non-zero)"; fi
}
assert_exits_nonzero() {
    local description="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$description (expected non-zero, got 0)"; else pass "$description"; fi
}

echo "Testing: $SCRIPT"; echo ""
[[ -f "$SCRIPT" ]] || { echo "FATAL: Script not found: $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

write_strings() {
    local locale="$1"; shift
    mkdir -p "$TMP/res/$locale.lproj"
    printf '%b' "$1" > "$TMP/res/$locale.lproj/Localizable.strings"
}

EN_BODY='/* base */\n"a" = "A";\n"b" = "B";\n"c" = "C";\n'

echo "=== Matching locales ==="
write_strings en "$EN_BODY"
write_strings pt '"a" = "A1";\n"b" = "B1";\n"c" = "C1";\n'
assert_exits_zero "Locales with identical key sets pass" \
    bash -c "bash '$SCRIPT' '$TMP/res' en >/dev/null 2>&1"

echo ""
echo "=== Missing key ==="
rm -rf "$TMP/res"; write_strings en "$EN_BODY"
write_strings pt '"a" = "A1";\n"b" = "B1";\n'
assert_exits_nonzero "A locale missing a base key fails" \
    bash -c "bash '$SCRIPT' '$TMP/res' en >/dev/null 2>&1"

echo ""
echo "=== Extra key ==="
rm -rf "$TMP/res"; write_strings en "$EN_BODY"
write_strings pt '"a" = "A1";\n"b" = "B1";\n"c" = "C1";\n"d" = "D1";\n'
assert_exits_nonzero "A locale with an extra key fails" \
    bash -c "bash '$SCRIPT' '$TMP/res' en >/dev/null 2>&1"

echo ""
echo "=== Duplicate key ==="
rm -rf "$TMP/res"; write_strings en "$EN_BODY"
write_strings pt '"a" = "A1";\n"b" = "B1";\n"c" = "C1";\n"c" = "C2";\n'
assert_exits_nonzero "A locale with a duplicate key fails" \
    bash -c "bash '$SCRIPT' '$TMP/res' en >/dev/null 2>&1"

echo ""
echo "=== Malformed syntax ==="
rm -rf "$TMP/res"; write_strings en "$EN_BODY"
write_strings pt '"a" = "A1"\n"b" = "B1";\n'
assert_exits_nonzero "A locale with malformed syntax fails" \
    bash -c "bash '$SCRIPT' '$TMP/res' en >/dev/null 2>&1"

echo ""
echo "=== Real repository localizations ==="
if [[ -d "MacPGP/MacPGP/Resources/en.lproj" ]]; then
    assert_exits_zero "Repository localizations are at parity" \
        bash -c "bash '$SCRIPT' MacPGP/MacPGP/Resources en >/dev/null 2>&1"
else
    echo "  SKIP  Repository resources not present"
fi

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"
if [[ "$FAIL" -gt 0 ]]; then
    echo ""; echo "Failed tests:"; for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
fi
echo "All tests passed."
exit 0
