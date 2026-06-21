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

CONFIGURATION="Debug"
SIGNED=0
COMMAND=""

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
  test             Build and run the unit tests (MacPGPTests)
  uitest           Build and run the UI tests (MacPGPUITests)
  clean            Clean and remove DerivedData/ and TestResults/

Options:
  -c, --configuration <name>   Build configuration (default: Debug)
      --signed                 Use the project's signing instead of CI-style unsigned
  -h, --help                   Show this help

By default the build is UNSIGNED (ad-hoc, entitlements stripped) exactly like CI,
so it needs no provisioning profile or team. Use --signed when you need App Group
/ keychain entitlements (e.g. to exercise the Finder Sync / Share / Quick Look
extensions).

Environment overrides:
  DERIVED_DATA_PATH         build output dir (default: DerivedData)
  RESULT_BUNDLE_DIR         test result bundle dir (default: TestResults)
  MACOSX_DEPLOYMENT_TARGET  deployment target, unsigned builds only (default: 26.2)

Examples:
  scripts/build.sh                  # unsigned Debug build (CI parity)
  scripts/build.sh run              # build and launch
  scripts/build.sh run --signed     # build with real signing, then launch
  scripts/build.sh test             # unit tests
  scripts/build.sh build -c Release # Release build
EOF
}

# --- Argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    build|run|test|uitest|clean)
      [[ -n "$COMMAND" ]] && die "multiple commands given ('$COMMAND' and '$1')"
      COMMAND="$1" ;;
    -c|--configuration)
      [[ $# -ge 2 ]] || die "$1 requires a value (e.g. Debug or Release)"
      CONFIGURATION="$2"; shift ;;
    --signed) SIGNED=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: '$1' (try --help)" ;;
  esac
  shift
done
COMMAND="${COMMAND:-build}"

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

# Pretty-print xcodebuild output when a formatter is installed; otherwise raw.
formatter=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  formatter=(xcbeautify)
elif command -v xcpretty >/dev/null 2>&1; then
  formatter=(xcpretty)
fi

# pipefail (set -o above) makes the pipeline surface xcodebuild's exit status
# even when piped through the formatter, so build failures fail the script.
run_xcodebuild() { xcodebuild "$@" "${common_flags[@]}" "${signing_flags[@]}" | "${formatter[@]}"; }

app_path()   { printf '%s/Build/Products/%s/MacPGP.app' "$DERIVED_DATA_PATH" "$CONFIGURATION"; }
mode_label() { [[ "$SIGNED" -eq 1 ]] && echo "signed" || echo "unsigned, CI parity"; }

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
  test)   do_test ;;
  uitest) do_uitest ;;
  clean)  do_clean ;;
  *)      die "unknown command: '$COMMAND'" ;;
esac
