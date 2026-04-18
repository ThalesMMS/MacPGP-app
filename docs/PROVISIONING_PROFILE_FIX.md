# MacPGP Signing and Provisioning Guide

**Status: Resolved on 2026-04-14**

The project is configured for automatic signing with target-specific
entitlements. This document records the current signing setup and the checks
needed to keep App Groups and Release signing reproducible on another machine.

The previous provisioning failures about missing App Groups are historical. If
they reappear, treat that as a regression in the Apple Developer Portal App ID
or provisioning profile setup, not as a source-code-only issue.

## Current Signing Setup

- Xcode project: `MacPGP/MacPGP.xcodeproj`
- Scheme used for the app archive: `MacPGP`
- Signing style: `Automatic`
- Apple Developer team: `H4Q6WN7NV5`
- Shared App Group: `group.com.macpgp.shared`
- Debug and Release signing settings are intentionally aligned for shipped
  targets: automatic signing, team `H4Q6WN7NV5`, target-specific entitlements,
  and App Group registration.

The v1.0 app bundle ships the main app plus Finder Sync, Quick Look, and
Thumbnail extensions. `ShareExtension` remains in the project for direct
development builds, but it is not embedded in the v1.0 app bundle.

| Target | Bundle ID / App ID | Entitlements file | Capability summary | Shipping status |
| --- | --- | --- | --- | --- |
| MacPGP | `thalesmms.MacPGP` | `MacPGP/MacPGP.entitlements` | App Sandbox, App Groups, user-selected files read-write, keychain access group | Shipped app |
| FinderSyncExtension | `thalesmms.MacPGP.FinderSyncExtension` | `FinderSyncExtension/FinderSyncExtension.entitlements` | App Sandbox, App Groups, user-selected files read-only | Shipped extension |
| QuickLookExtension | `thalesmms.MacPGP.QuickLookExtension` | `QuickLookExtension/QuickLookExtension.entitlements` | App Sandbox, App Groups, user-selected files read-only | Shipped extension |
| ThumbnailExtension | `thalesmms.MacPGP.ThumbnailExtension` | `ThumbnailExtension/ThumbnailExtension.entitlements` | App Sandbox, App Groups, user-selected files read-only | Shipped extension |
| ShareExtension | `thalesmms.MacPGP.ShareExtension` | `ShareExtension/ShareExtension.entitlements` | App Sandbox, App Groups, user-selected files read-write | Development-only target |

## Apple Developer Portal Prerequisites

The release Apple Developer account must have access to team `H4Q6WN7NV5`.
The App Group `group.com.macpgp.shared` must exist for that team.

The App IDs for all shipped targets must have the App Groups capability enabled
and must include `group.com.macpgp.shared`:

- `thalesmms.MacPGP`
- `thalesmms.MacPGP.FinderSyncExtension`
- `thalesmms.MacPGP.QuickLookExtension`
- `thalesmms.MacPGP.ThumbnailExtension`

Provisioning profiles used by Release builds must be regenerated or updated
after enabling the App Group capability. With automatic signing, Xcode can
create, update, and download those profiles when the machine is signed into an
Apple Developer account with sufficient team permissions. Command-line builds
that need Xcode to contact the Developer Portal should pass
`-allowProvisioningUpdates`.

`ShareExtension` only needs the same App Group provisioning when that
development-only target is built directly.

## New Machine Setup

1. Install Xcode and select it with `xcode-select` if multiple Xcodes are
   installed.
2. Open Xcode, sign into an Apple Developer account that belongs to team
   `H4Q6WN7NV5`, and confirm the account can manage certificates, identifiers,
   and profiles.
3. Open `MacPGP/MacPGP.xcodeproj` and inspect the Signing & Capabilities tab for
   MacPGP, FinderSyncExtension, QuickLookExtension, and ThumbnailExtension.
   The team should be `H4Q6WN7NV5`, automatic signing should be enabled, and
   App Groups should list `group.com.macpgp.shared`.
4. Run a signed build once so Xcode can create or download automatic
   provisioning profiles for the machine.
5. Confirm the build log has no provisioning errors and that Xcode still shows
   team `H4Q6WN7NV5` for every shipped target.

## Regression Build Check

Run this from the repository root when validating a machine or a signing
configuration change:

```bash
xcodebuild build \
  -project MacPGP/MacPGP.xcodeproj \
  -scheme MacPGP \
  -configuration Release \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates
```

Expected result: no provisioning profile errors and a final
`** BUILD SUCCEEDED **` line.

The unsigned CI build in `RELEASING.md` is still useful for source build
coverage, but `CODE_SIGNING_ALLOWED=NO` does not validate profiles,
certificates, App IDs, or App Groups.

## Archive Validation

The Release archive path validates the signed Release artifact and prepares the
distribution export path instead of only checking a local development build.

Create a Release archive from the command line:

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

The same archive can also be created from Xcode with Product > Archive. Use the
MacPGP scheme and Release configuration, then validate the archive in Organizer.

Inspect the signed app and embedded extensions:

```bash
APP="$ARCHIVE_PATH/Products/Applications/MacPGP.app"

for item in "$APP" "$APP/Contents/PlugIns/"*.appex; do
  echo "== $item =="
  codesign -dvvv "$item" 2>&1 | egrep 'Identifier|TeamIdentifier|Authority'
done
```

Expected result: the main app and each embedded extension show team identifier
`H4Q6WN7NV5`. The embedded extension list should include FinderSyncExtension,
QuickLookExtension, and ThumbnailExtension.

Confirm the App Group entitlement is present in the signed products:

```bash
for item in "$APP" "$APP/Contents/PlugIns/"*.appex; do
  echo "== $item =="
  codesign -d --entitlements :- "$item" 2>/dev/null | \
    grep -A3 'com.apple.security.application-groups'
done
```

Expected result: each signed product lists `group.com.macpgp.shared`.

Run the export and App Store Connect validation workflow in `RELEASING.md` to
validate the distribution handoff before cutting a stable release.
