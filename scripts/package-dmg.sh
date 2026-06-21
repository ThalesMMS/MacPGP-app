#!/usr/bin/env bash
# Creates a distributable DMG from an existing MacPGP.app bundle.
#
# The app bundle should already be built/exported with the intended signing
# identity. For public distribution outside the Mac App Store, use a Developer ID
# signed app, then sign and notarize the DMG with the options below.

set -euo pipefail
cd "$(dirname "$0")/.."

app_bundle=""
output_path=""
volume_name=""
sign_identity="${DMG_SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"
staple=1

usage() {
  cat <<'EOF'
Usage: scripts/package-dmg.sh [options]

Options:
  --app <path>             MacPGP.app to package. Defaults to a known build/export path.
  --output <path>          Output DMG path. Defaults to build/dmg/MacPGP-<version>.dmg.
  --volume-name <name>     Mounted volume name. Defaults to "MacPGP <version>".
  --sign-identity <name>   Code-sign the DMG, for example "Developer ID Application: ...".
  --notary-profile <name>  Submit the DMG with xcrun notarytool --keychain-profile.
  --skip-staple            Do not staple after notarization.
  -h, --help               Show this help.

Environment:
  DMG_SIGN_IDENTITY        Default value for --sign-identity.
  NOTARY_PROFILE           Default value for --notary-profile.

Examples:
  scripts/package-dmg.sh --app build/developer-id/MacPGP.app
  scripts/package-dmg.sh --app build/developer-id/MacPGP.app \
    --sign-identity "Developer ID Application: Example, Inc. (TEAMID)" \
    --notary-profile macpgp-notary
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || die "--app requires a path"
      app_bundle="$2"; shift 2 ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires a path"
      output_path="$2"; shift 2 ;;
    --volume-name)
      [[ $# -ge 2 ]] || die "--volume-name requires a value"
      volume_name="$2"; shift 2 ;;
    --sign-identity)
      [[ $# -ge 2 ]] || die "--sign-identity requires a value"
      sign_identity="$2"; shift 2 ;;
    --notary-profile)
      [[ $# -ge 2 ]] || die "--notary-profile requires a value"
      notary_profile="$2"; shift 2 ;;
    --skip-staple)
      staple=0; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

require_tool hdiutil
require_tool ditto
require_tool codesign

if [[ -z "$app_bundle" ]]; then
  for candidate in \
    "build/developer-id/MacPGP.app" \
    "build/export/MacPGP.app" \
    "DerivedData/Build/Products/Release/MacPGP.app" \
    "DerivedData/Build/Products/Debug/MacPGP.app"
  do
    if [[ -d "$candidate" ]]; then
      app_bundle="$candidate"
      break
    fi
  done
fi

[[ -n "$app_bundle" ]] || die "no app bundle supplied; pass --app /path/to/MacPGP.app"
[[ -d "$app_bundle" ]] || die "app bundle not found: $app_bundle"

info_plist="$app_bundle/Contents/Info.plist"
[[ -f "$info_plist" ]] || die "Info.plist not found in app bundle: $info_plist"

bundle_name="$(plist_value CFBundleName "$info_plist")"
short_version="$(plist_value CFBundleShortVersionString "$info_plist")"
build_version="$(plist_value CFBundleVersion "$info_plist")"

[[ -n "$bundle_name" ]] || bundle_name="$(basename "$app_bundle" .app)"
[[ -n "$short_version" ]] || short_version="0"
[[ -n "$build_version" ]] || build_version="0"

if [[ -z "$volume_name" ]]; then
  volume_name="$bundle_name $short_version"
fi

if [[ -z "$output_path" ]]; then
  safe_version="$(printf '%s' "$short_version" | tr -c 'A-Za-z0-9._-' '-')"
  output_path="build/dmg/$bundle_name-$safe_version.dmg"
fi

mkdir -p "$(dirname "$output_path")"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/macpgp-dmg.XXXXXX")"
cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

staging_volume="$staging_root/$volume_name"
mkdir -p "$staging_volume"

app_name="$(basename "$app_bundle")"
ditto --rsrc --extattr "$app_bundle" "$staging_volume/$app_name"
ln -s /Applications "$staging_volume/Applications"

rm -f "$output_path"
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_volume" \
  -format UDZO \
  -fs HFS+ \
  -ov \
  "$output_path"

hdiutil verify "$output_path" >/dev/null

if [[ -n "$sign_identity" ]]; then
  codesign --force --sign "$sign_identity" --timestamp "$output_path"
  codesign --verify --verbose "$output_path"
fi

if [[ -n "$notary_profile" ]]; then
  require_tool xcrun
  xcrun notarytool submit "$output_path" --keychain-profile "$notary_profile" --wait
  if [[ "$staple" -eq 1 ]]; then
    xcrun stapler staple "$output_path"
    xcrun stapler validate "$output_path"
  fi
fi

echo "Created DMG: $output_path"
echo "Packaged app: $app_name ($short_version, build $build_version)"
