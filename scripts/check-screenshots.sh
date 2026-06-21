#!/usr/bin/env bash
# Validates the App Store screenshot set against its manifest (issue #133).
#
# Checks: manifest JSON validity, sequence integrity (no duplicates, contiguous),
# required filenames, PNG file type, required dimensions, forbidden placeholder /
# stray files, and (with --require-complete) that every required capture exists and
# the build provenance is populated.
#
# Usage:
#   scripts/check-screenshots.sh [assets-dir] [--require-complete]
#
# Without --require-complete (default, e.g. on dev branches) it validates whatever
# has been captured so far and never fails on not-yet-captured screenshots. Release
# validation should pass --require-complete to gate on a complete, provenanced set.

set -uo pipefail

assets_dir="app-store-assets/screenshots"
require_complete=0
for arg in "$@"; do
  case "$arg" in
    --require-complete) require_complete=1 ;;
    *) assets_dir="$arg" ;;
  esac
done

manifest="$assets_dir/manifest.json"
fail=0
err() { echo "::error::$*" >&2; fail=1; }

if [[ ! -f "$manifest" ]]; then
  echo "::error::Screenshot manifest not found: $manifest" >&2
  exit 1
fi

parsed="$(python3 - "$manifest" <<'PY'
import json, sys
try:
    m = json.load(open(sys.argv[1]))
except Exception as exc:
    print("FATAL\t%s" % exc)
    sys.exit(0)

try:
    print("DIMS\t%s" % m["target"]["requiredDimensions"])
    seqs = []
    for s in m["screenshots"]:
        seqs.append(int(s["sequence"]))
        for appearance, rel in s["files"].items():
            print("FILE\t%s\t%d\t%s\t%s" % (rel, int(s.get("optional", False)), s["subject"], appearance))
    if len(set(seqs)) != len(seqs):
        print("ERROR\tDuplicate sequence numbers in manifest")
    if sorted(seqs) != list(range(1, len(seqs) + 1)):
        print("ERROR\tSequence numbers must be contiguous starting at 1")
    for key, value in m["build"].items():
        if str(value).startswith("TBD"):
            print("TBD\t%s" % key)
except (KeyError, TypeError) as exc:
    print("FATAL\tManifest missing required field: %s" % exc)
PY
)"

if grep -q $'^FATAL\t' <<<"$parsed"; then
  err "Invalid manifest: $(grep $'^FATAL\t' <<<"$parsed" | cut -f2-)"
  exit 1
fi

required_dims="$(grep $'^DIMS\t' <<<"$parsed" | head -1 | cut -f2)"

while IFS=$'\t' read -r tag rest; do
  [[ "$tag" == "ERROR" ]] && err "$rest"
done <<<"$parsed"

# Validate each manifest-declared file that exists; track coverage.
declared_files=()
while IFS=$'\t' read -r tag rel optional subject appearance; do
  [[ "$tag" == "FILE" ]] || continue
  declared_files+=("$rel")
  path="$assets_dir/$rel"

  if [[ ! -f "$path" ]]; then
    if [[ "$require_complete" -eq 1 && "$optional" != "1" ]]; then
      err "Required screenshot missing: $rel"
    else
      echo "  pending: $rel"
    fi
    continue
  fi

  # File type must be PNG. A 0-byte or non-image placeholder fails here
  # (an empty file reports as application/x-empty, not image/png).
  if [[ "$(file -b --mime-type "$path" 2>/dev/null)" != "image/png" ]]; then
    err "Not a PNG file (empty or placeholder): $rel"
    continue
  fi

  # Dimension check via sips (macOS). A wrong-sized placeholder fails here.
  if command -v sips >/dev/null 2>&1; then
    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    if [[ "${width}x${height}" != "$required_dims" ]]; then
      err "Wrong dimensions for $rel: ${width}x${height} (expected $required_dims)"
      continue
    fi
  fi

  echo "  ok: $rel (${width:-?}x${height:-?})"
done <<<"$parsed"

# Stray / placeholder PNGs that are not declared in the manifest.
while IFS= read -r found; do
  rel="${found#"$assets_dir/"}"
  if ! printf '%s\n' "${declared_files[@]}" | grep -qxF "$rel"; then
    err "Stray screenshot file not listed in manifest: $rel"
  fi
done < <(find "$assets_dir" -type f -name '*.png' 2>/dev/null)

# Provenance completeness is only enforced for a release-complete set.
if [[ "$require_complete" -eq 1 ]]; then
  while IFS=$'\t' read -r tag key; do
    [[ "$tag" == "TBD" ]] && err "Build provenance not populated: build.$key is still TBD"
  done <<<"$parsed"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Screenshot validation FAILED." >&2
  exit 1
fi

if [[ "$require_complete" -eq 1 ]]; then
  echo "Screenshot validation passed: complete, provenanced, correctly sized set."
else
  echo "Screenshot validation passed (captured files valid; missing captures are allowed pre-release)."
fi
