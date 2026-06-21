#!/usr/bin/env bash
# Tests for scripts/check-screenshots.sh.

set -uo pipefail

SCRIPT="scripts/check-screenshots.sh"
PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL  $1"; }

assert_exits_zero() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d (expected 0)"; fi
}
assert_exits_nonzero() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$d (expected non-zero)"; else pass "$d"; fi
}

echo "Testing: $SCRIPT"; echo ""
[[ -f "$SCRIPT" ]] || { echo "FATAL: Script not found: $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_png() {
    python3 - "$1" "$2" "$3" <<'PY'
import zlib, struct, sys
w, h, path = int(sys.argv[2]), int(sys.argv[3]), sys.argv[1]
def chunk(t, d):
    c = t + d
    return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
sig = b"\x89PNG\r\n\x1a\n"
ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)
raw = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
open(path, "wb").write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
}

write_manifest() {
    local dir="$1" provenance="$2"
    mkdir -p "$dir/light" "$dir/dark"
    cat > "$dir/manifest.json" <<EOF
{
  "schemaVersion": 1,
  "target": { "requiredDimensions": "8x8", "fileType": "png", "appearances": ["light","dark"], "namingConvention": "x" },
  "build": { "appVersion": "$provenance", "gitCommit": "$provenance", "capturedAt": "$provenance" },
  "screenshots": [
    { "sequence": 1, "subject": "a", "optional": false, "featureClaim": "A", "files": { "light": "light/01-a-light.png", "dark": "dark/01-a-dark.png" } }
  ]
}
EOF
}

# --- Valid captured set ---
GOOD="$TMP/good"
write_manifest "$GOOD" "1.0"
make_png "$GOOD/light/01-a-light.png" 8 8
make_png "$GOOD/dark/01-a-dark.png" 8 8

echo "=== Valid set ==="
assert_exits_zero "Complete, correctly sized, provenanced set passes --require-complete" \
    bash -c "bash '$SCRIPT' '$GOOD' --require-complete >/dev/null 2>&1"

echo ""
echo "=== Wrong dimensions ==="
BAD_DIM="$TMP/baddim"; write_manifest "$BAD_DIM" "1.0"
make_png "$BAD_DIM/light/01-a-light.png" 16 16
make_png "$BAD_DIM/dark/01-a-dark.png" 8 8
assert_exits_nonzero "Wrong dimensions fail" \
    bash -c "bash '$SCRIPT' '$BAD_DIM' >/dev/null 2>&1"

echo ""
echo "=== Placeholder / empty file ==="
PLACE="$TMP/place"; write_manifest "$PLACE" "1.0"
: > "$PLACE/light/01-a-light.png"
make_png "$PLACE/dark/01-a-dark.png" 8 8
assert_exits_nonzero "Empty placeholder PNG fails" \
    bash -c "bash '$SCRIPT' '$PLACE' >/dev/null 2>&1"

echo ""
echo "=== Stray file not in manifest ==="
STRAY="$TMP/stray"; write_manifest "$STRAY" "1.0"
make_png "$STRAY/light/01-a-light.png" 8 8
make_png "$STRAY/dark/01-a-dark.png" 8 8
make_png "$STRAY/light/99-unexpected-light.png" 8 8
assert_exits_nonzero "Stray screenshot not in manifest fails" \
    bash -c "bash '$SCRIPT' '$STRAY' >/dev/null 2>&1"

echo ""
echo "=== Incomplete set ==="
INCOMPLETE="$TMP/incomplete"; write_manifest "$INCOMPLETE" "1.0"
make_png "$INCOMPLETE/light/01-a-light.png" 8 8
# dark capture missing
assert_exits_zero "Incomplete set passes in dev mode" \
    bash -c "bash '$SCRIPT' '$INCOMPLETE' >/dev/null 2>&1"
assert_exits_nonzero "Incomplete set fails with --require-complete" \
    bash -c "bash '$SCRIPT' '$INCOMPLETE' --require-complete >/dev/null 2>&1"

echo ""
echo "=== TBD provenance ==="
TBD="$TMP/tbd"; write_manifest "$TBD" "TBD-at-capture"
make_png "$TBD/light/01-a-light.png" 8 8
make_png "$TBD/dark/01-a-dark.png" 8 8
assert_exits_nonzero "TBD provenance fails --require-complete" \
    bash -c "bash '$SCRIPT' '$TBD' --require-complete >/dev/null 2>&1"

echo ""
echo "=== Missing manifest ==="
assert_exits_nonzero "Missing manifest fails" \
    bash -c "bash '$SCRIPT' '$TMP/nonexistent' >/dev/null 2>&1"

echo ""
echo "=== Real repository manifest (dev mode) ==="
if [[ -f "app-store-assets/screenshots/manifest.json" ]]; then
    assert_exits_zero "Repository manifest validates in dev mode" \
        bash -c "bash '$SCRIPT' app-store-assets/screenshots >/dev/null 2>&1"
else
    echo "  SKIP  Repository manifest not present"
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
