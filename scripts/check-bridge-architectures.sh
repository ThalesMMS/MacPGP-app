#!/usr/bin/env bash
# Reports the CPU architectures vendored in RNPBridge.xcframework and verifies
# they match the documented support matrix. MacPGP ships Apple Silicon (arm64)
# only; see README.md, DEVELOPMENT.md, and docs/APP_STORE_LISTING.md.
#
# Usage:
#   scripts/check-bridge-architectures.sh [xcframework] [expected_archs] [app_bundle]
#
# Environment overrides:
#   EXPECTED_ARCHS  space/comma separated architecture set (default: arm64)
#   APP_BUNDLE      path to the final .app archive to inspect (optional)

set -euo pipefail

xcframework="${1:-Vendor/RNPBridge/RNPBridge.xcframework}"
expected_archs="${EXPECTED_ARCHS:-${2:-arm64}}"
app_bundle="${APP_BUNDLE:-${3:-}}"

info_plist="$xcframework/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "::error::xcframework Info.plist not found: $info_plist" >&2
  exit 1
fi

# Normalize an architecture list into a sorted, space-separated set.
normalize_set() {
  tr ',' ' ' | tr -s '[:space:]' '\n' | sed '/^$/d' | sort -u | paste -sd' ' -
}

expected_set="$(printf '%s' "$expected_archs" | normalize_set)"

# Parse the xcframework Info.plist. plistlib ships with python3 and works on
# both macOS and Linux runners, so no Apple-only tooling is required here.
report="$(python3 - "$info_plist" <<'PY'
import plistlib, sys

with open(sys.argv[1], "rb") as handle:
    plist = plistlib.load(handle)

libraries = plist.get("AvailableLibraries", [])
all_archs = set()
for library in libraries:
    identifier = library.get("LibraryIdentifier", "?")
    platform = library.get("SupportedPlatform", "?")
    variant = library.get("SupportedPlatformVariant", "")
    archs = library.get("SupportedArchitectures", [])
    all_archs.update(archs)
    label = platform + ("-" + variant if variant else "")
    print("LIB\t%s\t%s\t%s" % (identifier, label, " ".join(sorted(archs))))
print("ALL\t%s" % " ".join(sorted(all_archs)))
PY
)"

echo "RNPBridge.xcframework architecture report ($xcframework):"
while IFS=$'\t' read -r tag identifier platform archs; do
  [[ "$tag" == "LIB" ]] || continue
  echo "  - $identifier [$platform]: ${archs:-<none>}"
done <<< "$report"

actual_set="$(printf '%s\n' "$report" | awk -F'\t' '$1=="ALL"{print $2}' | normalize_set)"

echo "  Architectures present:  ${actual_set:-<none>}"
echo "  Architectures expected: ${expected_set}"

if [[ "$actual_set" != "$expected_set" ]]; then
  echo "::error::RNPBridge.xcframework architectures (${actual_set:-<none>}) do not match the documented support matrix ($expected_set)." >&2
  echo "If this change is intentional (for example adding universal or x86_64 support), update README.md, DEVELOPMENT.md, docs/APP_STORE_LISTING.md, and the expected architecture set together." >&2
  exit 1
fi

# Optionally inspect the final app archive's main executable when provided.
if [[ -n "$app_bundle" ]]; then
  if [[ ! -d "$app_bundle" ]]; then
    echo "::error::App bundle path does not exist: $app_bundle" >&2
    exit 1
  fi
  app_name="$(basename "$app_bundle" .app)"
  app_binary="$app_bundle/Contents/MacOS/$app_name"
  if [[ ! -f "$app_binary" ]]; then
    echo "::error::App executable not found: $app_binary" >&2
    exit 1
  fi
  if command -v lipo >/dev/null 2>&1; then
    app_archs="$(lipo -archs "$app_binary" 2>/dev/null | normalize_set)"
    echo "  App archive executable architectures: ${app_archs:-<none>}"
    if [[ "$app_archs" != "$expected_set" ]]; then
      echo "::error::App archive architectures (${app_archs:-<none>}) do not match the documented support matrix ($expected_set)." >&2
      exit 1
    fi
  else
    echo "  (lipo unavailable; skipped app archive architecture inspection)"
  fi
fi

echo "Bridge architecture guardrail passed: ${actual_set} matches expected ${expected_set}."
