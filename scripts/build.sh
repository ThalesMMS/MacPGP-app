#!/usr/bin/env bash
# Local build/run/test wrapper for the MacPGP scheme.
#
# Mirrors the xcodebuild invocation in .github/workflows/ci.yml so a green local
# build matches CI. By default the build is UNSIGNED (ad-hoc identity with
# entitlements stripped) exactly like CI: it needs no provisioning profile or
# Apple Developer team and is enough to verify the app compiles, links, and runs.
# Pass --signed to build with the project's configured signing instead, which is
# required when you need App Group / keychain entitlements to work (e.g. to
# exercise the Finder Sync, Share, or Quick Look extensions).
#
# Run locally:
#   scripts/build.sh [command] [options]

set -euo pipefail
cd "$(dirname "$0")/.."

# --- Configuration (mirrors .github/workflows/ci.yml) -----------------------
PROJECT_PATH="MacPGP/MacPGP.xcodeproj"
SCHEME="MacPGP"
DESTINATION="platform=macOS"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-DerivedData}"
RESULT_BUNDLE_DIR="${RESULT_BUNDLE_DIR:-TestResults}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.2}"
TEAM_ID="${DEVELOPMENT_TEAM:-H4Q6WN7NV5}"
ARCHIVE_DIR="${ARCHIVE_DIR:-build}"
ARCHIVE_PATH_OVERRIDE="${ARCHIVE_PATH:-}"
EXPORT_PATH_OVERRIDE="${EXPORT_PATH:-}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS:-}"
DMG_OUTPUT_OVERRIDE="${DMG_OUTPUT:-}"

CONFIGURATION="Debug"
CONFIGURATION_SET=0
SIGNED=0
COMMAND=""
MARKETING_VERSION_OVERRIDE="${MARKETING_VERSION:-}"
BUILD_NUMBER_OVERRIDE="${CURRENT_PROJECT_VERSION:-}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-Developer ID Application: Thales Santos (H4Q6WN7NV5)}"
NOTARY_PROFILE_OVERRIDE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0

# --- Logging ----------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; BLUE=""; GREEN=""; RED=""; RESET=""
fi
info() { printf '%s==>%s %s\n' "$BLUE$BOLD" "$RESET" "$*"; }
ok()   { printf '%s==>%s %s\n' "$GREEN$BOLD" "$RESET" "$*"; }
die()  { printf '%serror:%s %s\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
MacPGP build helper — wraps the xcodebuild invocation used by CI.

Usage: scripts/build.sh [command] [options]

Commands:
  build            Build the app (default)
  run              Build, then launch MacPGP.app
  archive          Create and validate a signed Release .xcarchive
  dmg              Create, sign, notarize, and validate a Developer ID DMG
  test             Build and run the unit tests (MacPGPTests)
  uitest           Build and run the UI tests (MacPGPUITests)
  clean            Clean and remove DerivedData/ and TestResults/

Options:
  -c, --configuration <name>   Build configuration (default: Debug)
      --signed                 Use the project's signing instead of CI-style unsigned
      --version <version>      Override MARKETING_VERSION, required for archive
      --build-number <number>  Override CURRENT_PROJECT_VERSION, required for archive
      --sign-identity <name>   Developer ID identity for dmg
      --notary-profile <name>  notarytool keychain profile for dmg
      --skip-notarization      Create a signed local DMG without notarizing
  -h, --help                   Show this help

By default the build is UNSIGNED (ad-hoc, entitlements stripped) exactly like CI,
so it needs no provisioning profile or team. Use --signed when you need App Group
/ keychain entitlements (e.g. to exercise the Finder Sync / Share / Quick Look
extensions).

Environment overrides:
  DERIVED_DATA_PATH         build output dir (default: DerivedData)
  RESULT_BUNDLE_DIR         test result bundle dir (default: TestResults)
  MACOSX_DEPLOYMENT_TARGET  deployment target, unsigned builds only (default: 26.2)
  DEVELOPMENT_TEAM          signing team for archive (default: H4Q6WN7NV5)
  ARCHIVE_DIR               archive output dir (default: build)
  ARCHIVE_PATH              explicit archive output path
  EXPORT_PATH               explicit Developer ID export path for dmg
  EXPORT_OPTIONS            explicit Developer ID export options plist path for dmg
  DMG_OUTPUT                explicit DMG output path
  DMG_SIGN_IDENTITY         Developer ID identity for dmg
  NOTARY_PROFILE            notarytool keychain profile for dmg
  MARKETING_VERSION         default value for --version
  CURRENT_PROJECT_VERSION   default value for --build-number

Examples:
  scripts/build.sh                  # unsigned Debug build (CI parity)
  scripts/build.sh run              # build and launch
  scripts/build.sh run --signed     # build with real signing, then launch
  scripts/build.sh test             # unit tests
  scripts/build.sh build -c Release # Release build
  scripts/build.sh archive --version 1.0.1 --build-number 2
  scripts/build.sh dmg --version 1.0.1 --build-number 2 --notary-profile macpgp-notary
EOF
}

