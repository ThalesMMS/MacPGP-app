#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BRIDGE_ROOT="$ROOT/Vendor/RNPBridge"
BUILD_ROOT="$BRIDGE_ROOT/build/arm64"
HEADERS_ROOT="$BRIDGE_ROOT/headers"
XCFRAMEWORK_PATH="$BRIDGE_ROOT/RNPBridge.xcframework"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-${BREW_PREFIX:-}}"

if [[ -z "$HOMEBREW_PREFIX" ]]; then
  HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
fi

if [[ -z "$HOMEBREW_PREFIX" ]]; then
  echo "Unable to determine Homebrew prefix. Set HOMEBREW_PREFIX or BREW_PREFIX." >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT" "$HEADERS_ROOT/rnp"

cp "$HOMEBREW_PREFIX/opt/rnp/include/rnp/"*.h "$HEADERS_ROOT/rnp/"

libtool -static \
  -o "$BUILD_ROOT/libRNPBridge.a" \
  "$HOMEBREW_PREFIX/opt/rnp/lib/librnp.a" \
  "$HOMEBREW_PREFIX/opt/rnp/lib/libsexpp.a" \
  "$HOMEBREW_PREFIX/opt/botan/lib/libbotan-3.a" \
  "$HOMEBREW_PREFIX/opt/json-c/lib/libjson-c.a"

rm -rf "$XCFRAMEWORK_PATH"

xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/libRNPBridge.a" \
  -headers "$HEADERS_ROOT" \
  -output "$XCFRAMEWORK_PATH"
