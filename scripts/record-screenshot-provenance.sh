#!/usr/bin/env bash
# Records build provenance for the App Store screenshot set (issue #133).
#
# Populates the `build` block of the screenshot manifest with values derived from
# git, the signed app bundle, and the capture machine, so each screenshot set is
# traceable to the exact release candidate it came from. Run this on the capture
# machine, against the same signed build the screenshots were taken from.
#
# Usage:
#   scripts/record-screenshot-provenance.sh [manifest] [app-bundle] \
#       [archive-identifier] [display-scale] [captured-by]
#
# Auto-detected: gitCommit, macOSVersion, hardwareModel, capturedAt, and (when an
# app bundle is given) appVersion/buildNumber. archiveIdentifier, displayScale, and
# capturedBy are taken from arguments (or left as their current value if omitted).

set -euo pipefail

manifest="${1:-app-store-assets/screenshots/manifest.json}"
app_bundle="${2:-}"
archive_identifier="${3:-}"
display_scale="${4:-}"
captured_by="${5:-}"

if [[ ! -f "$manifest" ]]; then
  echo "::error::Manifest not found: $manifest" >&2
  exit 1
fi

git_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet HEAD 2>/dev/null; then
  git_commit="$git_commit-dirty"
fi
macos_version="$(sw_vers -productVersion 2>/dev/null || echo unknown) ($(sw_vers -buildVersion 2>/dev/null || echo unknown))"
hardware_model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

app_version=""
build_number=""
if [[ -n "$app_bundle" ]]; then
  plist="$app_bundle/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo unknown)"
    build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo unknown)"
  else
    echo "::warning::Info.plist not found in app bundle: $plist" >&2
  fi
fi

python3 - "$manifest" "$git_commit" "$macos_version" "$hardware_model" "$captured_at" \
    "$app_version" "$build_number" "$archive_identifier" "$display_scale" "$captured_by" <<'PY'
import json, sys

(manifest, git_commit, macos, hardware, captured_at,
 app_version, build_number, archive_id, display_scale, captured_by) = sys.argv[1:11]

with open(manifest) as handle:
    data = json.load(handle)

build = data.setdefault("build", {})
build["gitCommit"] = git_commit
build["macOSVersion"] = macos
build["hardwareModel"] = hardware
build["capturedAt"] = captured_at
if app_version:
    build["appVersion"] = app_version
if build_number:
    build["buildNumber"] = build_number
if archive_id:
    build["archiveIdentifier"] = archive_id
if display_scale:
    build["displayScale"] = display_scale
if captured_by:
    build["capturedBy"] = captured_by

with open(manifest, "w") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")

print("Recorded provenance into %s:" % manifest)
for key in ("appVersion", "buildNumber", "gitCommit", "archiveIdentifier",
            "macOSVersion", "hardwareModel", "displayScale", "capturedAt", "capturedBy"):
    print("  %-18s %s" % (key, build.get(key, "(unset)")))
remaining = [k for k, v in build.items() if str(v).startswith("TBD")]
if remaining:
    print("Still TBD (provide via arguments before release): %s" % ", ".join(remaining))
PY