# --- Argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    build|run|archive|dmg|test|uitest|clean)
      [[ -n "$COMMAND" ]] && die "multiple commands given ('$COMMAND' and '$1')"
      COMMAND="$1" ;;
    -c|--configuration)
      [[ $# -ge 2 ]] || die "$1 requires a value (e.g. Debug or Release)"
      CONFIGURATION="$2"; CONFIGURATION_SET=1; shift ;;
    --signed) SIGNED=1 ;;
    --version)
      [[ $# -ge 2 ]] || die "$1 requires a value (e.g. 1.0.1)"
      MARKETING_VERSION_OVERRIDE="$2"; shift ;;
    --build-number)
      [[ $# -ge 2 ]] || die "$1 requires a value (e.g. 2)"
      BUILD_NUMBER_OVERRIDE="$2"; shift ;;
    --sign-identity)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      DMG_SIGN_IDENTITY="$2"; shift ;;
    --notary-profile)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      NOTARY_PROFILE_OVERRIDE="$2"; shift ;;
    --skip-notarization)
      SKIP_NOTARIZATION=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: '$1' (try --help)" ;;
  esac
  shift
done
COMMAND="${COMMAND:-build}"
if [[ "$COMMAND" =~ ^(archive|dmg)$ && "$CONFIGURATION_SET" -eq 0 ]]; then
  CONFIGURATION="Release"
fi

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode and its command-line tools."

# --- xcodebuild flag sets ---------------------------------------------------
common_flags=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -skipPackagePluginValidation
  -skipMacroValidation
)

signing_flags=()
if [[ "$SIGNED" -eq 1 ]]; then
  # Let the project's configured signing apply; allow xcodebuild to resolve
  # automatic provisioning without an interactive Xcode session.
  signing_flags+=( -allowProvisioningUpdates )
else
  # CI parity: ad-hoc signing with entitlements stripped — no team or profile
  # required. See the "Build MacPGP scheme" step in .github/workflows/ci.yml.
  signing_flags+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_ENTITLEMENTS=
    DEVELOPMENT_TEAM=
    PROVISIONING_PROFILE_SPECIFIER=
    MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
  )
fi

