#!/usr/bin/env bash
set -euo pipefail

configuration="${CONFIGURATION:-Release}"
project_file="${1:-MacPGP/MacPGP.xcodeproj/project.pbxproj}"
app_bundle="${APP_BUNDLE:-${2:-}}"

if [[ "$configuration" != "Release" ]]; then
  echo "Skipping ShareExtension release guardrail for CONFIGURATION=$configuration."
  exit 0
fi

if [[ ! -f "$project_file" ]]; then
  echo "::error::Cannot check ShareExtension.appex guardrail because project file was not found: $project_file"
  exit 1
fi

if awk '
  /\/\* Embed Foundation Extensions \*\/ = \{/ { in_embed_phase = 1 }
  in_embed_phase && /ShareExtension\.appex/ { found = 1 }
  in_embed_phase && /^[[:space:]]*};/ { in_embed_phase = 0 }
  END { exit found ? 0 : 1 }
' "$project_file"; then
  echo "::error::ShareExtension.appex must not be embedded in the main app target for Release/v1.0. Remove it from MacPGP's Embed Foundation Extensions build phase."
  exit 1
fi

if [[ -n "$app_bundle" && -d "$app_bundle/Contents/PlugIns/ShareExtension.appex" ]]; then
  echo "::error::ShareExtension.appex was found in $app_bundle/Contents/PlugIns. Release builds of the main app target must not embed ShareExtension.appex."
  exit 1
fi

echo "Release guardrail passed: ShareExtension.appex is not embedded in the main app target."
