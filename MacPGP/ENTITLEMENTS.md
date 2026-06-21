# Entitlement Rationale

This document records the retained entitlement surface for the MacPGP app and
its extensions. Each entitlement listed here should be present because shipped
runtime behavior depends on it.

## Summary

| Target | Retained entitlements | Rationale |
| --- | --- | --- |
| Main App | `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.application-groups`, `com.apple.security.network.client`, `keychain-access-groups` | Sandboxing is required for Mac App Store distribution. User-selected read/write access supports encrypt, decrypt, and sign file operations plus backup export. The app group shares key data with key-reading extensions via `keys.pgp`. The network client entitlement is required for keyserver search/fetch/upload. The Keychain access group lets stored passphrases use the macOS Data Protection keychain. |
| ShareExtension | `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. User-selected read/write access lets the extension write `.gpg` output alongside the input file. The app group lets the extension read `keys.pgp` from the shared container. |
| QuickLookExtension | `com.apple.security.app-sandbox`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. Quick Look is metadata-only in v1 (issue #136): it renders encryption metadata from the previewed file and does not decrypt or read secret-key material. Like FinderSync it remains a member of the shared app group but does not read `keys.pgp`. |
| ThumbnailExtension | `com.apple.security.app-sandbox` | Sandboxing is required for Mac App Store distribution. No file access or app group entitlement is needed because Quick Look thumbnail generation receives file content through system framework delivery. |
| FinderSyncExtension | `com.apple.security.app-sandbox`, `com.apple.security.application-groups` | Sandboxing is required for Mac App Store distribution. Finder Sync does not read `keys.pgp`, but remains a member of the shared app group. |

## Main App

The main app retains:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.files.user-selected.read-write`: required for user-driven
  encrypt, decrypt, and sign file operations, and for backup export.
- `com.apple.security.application-groups`: required to share key data with
  ShareExtension and QuickLookExtension through the shared `keys.pgp` file.
- `com.apple.security.network.client`: required for keyserver search, fetch, and
  upload (the only outbound network use; see `docs/SIGNING_REFERENCE.md`).
- `keychain-access-groups`: required for passphrase items to use
  `kSecUseDataProtectionKeychain` on macOS 10.15 and later, where
  `kSecAttrAccessibleWhenUnlocked` is honored for non-synchronizable generic
  password items.

  If this entitlement is missing in a distribution build, a **new** passphrase
  write fails closed with a typed `OperationError.keychainEntitlementMissing`
  instead of silently creating a legacy login-keychain item; the user is told
  that Keychain storage failed and the passphrase was not saved. Existing legacy
  items can still be read and are migrated to the Data Protection keychain once
  a verified copy exists. The silent legacy fallback for new writes is enabled
  only in DEBUG builds and under XCTest (which have no distribution
  entitlements) and can never activate in a normal production launch. A signed
  release-candidate smoke test that stores, retrieves, and deletes a synthetic
  passphrase, plus archive validation of the keychain access group and the
  absence of unintended `synchronizable` attributes, is part of the release
  checklist (see `docs/SIGNING_REFERENCE.md`).

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
- `com.apple.security.application-groups`: retained for app-group membership.
  Quick Look is metadata-only in v1 (issue #136) and does **not** read
  `keys.pgp` or any secret-key material; the membership is kept for parity with
  the other key-aware extensions and possible future shared-container reads.

Quick Look receives the previewed file content through system framework
delivery and reads encryption metadata directly from that file. It does not
decrypt in-preview, and it does not need user-selected file access. To decrypt,
the user opens the file in MacPGP.

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

The canonical expected entitlement set per target lives in machine-readable form
at `scripts/entitlements-manifest.json`. Run the automated check against the
signed archive before App Store submission:

```sh
scripts/check-archive-entitlements.sh --archive /path/to/MacPGP.xcarchive
```

It fails on a missing or extra App Group, missing or extra user-selected file
access, a missing Keychain access group on the app, any
`com.apple.security.get-task-allow`, and a missing or unexpected embedded
extension — for the Main App and all four extensions (Finder Sync, Quick Look,
Thumbnail, Share). The steps below remain available for manual inspection:

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
