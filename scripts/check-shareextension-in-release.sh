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

if ! awk '
  /\/\* Embed Foundation Extensions \*\/ = \{/ { in_embed_phase = 1 }
  in_embed_phase && /ShareExtension\.appex/ { found = 1 }
  in_embed_phase && /^[[:space:]]*};/ { in_embed_phase = 0 }
  END { exit found ? 0 : 1 }
' "$project_file"; then
  echo "::error::ShareExtension.appex must be embedded in the main app target for Release builds. Add it to MacPGP's Embed Foundation Extensions build phase."
  exit 1
fi

if [[ -n "$app_bundle" ]]; then
  if [[ ! -d "$app_bundle" ]]; then
    echo "::error::Cannot check ShareExtension.appex in app bundle because the path does not exist: $app_bundle"
    exit 1
  fi

  if [[ ! -d "$app_bundle/Contents/PlugIns/ShareExtension.appex" ]]; then
    echo "::error::ShareExtension.appex was not found in $app_bundle/Contents/PlugIns."
    exit 1
  fi
fi

echo "Release guardrail passed: ShareExtension.appex is embedded in the main app target."
