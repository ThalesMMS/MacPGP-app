# Releasing MacPGP

MacPGP already has a substantial local feature set, but it does not publish GitHub releases yet.
This document keeps the first public release honest: ship a prerelease if any gate below is still incomplete, and cut a stable `v1.0.0` only after the full checklist is done.

## Versioning strategy

- Use Semantic Versioning for Git tags (`vMAJOR.MINOR.PATCH`).
- Keep the app's `MARKETING_VERSION` aligned with the intended release line.
- Use `CURRENT_PROJECT_VERSION` as the build number and increment it for each shipped build.
- Prefer prerelease tags such as `v1.0.0-rc.1` if signing, notarization, or final validation is still pending.

## Signing prerequisites

Release signing is documented in `docs/PROVISIONING_PROFILE_FIX.md`. Before
creating a signed archive, confirm:

- Xcode is signed into an Apple Developer account on team `H4Q6WN7NV5`.
- Automatic signing is enabled for MacPGP, FinderSyncExtension,
  QuickLookExtension, and ThumbnailExtension.
- The App IDs for all shipped targets include the shared App Group
  `group.com.macpgp.shared`.
- The Release machine can create or download provisioning profiles, either via
  the signed-in Xcode account or App Store Connect credentials passed to
  `xcodebuild`.

The CI build with `CODE_SIGNING_ALLOWED=NO` is a source-build check only. Actual
Release signing cannot run in CI unless the runner has the required Apple
Developer account access, certificates/profiles or automatic signing access, and
App Store Connect credentials configured as secrets.

## Release archive and export

Create a signed Release archive from the repository root:

```bash
ARCHIVE_PATH="$PWD/build/MacPGP.xcarchive"
mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild archive \
  -project MacPGP/MacPGP.xcodeproj \
  -scheme MacPGP \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=H4Q6WN7NV5 \
  CODE_SIGN_STYLE=Automatic
```

Create an export options plist for an App Store Connect export:

```bash
EXPORT_OPTIONS="$PWD/build/MacPGP-AppStoreExportOptions.plist"

mkdir -p "$(dirname "$EXPORT_OPTIONS")"
rm -f "$EXPORT_OPTIONS"
plutil -create xml1 "$EXPORT_OPTIONS"
plutil -insert method -string app-store-connect "$EXPORT_OPTIONS"
plutil -insert destination -string export "$EXPORT_OPTIONS"
plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS"
plutil -insert teamID -string H4Q6WN7NV5 "$EXPORT_OPTIONS"
plutil -insert uploadSymbols -bool YES "$EXPORT_OPTIONS"
```

Export the archive:

```bash
EXPORT_PATH="$PWD/build/export"
mkdir -p "$EXPORT_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates
```

For a local validation export, use the same command with an export options plist
whose `method` is `validation`.

Validate the exported App Store package with App Store Connect:

```bash
PKG_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.pkg' -print -quit)"
test -n "$PKG_PATH"

xcrun altool --validate-app \
  -f "$PKG_PATH" \
  -t macos \
  --api-key "$ASC_API_KEY" \
  --api-issuer "$ASC_API_ISSUER_ID" \
  --output-format json
```

The App Store Connect API key file must be available to `altool`, or pass its
path with `--p8-file-path`.

Transporter can be used instead of `altool`: add the exported package in the
Transporter app and run Validate before upload.

After export, inspect the archive signatures and App Group entitlements with the
commands in `docs/PROVISIONING_PROFILE_FIX.md`.

## Release checklist

- [ ] `CHANGELOG.md` updated for the release
- [ ] Draft release notes reviewed in GitHub
- [ ] `xcodebuild build -project MacPGP/MacPGP.xcodeproj -scheme MacPGP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [ ] Manual smoke test completed for key generation/import, encrypt/decrypt, sign/verify, and key export
- [ ] Finder Sync, Quick Look, and Thumbnail extensions verified on a clean local install
- [ ] Signed Release archive created and validated with matching team ID and App Group entitlements
- [ ] App Store Connect export validated with `xcodebuild -exportArchive` and `altool` or Transporter
- [ ] Distribution artifact decided and documented (for example: signed `.app`, `.zip`, or `.dmg`)
- [ ] macOS signing/notarization status confirmed in the release notes
- [ ] Installation and extension-enablement steps in `README.md` verified against the shipped artifact

## First stable release gate

Cut the first stable `v1.0.0` only when all checklist items above are complete.
If any item is still open, publish a prerelease instead and call out the remaining gaps in the release notes.
