#!/usr/bin/env bash
set -euo pipefail

max_minos="${1:-26.2}"
bridge_archive="${2:-Vendor/RNPBridge/RNPBridge.xcframework/macos-arm64/libRNPBridge.a}"

if [[ ! "$max_minos" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "::error::Invalid macOS deployment target: $max_minos" >&2
  exit 1
fi

if [[ ! -f "$bridge_archive" ]]; then
  echo "::error::RNPBridge archive was not found: $bridge_archive" >&2
  exit 1
fi

version_number() {
  local version="$1"
  local major minor patch
  IFS=. read -r major minor patch <<< "$version"
  printf '%d%03d%03d\n' "$major" "${minor:-0}" "${patch:-0}"
}

max_minos_number="$(version_number "$max_minos")"
highest_minos="0.0"
highest_minos_number=0
found_minos=0

while IFS= read -r object_minos; do
  [[ -z "$object_minos" ]] && continue
  found_minos=1

  object_minos_number="$(version_number "$object_minos")"
  if (( object_minos_number > highest_minos_number )); then
    highest_minos="$object_minos"
    highest_minos_number="$object_minos_number"
  fi

  if (( object_minos_number > max_minos_number )); then
    echo "::error::RNPBridge object minos $object_minos is newer than allowed target $max_minos." >&2
    echo "Rebuild the bridge for macOS $max_minos or raise the CI/project deployment target intentionally." >&2
    exit 1
  fi
done < <(otool -l "$bridge_archive" | awk '/^[[:space:]]*minos / { print $2 }' | sort -u)

if (( found_minos == 0 )); then
  echo "::error::No LC_BUILD_VERSION minos entries found in $bridge_archive." >&2
  exit 1
fi

echo "RNPBridge minos guardrail passed: highest object minos $highest_minos <= allowed target $max_minos."