xcode_setting_overrides=()
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  xcode_setting_overrides+=( MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE" )
fi
if [[ -n "$BUILD_NUMBER_OVERRIDE" ]]; then
  xcode_setting_overrides+=( CURRENT_PROJECT_VERSION="$BUILD_NUMBER_OVERRIDE" )
fi

# Pretty-print xcodebuild output when a formatter is installed; otherwise raw.
formatter=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  formatter=(xcbeautify)
elif command -v xcpretty >/dev/null 2>&1; then
  formatter=(xcpretty)
fi

# pipefail (set -o above) makes the pipeline surface xcodebuild's exit status
# even when piped through the formatter, so build failures fail the script.
run_xcodebuild() {
  if [[ -n "$MARKETING_VERSION_OVERRIDE" || -n "$BUILD_NUMBER_OVERRIDE" ]]; then
    xcodebuild "$@" "${common_flags[@]}" "${signing_flags[@]}" "${xcode_setting_overrides[@]}" | "${formatter[@]}"
  else
    xcodebuild "$@" "${common_flags[@]}" "${signing_flags[@]}" | "${formatter[@]}"
  fi
}

safe_value() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
app_path()   { printf '%s/Build/Products/%s/MacPGP.app' "$DERIVED_DATA_PATH" "$CONFIGURATION"; }
archive_path() {
  if [[ -n "$ARCHIVE_PATH_OVERRIDE" ]]; then
    printf '%s' "$ARCHIVE_PATH_OVERRIDE"
    return
  fi

  local safe_version safe_build
  safe_version="$(safe_value "$MARKETING_VERSION_OVERRIDE")"
  safe_build="$(safe_value "$BUILD_NUMBER_OVERRIDE")"
  printf '%s/MacPGP-%s-%s.xcarchive' "$ARCHIVE_DIR" "$safe_version" "$safe_build"
}
developer_id_export_path() {
  if [[ -n "$EXPORT_PATH_OVERRIDE" ]]; then
    printf '%s' "$EXPORT_PATH_OVERRIDE"
    return
  fi

  local safe_version safe_build
  safe_version="$(safe_value "$MARKETING_VERSION_OVERRIDE")"
  safe_build="$(safe_value "$BUILD_NUMBER_OVERRIDE")"
  printf '%s/developer-id-%s-%s' "$ARCHIVE_DIR" "$safe_version" "$safe_build"
}
developer_id_export_options_path() {
  if [[ -n "$EXPORT_OPTIONS_PATH" ]]; then
    printf '%s' "$EXPORT_OPTIONS_PATH"
    return
  fi
  printf '%s/MacPGP-DeveloperIDExportOptions.plist' "$ARCHIVE_DIR"
}
dmg_output_path() {
  if [[ -n "$DMG_OUTPUT_OVERRIDE" ]]; then
    printf '%s' "$DMG_OUTPUT_OVERRIDE"
    return
  fi

  local safe_version
  safe_version="$(safe_value "$MARKETING_VERSION_OVERRIDE")"
  printf '%s/dmg/MacPGP-%s.dmg' "$ARCHIVE_DIR" "$safe_version"
}
mode_label() { [[ "$SIGNED" -eq 1 ]] && echo "signed" || echo "unsigned, CI parity"; }

require_release_inputs() {
  local command_name="$1"
  [[ "$CONFIGURATION" == "Release" ]] || die "$command_name requires Release configuration (omit -c or pass -c Release)"
  [[ -n "$MARKETING_VERSION_OVERRIDE" ]] || die "$command_name requires --version <version> (e.g. --version 1.0.1)"
  [[ -n "$BUILD_NUMBER_OVERRIDE" ]] || die "$command_name requires --build-number <number> (e.g. --build-number 2)"
}

write_developer_id_export_options() {
  local export_options="$1"
  mkdir -p "$(dirname "$export_options")"
  rm -f "$export_options"
  plutil -create xml1 "$export_options"
  plutil -insert method -string developer-id "$export_options"
  plutil -insert destination -string export "$export_options"
  plutil -insert signingStyle -string automatic "$export_options"
  plutil -insert teamID -string "$TEAM_ID" "$export_options"
}

# --- Commands ---------------------------------------------------------------
do_build() {
  info "Building $SCHEME ($CONFIGURATION, $(mode_label))"
  run_xcodebuild build
  ok "Build succeeded → $(app_path)"
}

do_run() {
  do_build
  local app; app="$(app_path)"
  [[ -d "$app" ]] || die "built app not found at $app"
  info "Launching $app"
  open "$app"
}

do_archive() {
  require_release_inputs archive

  local archive app
  archive="$(archive_path)"
  app="$archive/Products/Applications/MacPGP.app"

  mkdir -p "$(dirname "$archive")"
  info "Archiving $SCHEME ($CONFIGURATION, signed, version $MARKETING_VERSION_OVERRIDE build $BUILD_NUMBER_OVERRIDE)"
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$archive" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    "${xcode_setting_overrides[@]}" | "${formatter[@]}"

  [[ -d "$app" ]] || die "archived app not found at $app"
  info "Validating archive entitlements"
  scripts/check-archive-entitlements.sh --archive "$archive"
  info "Checking ShareExtension release embedding"
  CONFIGURATION=Release APP_BUNDLE="$app" scripts/check-shareextension-in-release.sh "$PROJECT_PATH/project.pbxproj"
  info "Checking release architecture"
  APP_BUNDLE="$app" scripts/check-bridge-architectures.sh
  ok "Archive succeeded and validated → $archive"
}

do_dmg() {
  require_release_inputs dmg
  if [[ "$SKIP_NOTARIZATION" -eq 1 && -n "$NOTARY_PROFILE_OVERRIDE" ]]; then
    die "--skip-notarization cannot be combined with --notary-profile"
  fi
  if [[ "$SKIP_NOTARIZATION" -eq 0 && -z "$NOTARY_PROFILE_OVERRIDE" ]]; then
    die "dmg requires --notary-profile <profile> for a publishable release; pass --skip-notarization only for local validation"
  fi
  if ! security find-identity -v -p codesigning | grep -F "$DMG_SIGN_IDENTITY" >/dev/null; then
    die "Developer ID signing identity not found: $DMG_SIGN_IDENTITY"
  fi

  local archive export_path export_options app output
  archive="$(archive_path)"
  export_path="$(developer_id_export_path)"
  export_options="$(developer_id_export_options_path)"
  app="$export_path/MacPGP.app"
  output="$(dmg_output_path)"

  do_archive

  info "Exporting Developer ID app → $export_path"
  write_developer_id_export_options "$export_options"
  rm -rf "$export_path"
  mkdir -p "$export_path"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates | "${formatter[@]}"

  [[ -d "$app" ]] || die "Developer ID export did not create $app"

  package_args=(
    --app "$app"
    --output "$output"
    --sign-identity "$DMG_SIGN_IDENTITY"
  )
  if [[ -n "$NOTARY_PROFILE_OVERRIDE" ]]; then
    package_args+=( --notary-profile "$NOTARY_PROFILE_OVERRIDE" )
  fi

  info "Creating Developer ID DMG → $output"
  bash scripts/package-dmg.sh "${package_args[@]}"

  if [[ "$SKIP_NOTARIZATION" -eq 0 ]]; then
    info "Validating Gatekeeper assessment"
    spctl -a -t open --context context:primary-signature -v "$output"
    ok "Publishable notarized DMG succeeded → $output"
  else
    info "Created a signed but unnotarized DMG; notarize before publishing."
    ok "Local DMG succeeded → $output"
  fi
}

do_test() {
  mkdir -p "$RESULT_BUNDLE_DIR"
  info "Running MacPGPTests ($CONFIGURATION, $(mode_label))"
  run_xcodebuild test \
    -only-testing:MacPGPTests \
    -resultBundlePath "$RESULT_BUNDLE_DIR/MacPGPTests.xcresult"
  ok "Unit tests passed → $RESULT_BUNDLE_DIR/MacPGPTests.xcresult"
}

do_uitest() {
  mkdir -p "$RESULT_BUNDLE_DIR"
  info "Running MacPGPUITests ($CONFIGURATION, $(mode_label))"
  run_xcodebuild test \
    -only-testing:MacPGPUITests \
    -resultBundlePath "$RESULT_BUNDLE_DIR/MacPGPUITests.xcresult" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 600
  ok "UI tests passed → $RESULT_BUNDLE_DIR/MacPGPUITests.xcresult"
}

do_clean() {
  info "Cleaning $SCHEME and removing build output"
  xcodebuild clean "${common_flags[@]}" >/dev/null 2>&1 || true
  rm -rf "$DERIVED_DATA_PATH" "$RESULT_BUNDLE_DIR"
  ok "Removed $DERIVED_DATA_PATH/ and $RESULT_BUNDLE_DIR/"
}

case "$COMMAND" in
  build)  do_build ;;
  run)    do_run ;;
  archive) do_archive ;;
  dmg)    do_dmg ;;
  test)   do_test ;;
  uitest) do_uitest ;;
  clean)  do_clean ;;
  *)      die "unknown command: '$COMMAND'" ;;
esac
