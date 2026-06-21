#!/usr/bin/env bash
# Validates scripts/check-archive-entitlements.sh against fixture entitlement
# plists (no real signed archive required) — issue #150.

set -uo pipefail

script="scripts/check-archive-entitlements.sh"
manifest="scripts/entitlements-manifest.json"
failures=0

emit_plists() {
  # $1 = output dir; remaining = "Target:key1,key2,..." specs (array/bool values
  # are synthesized as appropriate). Pass "skip:Target" to omit a target.
  local dir="$1"; shift
  mkdir -p "$dir"
  python3 - "$dir" "$@" <<'PY'
import sys, plistlib, os
out = sys.argv[1]
for spec in sys.argv[2:]:
    name, _, keycsv = spec.partition(":")
    ent = {}
    for key in [k for k in keycsv.split(",") if k]:
        if key == "com.apple.security.application-groups":
            ent[key] = ["group.com.macpgp.shared"]
        elif key == "keychain-access-groups":
            ent[key] = ["ABCDE12345.thalesmms.MacPGP"]
        else:
            ent[key] = True
    with open(os.path.join(out, f"{name}.plist"), "wb") as fh:
        plistlib.dump(ent, fh)
PY
}

# Capability key shorthands.
SBX="com.apple.security.app-sandbox"
GRP="com.apple.security.application-groups"
FILES="com.apple.security.files.user-selected.read-write"
NET="com.apple.security.network.client"
KC="keychain-access-groups"
GTA="com.apple.security.get-task-allow"

good_specs=(
  "MacPGP:$SBX,$GRP,$FILES,$NET,$KC"
  "ShareExtension:$SBX,$GRP,$FILES"
  "QuickLookExtension:$SBX,$GRP"
  "FinderSyncExtension:$SBX,$GRP"
  "ThumbnailExtension:$SBX"
)

run_case() {
  local name="$1" expected="$2"; shift 2
  local dir; dir="$(mktemp -d)"
  emit_plists "$dir" "$@"
  bash "$script" --plist-dir "$dir" --manifest "$manifest" >/dev/null 2>&1
  local rc=$?
  rm -rf "$dir"
  if [[ "$rc" -eq "$expected" ]]; then
    echo "ok: $name (exit $rc)"
  else
    echo "FAIL: $name (exit $rc, expected $expected)"
    failures=$((failures + 1))
  fi
}

# 1. Canonical set passes.
run_case "canonical-passes" 0 "${good_specs[@]}"

# 2. Drift: Thumbnail with an unexpected App Group fails.
run_case "thumbnail-appgroup-drift-fails" 1 \
  "MacPGP:$SBX,$GRP,$FILES,$NET,$KC" \
  "ShareExtension:$SBX,$GRP,$FILES" \
  "QuickLookExtension:$SBX,$GRP" \
  "FinderSyncExtension:$SBX,$GRP" \
  "ThumbnailExtension:$SBX,$GRP"

# 3. Missing keychain group on the app fails.
run_case "app-missing-keychain-fails" 1 \
  "MacPGP:$SBX,$GRP,$FILES,$NET" \
  "ShareExtension:$SBX,$GRP,$FILES" \
  "QuickLookExtension:$SBX,$GRP" \
  "FinderSyncExtension:$SBX,$GRP" \
  "ThumbnailExtension:$SBX"

# 4. get-task-allow present anywhere fails.
run_case "get-task-allow-fails" 1 \
  "MacPGP:$SBX,$GRP,$FILES,$NET,$KC,$GTA" \
  "ShareExtension:$SBX,$GRP,$FILES" \
  "QuickLookExtension:$SBX,$GRP" \
  "FinderSyncExtension:$SBX,$GRP" \
  "ThumbnailExtension:$SBX"

# 5. Unexpected embedded extension fails.
run_case "unexpected-extension-fails" 1 \
  "${good_specs[@]}" \
  "RogueExtension:$SBX"

# 6. Missing extension fails.
run_case "missing-extension-fails" 1 \
  "MacPGP:$SBX,$GRP,$FILES,$NET,$KC" \
  "ShareExtension:$SBX,$GRP,$FILES" \
  "QuickLookExtension:$SBX,$GRP" \
  "FinderSyncExtension:$SBX,$GRP"

if [[ "$failures" -ne 0 ]]; then
  echo "$failures test case(s) failed."
  exit 1
fi
echo "All archive-entitlement check test cases passed."
