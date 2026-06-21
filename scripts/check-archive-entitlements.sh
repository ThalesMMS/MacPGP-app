#!/usr/bin/env bash
# Inspects a distribution .xcarchive (or a directory of pre-extracted entitlement
# plists) and fails when any shipped target's entitlements diverge from the
# canonical manifest (scripts/entitlements-manifest.json) — issue #150.
#
# For each target it enforces:
#   - the exact set of capability entitlements (com.apple.security.* and
#     keychain-access-groups) equals the manifest's `required` (missing OR extra
#     fails — this catches drift like an unexpected App Group on Thumbnail);
#   - every `forbidden` entitlement is absent (including
#     com.apple.security.get-task-allow on every target);
#   - the embedded plug-in inventory matches the expected extension set
#     (no missing or unexpected .appex).
#
# Usage:
#   scripts/check-archive-entitlements.sh --archive /path/to/MacPGP.xcarchive
#   scripts/check-archive-entitlements.sh --source       # check source .entitlements (CI)
#   scripts/check-archive-entitlements.sh --plist-dir /path/to/dir   # <Target>.plist each
#   [--manifest scripts/entitlements-manifest.json]
#
# --archive is authoritative for release (inspects the signed bundle). --source
# validates the checked-in .entitlements files against the manifest so source
# drift (e.g. an unexpected App Group on a sandbox-only extension) is caught in
# CI without a signed archive.

set -uo pipefail

manifest="scripts/entitlements-manifest.json"
archive=""
plist_dir=""
source_mode=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) archive="$2"; shift 2 ;;
    --plist-dir) plist_dir="$2"; shift 2 ;;
    --source) source_mode="1"; shift ;;
    --manifest) manifest="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$manifest" ]]; then
  echo "::error::Manifest not found: $manifest" >&2
  exit 2
fi
if [[ -z "$archive" && -z "$plist_dir" && -z "$source_mode" ]]; then
  echo "::error::Provide --archive <path>, --source, or --plist-dir <dir>" >&2
  exit 2
fi

work_dir=""
cleanup() { [[ -n "$work_dir" ]] && rm -rf "$work_dir"; }
trap cleanup EXIT

# --source: copy each target's checked-in .entitlements into a plist dir keyed by
# target name, then run the same comparison (the source tree always contains all
# expected targets, so the inventory check passes by construction).
source_path_for() {
  # bash 3.2 (macOS default) has no associative arrays; use a case mapping.
  case "$1" in
    MacPGP) echo "MacPGP/MacPGP/MacPGP.entitlements" ;;
    ShareExtension) echo "MacPGP/ShareExtension/ShareExtension.entitlements" ;;
    QuickLookExtension) echo "MacPGP/QuickLookExtension/QuickLookExtension.entitlements" ;;
    FinderSyncExtension) echo "MacPGP/FinderSyncExtension/FinderSyncExtension.entitlements" ;;
    ThumbnailExtension) echo "MacPGP/ThumbnailExtension/ThumbnailExtension.entitlements" ;;
    *) echo "" ;;
  esac
}

if [[ -n "$source_mode" ]]; then
  work_dir="$(mktemp -d)"
  plist_dir="$work_dir/plists"
  mkdir -p "$plist_dir"
  for name in MacPGP ShareExtension QuickLookExtension FinderSyncExtension ThumbnailExtension; do
    src="$(source_path_for "$name")"
    if [[ -z "$src" || ! -f "$src" ]]; then
      echo "::error::Source entitlements not found: $src" >&2
      exit 1
    fi
    cp "$src" "$plist_dir/$name.plist"
  done
fi

# When given an archive, extract each target's entitlements to a temp plist dir
# and record which .appex bundles are actually embedded.
embedded_inventory=""
if [[ -n "$archive" ]]; then
  if [[ ! -d "$archive" ]]; then
    echo "::error::Archive not found: $archive" >&2
    exit 2
  fi
  work_dir="$(mktemp -d)"
  plist_dir="$work_dir/plists"
  mkdir -p "$plist_dir"

  app="$archive/Products/Applications/MacPGP.app"
  if [[ ! -d "$app" ]]; then
    echo "::error::MacPGP.app not found in archive: $app" >&2
    exit 1
  fi
  codesign -d --entitlements - --xml "$app" > "$plist_dir/MacPGP.plist" 2>/dev/null || {
    echo "::error::Failed to read entitlements from $app" >&2; exit 1; }

  if [[ -d "$app/Contents/PlugIns" ]]; then
    for appex in "$app/Contents/PlugIns"/*.appex; do
      [[ -e "$appex" ]] || continue
      base="$(basename "$appex" .appex)"
      embedded_inventory+="$base"$'\n'
      codesign -d --entitlements - --xml "$appex" > "$plist_dir/$base.plist" 2>/dev/null || {
        echo "::error::Failed to read entitlements from $appex" >&2; exit 1; }
    done
  fi
fi

python3 - "$manifest" "$plist_dir" "$embedded_inventory" <<'PY'
import json, os, sys, plistlib

manifest_path, plist_dir, embedded_raw = sys.argv[1], sys.argv[2], sys.argv[3]
with open(manifest_path, "rb") as f:
    manifest = json.load(f)

def capability_keys(entitlements):
    return {k for k in entitlements
            if k.startswith("com.apple.security.") or k == "keychain-access-groups"}

failures = []
expected_extensions = set()

for target in manifest["targets"]:
    name = target["name"]
    if target.get("kind") == "extension":
        expected_extensions.add(name)

    plist_path = os.path.join(plist_dir, f"{name}.plist")
    if not os.path.isfile(plist_path):
        failures.append(f"{name}: entitlements not found ({plist_path})")
        continue
    try:
        with open(plist_path, "rb") as fh:
            ents = plistlib.load(fh)
    except Exception as exc:
        failures.append(f"{name}: cannot parse entitlements ({exc})")
        continue

    required = set(target.get("required", []))
    forbidden = set(target.get("forbidden", []))
    caps = capability_keys(ents)

    missing = required - caps
    extra = caps - required
    present_forbidden = forbidden & set(ents.keys())

    if missing:
        failures.append(f"{name}: missing required entitlements: {sorted(missing)}")
    if extra:
        failures.append(f"{name}: unexpected entitlements (drift): {sorted(extra)}")
    if present_forbidden:
        failures.append(f"{name}: forbidden entitlements present: {sorted(present_forbidden)}")

# Inventory check (archive mode only; plist-dir mode infers from files present).
embedded = {line.strip() for line in embedded_raw.splitlines() if line.strip()}
if not embedded:
    # plist-dir mode: derive embedded extensions from the available plists.
    for fname in os.listdir(plist_dir):
        if fname.endswith(".plist"):
            base = fname[:-len(".plist")]
            if base != "MacPGP":
                embedded.add(base)

missing_ext = expected_extensions - embedded
unexpected_ext = embedded - expected_extensions
if missing_ext:
    failures.append(f"missing embedded extensions: {sorted(missing_ext)}")
if unexpected_ext:
    failures.append(f"unexpected embedded extensions: {sorted(unexpected_ext)}")

if failures:
    print("Archive entitlement check FAILED:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)

print("Archive entitlement check passed: all targets match the canonical manifest.")
PY
