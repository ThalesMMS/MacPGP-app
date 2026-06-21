#!/usr/bin/env bash
# Fails when the documented shipping-extension list diverges from the release
# target configuration. This prevents the kind of contradiction described in
# issue #124, where ShareExtension was embedded and CI-enforced but listed under
# "Postponed to Future Release" in docs/V1_SCOPE.md.
#
# Source of truth comparison:
#   - Release target config: the "Embed Foundation Extensions" build phase in
#     MacPGP/MacPGP.xcodeproj/project.pbxproj (the *.appex bundles that ship).
#   - Documentation: the "## Shipped Extensions" section in docs/V1_SCOPE.md
#     (each "### <ExtensionName>" heading).
#
# Usage:
#   scripts/check-extension-scope-consistency.sh [project.pbxproj] [V1_SCOPE.md]

set -euo pipefail

pbxproj="${1:-MacPGP/MacPGP.xcodeproj/project.pbxproj}"
scope="${2:-docs/V1_SCOPE.md}"

if [[ ! -f "$pbxproj" ]]; then
  echo "::error::Project file not found: $pbxproj" >&2
  exit 1
fi
if [[ ! -f "$scope" ]]; then
  echo "::error::Scope document not found: $scope" >&2
  exit 1
fi

# Extension bundles embedded in the main app's "Embed Foundation Extensions"
# build phase, reduced to their base names (FinderSyncExtension, ...).
embedded="$(awk '
  /\/\* Embed Foundation Extensions \*\/ = \{/ { in_phase = 1 }
  in_phase && /^[[:space:]]*};/ { in_phase = 0 }
  in_phase { print }
' "$pbxproj" | grep -oE '[A-Za-z0-9_]+\.appex' | sed 's/\.appex$//' | sort -u)"

# Extensions documented as shipping in the "## Shipped Extensions" section.
documented="$(awk '
  /^##[[:space:]]+Shipped Extensions[[:space:]]*$/ { in_section = 1; next }
  in_section && /^##[[:space:]]/ { in_section = 0 }
  in_section && /^###[[:space:]]+/ {
    line = $0
    sub(/^###[[:space:]]+/, "", line)
    sub(/[[:space:]]+$/, "", line)
    print line
  }
' "$scope" | sort -u)"

echo "Embedded extensions (release target):"
echo "$embedded" | sed 's/^/  - /'
echo "Documented shipping extensions ($scope):"
echo "$documented" | sed 's/^/  - /'

if [[ -z "$embedded" ]]; then
  echo "::error::No extensions found in the Embed Foundation Extensions build phase of $pbxproj." >&2
  exit 1
fi
if [[ -z "$documented" ]]; then
  echo "::error::No extensions found under '## Shipped Extensions' in $scope." >&2
  exit 1
fi

if [[ "$embedded" != "$documented" ]]; then
  echo "::error::Shipping-extension documentation diverges from the release target configuration." >&2
  only_embedded="$(comm -23 <(printf '%s\n' "$embedded") <(printf '%s\n' "$documented"))"
  only_documented="$(comm -13 <(printf '%s\n' "$embedded") <(printf '%s\n' "$documented"))"
  if [[ -n "$only_embedded" ]]; then
    echo "Embedded but not documented as shipping in $scope:" >&2
    echo "$only_embedded" | sed 's/^/  - /' >&2
  fi
  if [[ -n "$only_documented" ]]; then
    echo "Documented as shipping but not embedded in the release target:" >&2
    echo "$only_documented" | sed 's/^/  - /' >&2
  fi
  echo "Align docs/V1_SCOPE.md and the Xcode 'Embed Foundation Extensions' build phase, then re-run." >&2
  exit 1
fi

echo "Extension scope consistency check passed: documented shipping extensions match the release target."
