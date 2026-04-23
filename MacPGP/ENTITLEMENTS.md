# Entitlement Rationale

This document records the retained entitlement surface for the MacPGP app and
its extensions. Each entitlement listed here should be present because shipped
runtime behavior depends on it.

## Summary

| Target | Retained entitlements | Rationale |
| --- | --- | --- |
| Main App | `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. User-selected read/write access supports encrypt, decrypt, and sign file operations plus backup export. The app group shares key data with key-reading extensions via `keys.pgp`. |
| ShareExtension | `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. User-selected read/write access lets the extension write `.gpg` output alongside the input file. The app group lets the extension read `keys.pgp` from the shared container. |
| QuickLookExtension | `com.apple.security.app-sandbox`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. The app group lets Quick Look read `keys.pgp` for in-preview decryption. |
| ThumbnailExtension | `com.apple.security.app-sandbox` | Sandboxing is required for Mac App Store distribution. No file access or app group entitlement is needed because Quick Look thumbnail generation receives file content through system framework delivery. |
| FinderSyncExtension | `com.apple.security.app-sandbox`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. Finder Sync does not read `keys.pgp`, but remains a member of the shared app group. |

## Main App

The main app retains:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.files.user-selected.read-write`: required for user-driven
  encrypt, decrypt, and sign file operations, and for backup export.
- `com.apple.security.application-groups`: required to share key data with
  ShareExtension and QuickLookExtension through the shared `keys.pgp` file.

## ShareExtension

ShareExtension retains:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.files.user-selected.read-write`: required to write `.gpg`
  output alongside the input file selected through the share workflow.
- `com.apple.security.application-groups`: required to read `keys.pgp` from the
  shared app group container.

## QuickLookExtension

QuickLookExtension retains:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.application-groups`: required to read `keys.pgp` from the
  shared app group container for in-preview decryption.

Quick Look still receives the previewed file content through system framework
delivery. It does not need user-selected file access.

## Other System-Delivered Extensions

ThumbnailExtension retains only:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.

FinderSyncExtension retains:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.application-groups`: retained for shared app group
  membership. FinderSyncExtension does not read `keys.pgp`.

These extensions do not need user-selected file access. Their file context is
delivered by system frameworks.

## Distribution Archive Validation

Validate the final entitlements from a distribution-style archive before App
Store submission:

1. In Xcode, select the Release configuration and archive the app with
   Product > Archive.
2. Locate the archived `.xcarchive` in the Organizer or in
   `~/Library/Developer/Xcode/Archives/`.
3. Extract the embedded entitlements from the archived app bundle:

   ```sh
   codesign -d --entitlements :- "/path/to/MacPGP.xcarchive/Products/Applications/MacPGP.app"
   ```

4. Extract the embedded entitlements from each archived extension bundle inside
   `MacPGP.app/Contents/PlugIns/`:

   ```sh
   codesign -d --entitlements :- "/path/to/MacPGP.xcarchive/Products/Applications/MacPGP.app/Contents/PlugIns/ShareExtension.appex"
   codesign -d --entitlements :- "/path/to/MacPGP.xcarchive/Products/Applications/MacPGP.app/Contents/PlugIns/QuickLookExtension.appex"
   codesign -d --entitlements :- "/path/to/MacPGP.xcarchive/Products/Applications/MacPGP.app/Contents/PlugIns/ThumbnailExtension.appex"
   codesign -d --entitlements :- "/path/to/MacPGP.xcarchive/Products/Applications/MacPGP.app/Contents/PlugIns/FinderSyncExtension.appex"
   ```

5. Confirm `com.apple.security.get-task-allow` is absent from every target.
6. Confirm each target's embedded entitlements match the rationale and summary
   table above.
7. Optionally validate the archive through Xcode's Validate App workflow or
   Transporter before uploading to App Store Connect.
