# MacPGP Release QA Matrix

Release target: MacPGP v1.0 App Store build
Document version: 0.1
Last updated: 2026-04-18
Scope reference: `docs/V1_SCOPE.md`

This guide is the release-grade manual test matrix for MacPGP features that require manual verification because they depend on macOS system integration, Finder extensions, Keychain, notifications, local files, or install state.

## QA Sign-Off

- [ ] QA lead reviewed the release scope before testing
- [ ] QA lead confirmed all required install states were tested
- [ ] QA lead confirmed all required keyring states were tested
- [ ] QA lead confirmed critical findings are linked as GitHub issues
- [ ] QA lead approved this run for release consideration

QA lead:
Date:
Release build/archive:

## Test Execution Tracking

Use this table as the live run log. Each row must cover exactly one Install State and Keyring State combination. Duplicate Test IDs are intentional when a suite must be repeated across states; add more rows for repeated runs, platform variants, or bug retests.

| Test ID | Feature Area | Install State | Keyring State | Result | Tester | Date | Linked Issues |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IS-FRESH | Fresh install verification | Fresh | Empty |  |  |  |  |
| IS-UPGRADE | Upgrade install verification | Upgrade | Populated |  |  |  |  |
| KS-EMPTY | Keyring state: empty | Fresh | Empty |  |  |  |  |
| KS-EMPTY | Keyring state: empty | Upgrade | Empty |  |  |  |  |
| KS-POPULATED | Keyring state: populated | Fresh | Populated |  |  |  |  |
| KS-POPULATED | Keyring state: populated | Upgrade | Populated |  |  |  |  |
| CORE-KEY | Key management | Fresh | Empty |  |  |  |  |
| CORE-KEY | Key management | Fresh | Populated |  |  |  |  |
| CORE-KEY | Key management | Upgrade | Empty |  |  |  |  |
| CORE-KEY | Key management | Upgrade | Populated |  |  |  |  |
| CORE-ENCDEC | Encryption and decryption | Fresh | Empty |  |  |  |  |
| CORE-ENCDEC | Encryption and decryption | Fresh | Populated |  |  |  |  |
| CORE-ENCDEC | Encryption and decryption | Upgrade | Empty |  |  |  |  |
| CORE-ENCDEC | Encryption and decryption | Upgrade | Populated |  |  |  |  |
| CORE-SIGNVERIFY | Sign and verify screens | Fresh | Empty |  |  |  |  |
| CORE-SIGNVERIFY | Sign and verify screens | Fresh | Populated |  |  |  |  |
| CORE-SIGNVERIFY | Sign and verify screens | Upgrade | Empty |  |  |  |  |
| CORE-SIGNVERIFY | Sign and verify screens | Upgrade | Populated |  |  |  |  |
| CORE-KEYSERVER | Keyserver operations | Fresh | Populated |  |  |  |  |
| CORE-KEYSERVER | Keyserver operations | Upgrade | Populated |  |  |  |  |
| CORE-SETTINGS | Settings and preferences | Fresh | Empty |  |  |  |  |
| CORE-SETTINGS | Settings and preferences | Fresh | Populated |  |  |  |  |
| CORE-SETTINGS | Settings and preferences | Upgrade | Empty |  |  |  |  |
| CORE-SETTINGS | Settings and preferences | Upgrade | Populated |  |  |  |  |
| CORE-SVC-DEC | Services: decrypt | Fresh | Empty |  |  |  |  |
| CORE-SVC-DEC | Services: decrypt | Fresh | Populated |  |  |  |  |
| CORE-SVC-DEC | Services: decrypt | Upgrade | Empty |  |  |  |  |
| CORE-SVC-DEC | Services: decrypt | Upgrade | Populated |  |  |  |  |
| CORE-SVC-SIGN | Services: sign | Fresh | Empty |  |  |  |  |
| CORE-SVC-SIGN | Services: sign | Fresh | Populated |  |  |  |  |
| CORE-SVC-SIGN | Services: sign | Upgrade | Empty |  |  |  |  |
| CORE-SVC-SIGN | Services: sign | Upgrade | Populated |  |  |  |  |
| CORE-BACKUP | Backup and restore | Fresh | Populated |  |  |  |  |
| CORE-BACKUP | Backup and restore | Upgrade | Populated |  |  |  |  |
| EXT-FINDER | FinderSyncExtension | Fresh | Empty |  |  |  |  |
| EXT-FINDER | FinderSyncExtension | Fresh | Populated |  |  |  |  |
| EXT-FINDER | FinderSyncExtension | Upgrade | Empty |  |  |  |  |
| EXT-FINDER | FinderSyncExtension | Upgrade | Populated |  |  |  |  |
| EXT-QL | QuickLookExtension | Fresh | Empty |  |  |  |  |
| EXT-QL | QuickLookExtension | Fresh | Populated |  |  |  |  |
| EXT-QL | QuickLookExtension | Upgrade | Empty |  |  |  |  |
| EXT-QL | QuickLookExtension | Upgrade | Populated |  |  |  |  |
| EXT-THUMB | ThumbnailExtension | Fresh | Empty |  |  |  |  |
| EXT-THUMB | ThumbnailExtension | Fresh | Populated |  |  |  |  |
| EXT-THUMB | ThumbnailExtension | Upgrade | Empty |  |  |  |  |
| EXT-THUMB | ThumbnailExtension | Upgrade | Populated |  |  |  |  |
| EXT-SHARE | ShareExtension exclusion | Release candidate | N/A |  |  |  |  |
| EXT-CROSS | Cross-extension data flow | Fresh | Empty |  |  |  |  |
| EXT-CROSS | Cross-extension data flow | Fresh | Populated |  |  |  |  |
| EXT-CROSS | Cross-extension data flow | Upgrade | Empty |  |  |  |  |
| EXT-CROSS | Cross-extension data flow | Upgrade | Populated |  |  |  |  |
| CROSS-E2E | Full encrypt/decrypt/sign workflow | Fresh | Populated |  |  |  |  |
| CROSS-E2E | Full encrypt/decrypt/sign workflow | Upgrade | Populated |  |  |  |  |
| CROSS-BACKUP | Backup/restore integration | Fresh | Populated |  |  |  |  |
| CROSS-BACKUP | Backup/restore integration | Fresh | Restored |  |  |  |  |
| CROSS-BACKUP | Backup/restore integration | Upgrade | Populated |  |  |  |  |
| CROSS-BACKUP | Backup/restore integration | Upgrade | Restored |  |  |  |  |
| CROSS-KNOWN | Known issue verification | Fresh | Empty |  |  |  |  |
| CROSS-KNOWN | Known issue verification | Fresh | Populated |  |  |  |  |
| CROSS-KNOWN | Known issue verification | Upgrade | Empty |  |  |  |  |
| CROSS-KNOWN | Known issue verification | Upgrade | Populated |  |  |  |  |
| CROSS-SVC | Cross-app Services and shortcuts | Fresh | Populated |  |  |  |  |
| CROSS-SVC | Cross-app Services and shortcuts | Upgrade | Populated |  |  |  |  |
| QA-BUGS | Bugs found and sign-off | Release candidate | Empty |  |  |  |  |
| QA-BUGS | Bugs found and sign-off | Release candidate | Populated |  |  |  |  |
| QA-BUGS | Bugs found and sign-off | Release candidate | Restored |  |  |  |  |

## Legend and Bug Linking

- Result values: use `Pass`, `Fail`, `Blocked`, or `Not run`.
- Pass: mark `Pass` when every expected result in the test case succeeds.
- Fail: mark `Fail` when any expected result does not succeed, then link the bug.
- Blocked: mark `Blocked` when setup, signing, provisioning, OS state, or missing test data prevents execution.
- Not run: mark `Not run` only when the row is outside the approved test scope for that run.
- Linked Issues: use GitHub issue references such as `#14` or full issue URLs. New bug reports should follow the structure used in `docs/app-store-v1-detailed-issues.md`: Summary, Current repo evidence, What needs to happen, and Acceptance criteria.
- Retests: add a new tracking row instead of overwriting the original failed row, and link both the bug and fixing PR where applicable.

---

## Part 1: Prerequisites

### 1.1 Environment

1. Use a macOS system with Xcode installed.
2. Build and run the MacPGP app from the release candidate source or archive under test.
3. For notification delivery checks, start with MacPGP unset in System Settings > Notifications when possible, then allow notifications only when the in-context prompt appears during the test.
4. Confirm the shared App Group identifier is `group.com.macpgp.shared`.
5. Confirm the primary app keyring path is `~/Library/Application Support/MacPGP/Keyring/`.
6. Confirm the extension-visible keyring projection is `~/Library/Group Containers/group.com.macpgp.shared/keys.pgp`.

### 1.2 Build Instructions

```bash
# From the repository root
open MacPGP/MacPGP.xcodeproj

# In Xcode:
# 1. Select the MacPGP scheme
# 2. Product > Build (Cmd+B)
# 3. Product > Run (Cmd+R)
```

For a built local app, prefer the Release candidate bundle under test:

```bash
APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"
open "$APP_BUNDLE"
```

### 1.3 Services Setup

If Services do not appear after launching MacPGP:

```bash
# Flush Services cache
/System/Library/CoreServices/pbs -flush

# Relaunch MacPGP
APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"
open "$APP_BUNDLE"

# Wait 5-10 seconds for registration
```

### 1.4 State Setup Checklist

Run this checklist before each major section, then record the chosen state in the tracking table.

- [ ] Install state selected: Fresh or Upgrade
- [ ] Keyring state selected: Empty or Populated
- [ ] App was launched once after state setup
- [ ] App did not crash on launch
- [ ] Application Support keyring state matches the selected scenario
- [ ] App Group `keys.pgp` state matches the selected scenario
- [ ] Preferences state matches the selected scenario
- [ ] Any deviations are linked in the tracking table

### 1.5 Keyring Reset Procedure

> **Destructive reset warning:** `--reset-keyring` deletes local keyring state for the selected app profile. Run it only on disposable test profiles or CI agents. Back up test fixtures and any important keys before using this launch argument.

Use the `--reset-keyring` launch argument when a test requires a clean keyring. This argument is already used by the UI test suite and should reset local test keyring state for manual QA runs.

From a built app bundle:

```bash
APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"
"$APP_BUNDLE/Contents/MacOS/MacPGP" --reset-keyring
```

Or through `open`:

```bash
APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"
open "$APP_BUNDLE" --args --reset-keyring
```

After reset:

- [ ] Relaunch MacPGP normally.
- [ ] Confirm no keys are listed.
- [ ] Confirm decrypt and sign flows behave as Empty Keyring scenarios describe.
- [ ] Confirm App Group `keys.pgp` is absent, empty, or contains no usable keys.

### 1.6 Empty Keyring Definition

An Empty Keyring state means:

- No public keys are listed in MacPGP.
- No secret keys are listed in MacPGP.
- `~/Library/Application Support/MacPGP/Keyring/` has no usable key material.
- `~/Library/Group Containers/group.com.macpgp.shared/keys.pgp` is absent, empty, or contains no usable keys.

Expected behavior:

- [ ] Encrypt recipient selection is disabled or shows an actionable no-recipient state.
- [ ] Decrypt operations are unavailable or fail with a clear no-secret-key message.
- [ ] Sign operations are unavailable or fail with a clear no-secret-key message.
- [ ] Verify operations that require only public keys explain that no matching public key is available.
- [ ] Extensions fail gracefully when shared key data is missing.

### 1.7 Populated Keyring Definition

A Populated Keyring state means the keyring contains, at minimum:

- One RSA keypair with a known test passphrase.
- The keypair passphrase stored in Keychain for flows that support saved credentials.
- One imported public key for a different recipient.
- One expired key for edge case testing.
- A synced App Group projection at `group.com.macpgp.shared/keys.pgp` after app launch or keyring save.

Expected behavior:

- [ ] Encrypt recipient selection includes the imported public key.
- [ ] Decrypt can use the local secret key when the message targets that key.
- [ ] Sign can use the local secret key with the correct passphrase or saved Keychain credential.
- [ ] Verify can validate signatures when the matching public key is present.
- [ ] Extensions can read shared key data where supported by the extension.

---

## Part 2: Install State Tests

### IS-FRESH: Fresh Install

Use this scenario for first-run behavior with no previous MacPGP data.

#### Setup

1. Quit MacPGP.
2. Remove or move any existing `~/Library/Application Support/MacPGP/` directory.
3. Remove or move `~/Library/Group Containers/group.com.macpgp.shared/keys.pgp`.
4. Reset MacPGP preferences for the test account if this run requires a fully clean preference state.
5. Install or launch the release candidate app.

#### Verification

- [ ] Before first launch, `~/Library/Application Support/MacPGP/` does not exist.
- [ ] Before first launch, the App Group container has no `keys.pgp` file.
- [ ] App launches without crash.
- [ ] Empty keyring state is shown clearly.
- [ ] Keyring directory is created only as needed and contains no usable keys.
- [ ] Preferences use release defaults.
- [ ] App Group `keys.pgp` remains absent, empty, or contains no usable keys until key material is created.
- [ ] Empty Keyring expected behavior passes.

### IS-UPGRADE: Upgrade Install

Use this scenario for replacing an older v0.x or previous release candidate app while preserving user data.

#### Setup

1. Start from an existing v0.x or previous release candidate installation.
2. Confirm the existing app has a Populated Keyring state.
3. Confirm existing preferences are configured to known non-default values where possible.
4. Quit MacPGP.
5. Preserve `~/Library/Application Support/MacPGP/`.
6. Preserve `~/Library/Group Containers/group.com.macpgp.shared/` when present.
7. Replace the old app bundle with the release candidate app bundle.
8. Launch the release candidate app.

#### Verification

- [ ] App launches without crash.
- [ ] Existing public keys are still listed.
- [ ] Existing secret keys are still listed.
- [ ] Existing passphrase behavior is preserved as expected.
- [ ] Existing preferences are preserved as expected.
- [ ] App Group `keys.pgp` is refreshed after launch or the next keyring save.
- [ ] Existing encrypted/decrypted/sign/verify workflows still work.
- [ ] No data migration or compatibility issue is observed.

---

## Part 3: Core App Features

### CORE-KEY: Key Management

Run these tests in both Empty Keyring and Populated Keyring states where applicable. After every key mutation, confirm the main keyring view and the App Group projection stay consistent.

#### CORE-KEY-1.1 through 1.3: Generate RSA Key (2048, 3072, and 4096 Bits)

Repeat these steps for each key size. Use a unique name and email address per run.

**Steps:**

1. Use the Empty Keyring or Populated Keyring state.
2. Open Keyring.
3. Click "Generate New Key".
4. Enter a unique full name and email address.
5. Set Algorithm to RSA.
6. Set Key Size to the target size: `2048 bits`, `3072 bits`, or `4096 bits`.
7. Enter and confirm a strong test passphrase.
8. Click "Generate".
9. Click "Done" after the success screen appears.

**Expected:**

- [ ] For all sizes, "Generate New Key" opens without errors.
- [ ] For all sizes, RSA and the target key size can be selected.
- [ ] For all sizes, Generate remains disabled until required fields are valid.
- [ ] For all sizes, the success screen appears.
- [ ] For all sizes, the new key appears in Keyring.
- [ ] For all sizes, key details show the generated identity, key ID, and fingerprint.
- [ ] For all sizes, export and signing actions are available for the generated secret key.
- [ ] For all sizes, App Group `keys.pgp` is refreshed after the keyring save.
- [ ] For 4096-bit generation, a progress indicator appears while the key is generated.

#### CORE-KEY-1.4: Passphrase Validation

**Steps:**

1. Open "Generate New Key".
2. Fill the identity fields.
3. Enter a weak passphrase such as `abc`.
4. Confirm the passphrase with the same value.
5. Change Confirm Passphrase to a different value.
6. Restore matching passphrases.

**Expected:**

- [ ] Passphrase strength feedback appears for weak input.
- [ ] Weak passphrase state is visible enough for the tester to identify.
- [ ] "Passphrases do not match" appears when the fields differ.
- [ ] Generate is disabled while passphrases differ.
- [ ] Generate becomes available again when all required validation passes.

#### CORE-KEY-1.5: Expiration, Comment, and Keychain Storage

**Steps:**

1. Open "Generate New Key".
2. Fill full name and email address.
3. Enter `Manual QA comment` in "Comment (optional)".
4. Turn off "Never expires".
5. Select an expiration value such as `1 year`.
6. Enable "Store passphrase in Keychain".
7. Generate the key.
8. Open the generated key details.

**Expected:**

- [ ] Optional comment is accepted.
- [ ] Expiration picker appears when "Never expires" is off.
- [ ] Selected expiration is reflected in the generated key details.
- [ ] Success screen confirms "Passphrase stored in Keychain".
- [ ] Comment appears in key details or exported user ID where supported.
- [ ] App Group `keys.pgp` is refreshed after the keyring save.

#### CORE-KEY-2.1: Import ASCII-Armored Public Key

**Steps:**

1. Start from a test `.asc` public key file containing an ASCII-armored public key begin marker, such as `BEGIN PGP PUBLIC KEY BLOCK (example marker)`.
2. In Keyring, click "Import Key" or use the app import flow.
3. Select the public key file.
4. Confirm import.

**Expected:**

- [ ] File picker accepts the `.asc` file.
- [ ] Import completes without passphrase prompt.
- [ ] Imported public key appears in Keyring.
- [ ] Key can be selected as an encryption recipient.
- [ ] App Group `keys.pgp` is refreshed after the import.

#### CORE-KEY-2.2: Import ASCII-Armored Secret Key

**Steps:**

1. Start from a test `.asc` secret key file containing an ASCII-armored secret key begin marker, such as `BEGIN PGP PRIVATE KEY BLOCK (example marker)`.
2. In Keyring, click "Import Key" or use the app import flow.
3. Select the secret key file.
4. Enter the key passphrase if prompted.
5. Confirm import.

**Expected:**

- [ ] File picker accepts the `.asc` file.
- [ ] Passphrase prompt appears when the imported key requires it.
- [ ] Imported secret key appears in Keyring.
- [ ] Sign and decrypt actions are available for the key.
- [ ] App Group `keys.pgp` is refreshed after the import.

#### CORE-KEY-2.3: Import Binary Keyring File

**Steps:**

1. Prepare a binary OpenPGP keyring file such as `pubring.gpg`, `secring.gpg`, or a binary exported key.
2. In Keyring, click "Import Key" or use the app import flow.
3. Select the binary keyring file.
4. Confirm import.

**Expected:**

- [ ] Binary OpenPGP key data is accepted.
- [ ] Imported keys appear in Keyring.
- [ ] Secret keys are identified as secret keys when present.
- [ ] Duplicate keys are handled without duplicate visible rows.
- [ ] App Group `keys.pgp` is refreshed after the import.

#### CORE-KEY-2.4: Invalid or Corrupted Key Import

**Steps:**

1. Create a text file that is not OpenPGP key data.
2. Rename it with a supported extension such as `.asc`.
3. In Keyring, click "Import Key" or use the app import flow.
4. Select the invalid file.
5. Repeat with a truncated or corrupted key file.

**Expected:**

- [ ] Import fails with a clear error.
- [ ] No partial key appears in Keyring.
- [ ] Existing keys remain unchanged.
- [ ] App does not crash.
- [ ] App Group `keys.pgp` is not replaced with invalid data.

#### CORE-KEY-3.1: Export Public Key Only

**Steps:**

1. Use a Populated Keyring state.
2. Right-click a key.
3. Select "Export Public Key...".
4. Save to a known destination.
5. Open the exported file in a text editor.

**Expected:**

- [ ] Save panel appears.
- [ ] Public key export succeeds.
- [ ] Exported file contains an ASCII-armored public key begin marker, such as `BEGIN PGP PUBLIC KEY BLOCK (example marker)`.
- [ ] Exported file does not contain private key material.
- [ ] Exported key can be imported into a clean keyring as a public key.

#### CORE-KEY-3.2: Export Secret Key

**Steps:**

1. Use a Populated Keyring state with at least one secret key.
2. Right-click a secret key.
3. Select "Export Secret Key...".
4. Enter the key passphrase if prompted.
5. Save to a known destination.
6. Open the exported file in a text editor.

**Expected:**

- [ ] "Export Secret Key..." is available only for secret keys.
- [ ] Passphrase is required when the app needs to unlock the secret key.
- [ ] Exported file contains an ASCII-armored secret key begin marker, such as `BEGIN PGP PRIVATE KEY BLOCK (example marker)`.
- [ ] Exported secret key can be imported into a clean keyring.
- [ ] No secret key is uploaded or exposed through a public-key-only flow.

#### CORE-KEY-3.3: Export to Custom Location

**Steps:**

1. Right-click any exportable key.
2. Select "Export Public Key..." or "Export Secret Key...".
3. Choose a custom folder outside Desktop.
4. Change the default filename.
5. Save the file.

**Expected:**

- [ ] Save panel allows a custom destination.
- [ ] Save panel allows a custom filename.
- [ ] File is written to the selected folder.
- [ ] App reports export failure clearly if the destination is not writable.

#### CORE-KEY-3.4: Copy Key ID and Fingerprint

**Steps:**

1. Use a Populated Keyring state.
2. Right-click a key in Keyring.
3. Select "Copy Key ID".
4. Paste into TextEdit.
5. Right-click the same key.
6. Select "Copy Fingerprint".
7. Paste into TextEdit.

**Expected:**

- [ ] "Copy Key ID" places the short key ID on the clipboard.
- [ ] "Copy Fingerprint" places the full fingerprint on the clipboard.
- [ ] Clipboard values match the selected key.
- [ ] Copy actions do not alter the keyring.

#### CORE-KEY-4.1: Delete Key With Confirmation

**Steps:**

1. Use a Populated Keyring state.
2. Select a disposable test key.
3. Right-click the key and select "Delete Key".
4. Cancel the confirmation dialog.
5. Repeat and confirm deletion.
6. Relaunch MacPGP.

**Expected:**

- [ ] Confirmation dialog names the selected key.
- [ ] Cancel leaves the key in Keyring.
- [ ] Confirm removes the key from Keyring.
- [ ] Deleted key remains absent after relaunch.
- [ ] App Group `keys.pgp` is refreshed and no longer contains the deleted key.
- [ ] Dependent extension behavior reflects the deletion after sync.

### CORE-ENCDEC: Encryption and Decryption

#### CORE-ENCDEC-1.1: Text Encryption for Single Recipient

**Steps:**

1. Use a Populated Keyring state with at least one imported public key.
2. Open Encrypt.
3. Set Mode to Text.
4. Select one recipient.
5. Enter a plaintext message.
6. Enable Armor.
7. Click "Encrypt".

**Expected:**

- [ ] Recipient can be selected.
- [ ] Encryption succeeds.
- [ ] Output starts with an ASCII-armored PGP message begin marker, such as `BEGIN PGP MESSAGE (example marker)`.
- [ ] Output can be decrypted by the matching secret key.

#### CORE-ENCDEC-1.2: Text Encryption for Multiple Recipients

**Steps:**

1. Use a Populated Keyring state with at least two public recipient keys.
2. Open Encrypt.
3. Set Mode to Text.
4. Select multiple recipients.
5. Enter a plaintext message.
6. Click "Encrypt".
7. Attempt decryption with each matching recipient secret key.

**Expected:**

- [ ] Multiple recipients can be selected.
- [ ] Selected recipient count is visible.
- [ ] Encryption succeeds.
- [ ] Each intended recipient can decrypt the message.
- [ ] Non-recipient secret keys cannot decrypt the message.

#### CORE-ENCDEC-1.3: Text Encryption With Optional Signing

**Steps:**

1. Use a Populated Keyring state with one recipient public key and one local secret key.
2. Open Encrypt.
3. Set Mode to Text.
4. Select a recipient.
5. Select a key in "Sign with (optional)".
6. Enter a plaintext message.
7. Click "Encrypt".
8. Decrypt and verify the signed output where supported.

**Expected:**

- [ ] Signing key picker lists available secret keys.
- [ ] "Don't sign" remains available.
- [ ] App prompts for signer passphrase when needed.
- [ ] Encryption succeeds with signing enabled.
- [ ] Decrypted result can be verified as signed by the selected key where supported.

#### CORE-ENCDEC-1.4: ASCII Armor Toggle, Clipboard Text Flow, and Notification Opt-In

**Steps:**

1. Start from a fresh install or reset MacPGP notification permission so the system state is "Not Determined".
2. Launch MacPGP and confirm no notification permission prompt appears on launch.
3. Copy plaintext from TextEdit.
4. Paste it into Encrypt > Text mode.
5. Select one recipient.
6. Turn Armor on and encrypt.
7. Copy the encrypted output.
8. Paste the output into TextEdit and confirm ASCII-armored text.
9. Trigger "Encrypt from Clipboard" from the toolbar or menu.
10. Confirm the macOS notification permission prompt appears during this clipboard action.
11. Repeat the clipboard encrypt or decrypt action with notification permission denied.
12. Repeat with Armor off.

**Expected:**

- [ ] Pasted clipboard input is preserved in the message field.
- [ ] Armor on produces ASCII-armored output.
- [ ] Armor off produces non-armored output or a clearly documented binary handling path.
- [ ] Output can be copied and pasted without truncation.
- [ ] Notification permission is requested only after the first notification-worthy clipboard action, not on app launch.
- [ ] If notification permission is denied, clipboard encrypt and decrypt operations still complete without crashing.
- [ ] If notification permission is denied, notification delivery fails silently from the user's perspective and in-app output remains available.

#### CORE-ENCDEC-1.5: File Encryption for a Single File

**Steps:**

1. Create a small plaintext file.
2. Open Encrypt.
3. Set Mode to File.
4. Add the plaintext file.
5. Select one recipient.
6. Choose an output location.
7. Click "Encrypt".

**Expected:**

- [ ] File can be selected or dropped.
- [ ] Output location can be selected.
- [ ] Progress indicator appears while encryption runs.
- [ ] Encrypted file is written to the chosen location.
- [ ] Encrypted file can be decrypted successfully.

#### CORE-ENCDEC-1.6: File Encryption for Multiple Files

**Steps:**

1. Prepare at least three plaintext files.
2. Open Encrypt.
3. Set Mode to File.
4. Add all files.
5. Select one or more recipients.
6. Choose an output location.
7. Click "Encrypt".

**Expected:**

- [ ] Multiple files can be selected or dropped.
- [ ] Each file is listed before encryption.
- [ ] Progress reflects multi-file work.
- [ ] Each encrypted output file is created.
- [ ] Each encrypted output file can be decrypted.

#### CORE-ENCDEC-1.7: Large File Encryption

**Steps:**

1. Create or select a plaintext file larger than 10 MB.
2. Open Encrypt.
3. Set Mode to File.
4. Add the large file.
5. Select a recipient and output location.
6. Click "Encrypt".

**Expected:**

- [ ] App remains responsive while processing.
- [ ] Progress indicator or status text updates.
- [ ] Output file is created without truncation.
- [ ] Output file decrypts to the original content.
- [ ] No memory or timeout failure occurs.

#### CORE-ENCDEC-1.8: Empty Keyring Encryption Edge Case

**Steps:**

1. Use the Empty Keyring state.
2. Open Encrypt.
3. Set Mode to Text.
4. Enter plaintext.
5. Attempt to choose recipients and encrypt.

**Expected:**

- [ ] Recipient area explains that recipient public keys must be imported first.
- [ ] Encrypt action is disabled or fails with a clear no-recipient message.
- [ ] App does not crash.
- [ ] No output is produced.

#### CORE-ENCDEC-2.1: Text Decryption With Correct Passphrase

**Steps:**

1. Use a Populated Keyring state.
2. Prepare an encrypted message for the local secret key.
3. Open Decrypt.
4. Set Mode to Text.
5. Keep Auto-detect enabled.
6. Paste the encrypted message.
7. Click "Decrypt".
8. Enter the correct passphrase if prompted.

**Expected:**

- [ ] App auto-detects a matching secret key or tries available secret keys.
- [ ] Correct passphrase decrypts successfully.
- [ ] Decrypted output matches the original plaintext.
- [ ] No extra encrypted content remains in the output.

#### CORE-ENCDEC-2.2: Text Decryption With Wrong Passphrase

**Steps:**

1. Use a Populated Keyring state.
2. Paste a message encrypted for the local secret key.
3. Click "Decrypt".
4. Enter an incorrect passphrase.

**Expected:**

- [ ] Decryption fails with a clear passphrase or decrypt error.
- [ ] Original encrypted input remains available.
- [ ] No partial plaintext is shown.
- [ ] Tester can retry or cancel.

#### CORE-ENCDEC-2.3: Text Decryption With No Matching Secret Key

**Steps:**

1. Use a Populated Keyring state that does not contain the recipient secret key.
2. Paste an encrypted message for a different key.
3. Keep Auto-detect enabled.
4. Click "Decrypt".

**Expected:**

- [ ] App reports that no matching secret key is available or decryption failed clearly.
- [ ] App does not suggest the wrong key as successful.
- [ ] No plaintext is shown.

#### CORE-ENCDEC-2.4: File Decryption for `.gpg`, `.pgp`, and `.asc`

**Steps:**

1. Prepare encrypted files with `.gpg`, `.pgp`, and `.asc` extensions.
2. Open Decrypt.
3. Set Mode to File.
4. Add each file one at a time.
5. Choose an output location.
6. Click "Decrypt".
7. Enter the correct passphrase if prompted.

**Expected:**

- [ ] `.gpg` files decrypt successfully.
- [ ] `.pgp` files decrypt successfully.
- [ ] ASCII-armored `.asc` encrypted files decrypt successfully.
- [ ] Output files are written to the selected location.
- [ ] Output content matches the original plaintext or original file bytes.

#### CORE-ENCDEC-2.5: Auto-Detect Toggle and Manual Key Selection

**Steps:**

1. Use a Populated Keyring state with more than one secret key.
2. Open Decrypt.
3. Turn Auto-detect off.
4. Select a specific key in "Select Key".
5. Decrypt a message for that key.
6. Repeat with the wrong key selected.

**Expected:**

- [ ] Turning Auto-detect off reveals manual key selection.
- [ ] Correct manual key decrypts successfully.
- [ ] Wrong manual key fails clearly.
- [ ] Turning Auto-detect back on hides or bypasses manual selection and tries available secret keys.

#### CORE-ENCDEC-2.6: Empty Keyring Decryption Edge Case

**Steps:**

1. Use the Empty Keyring state.
2. Open Decrypt.
3. Set Mode to Text.
4. Paste an encrypted message.
5. Click "Decrypt" if available.

**Expected:**

- [ ] Decryption key area shows "No secret keys available for decryption" or equivalent.
- [ ] Decrypt action is disabled or fails with a clear no-secret-key message.
- [ ] App does not crash.
- [ ] No plaintext is shown.

### CORE-SIGNVERIFY: Sign and Verify Screens

#### CORE-SIGNVERIFY-1.1: Cleartext Signature

**Steps:**

1. Use a Populated Keyring state with at least one secret key.
2. Open Sign.
3. Set Mode to Text.
4. Enable Cleartext.
5. Leave Detached off.
6. Enable Armor.
7. Select a signing key.
8. Enter a plaintext message.
9. Click "Sign".
10. Enter the passphrase if prompted.

**Expected:**

- [ ] Signing key can be selected.
- [ ] Signed output starts with an ASCII-armored signed message begin marker, such as `BEGIN PGP SIGNED MESSAGE (example marker)`.
- [ ] Original message remains readable in the signed output.
- [ ] Signature block is present.

#### CORE-SIGNVERIFY-1.2: Inline Signature

**Steps:**

1. Open Sign.
2. Set Mode to Text.
3. Turn Cleartext off.
4. Leave Detached off.
5. Select a signing key.
6. Enter a plaintext message.
7. Click "Sign".

**Expected:**

- [ ] Inline signed output is produced.
- [ ] Armor setting controls whether output is ASCII-armored.
- [ ] Output can be verified by the Verify screen.
- [ ] Original input remains available if signing fails.

#### CORE-SIGNVERIFY-1.3: Detached Signature

**Steps:**

1. Open Sign.
2. Set Mode to Text.
3. Enable Detached.
4. Select a signing key.
5. Enter a plaintext message.
6. Click "Sign".

**Expected:**

- [ ] Output is a detached signature rather than a signed message.
- [ ] Armor on produces an ASCII-armored signature begin marker, such as `BEGIN PGP SIGNATURE (example marker)`.
- [ ] Detached signature verifies with the original message.

#### CORE-SIGNVERIFY-1.4: ASCII Armor Output

**Steps:**

1. Open Sign.
2. Set Mode to Text.
3. Select a signing key.
4. Enter a plaintext message.
5. Sign once with Armor enabled.
6. Sign again with Armor disabled.

**Expected:**

- [ ] Armor enabled produces ASCII-armored output.
- [ ] Armor disabled produces binary or non-armored output through a documented handling path.
- [ ] Both outputs verify successfully through supported verify flows.

#### CORE-SIGNVERIFY-1.5: File Signing

**Steps:**

1. Prepare a plaintext file.
2. Open Sign.
3. Set Mode to File.
4. Select the file.
5. Select a signing key.
6. Test both inline and detached signing where supported.
7. Click "Sign".

**Expected:**

- [ ] File can be selected or dropped.
- [ ] Signed file or signature file is written to the expected location.
- [ ] Progress or status appears during signing.
- [ ] Signed output verifies successfully.

#### CORE-SIGNVERIFY-1.6: Empty Keyring Sign Edge Case

**Steps:**

1. Use the Empty Keyring state.
2. Open Sign.
3. Set Mode to Text.
4. Enter a plaintext message.

**Expected:**

- [ ] Sign screen shows "No secret keys available for signing" or equivalent.
- [ ] Sign action is disabled or fails with a clear no-secret-key message.
- [ ] App does not crash.

#### CORE-SIGNVERIFY-2.1: Verify Valid Inline Signature With Known Signer

**Steps:**

1. Use a Populated Keyring state with the signer's public key present.
2. Create or obtain a valid inline signed message.
3. Open Verify.
4. Set Mode to Text.
5. Set Signature to Inline.
6. Paste the signed message.
7. Click "Verify".

**Expected:**

- [ ] Verification result is "Signature Valid".
- [ ] Result message clearly indicates success.
- [ ] Signer attribution appears when the signer public key is in the keyring.
- [ ] If signer attribution is missing, link known issue `#9`.

#### CORE-SIGNVERIFY-2.2: Verify Valid Detached Signature

**Steps:**

1. Use a Populated Keyring state with the signer's public key present.
2. Prepare an original message or file and its detached signature.
3. Open Verify.
4. Select Detached signature mode.
5. Provide the original content and detached signature.
6. Click "Verify".

**Expected:**

- [ ] Verification result is "Signature Valid".
- [ ] App pairs the detached signature with the original content.
- [ ] Signer attribution appears when the signer public key is in the keyring.
- [ ] Verification fails clearly if the original content and signature do not match.

#### CORE-SIGNVERIFY-2.3: Tampered Message Detection

**Steps:**

1. Start with a valid signed message.
2. Change one character in the signed content without changing the signature.
3. Open Verify.
4. Verify the tampered message.

**Expected:**

- [ ] Verification result is "Signature Invalid".
- [ ] App does not show success styling.
- [ ] Error wording distinguishes an invalid signature from an app or parsing error.
- [ ] If invalid signature and operational errors are conflated, link known issue `#43`.

#### CORE-SIGNVERIFY-2.4: Unknown Signer

**Steps:**

1. Remove the signer's public key or use a clean keyring without it.
2. Open Verify.
3. Verify a signature that is cryptographically valid but signed by the missing public key.

**Expected:**

- [ ] App reports that signer information is unavailable or unknown.
- [ ] App does not attribute the signature to the wrong local key.
- [ ] Validity, unknown signer, and missing public key states are clearly distinguishable.
- [ ] Importing the signer public key and retrying improves attribution.

#### CORE-SIGNVERIFY-2.5: Verify With Only Public Keys

**Steps:**

1. Use a keyring that contains public keys but no secret keys.
2. Open Verify.
3. Verify a valid signed message from one of the public keys.
4. Open Sign and inspect signing availability.

**Expected:**

- [ ] Verify works with only public keys.
- [ ] Sign remains unavailable without secret keys.
- [ ] App clearly separates verify requirements from sign requirements.

### CORE-KEYSERVER: Keyserver Operations

Use test keys intended for public keyserver testing only. Do not upload personal, production, or private key material.

#### CORE-KEYSERVER-1.1: Search by Email

**Steps:**

1. Open Keyring.
2. Click "Search Keyserver".
3. Select the default server.
4. Search for a known test email address.

**Expected:**

- [ ] Search starts and shows a loading state.
- [ ] Matching result appears when the key exists.
- [ ] Result includes enough identity data to choose the correct key.
- [ ] Import remains disabled until a result is selected.

#### CORE-KEYSERVER-1.2: Search by Key ID

**Steps:**

1. Open "Search Keyserver".
2. Search for a known test Key ID.
3. Select the matching result.
4. Import the key.

**Expected:**

- [ ] Search by Key ID returns the expected key.
- [ ] Imported key appears in Keyring.
- [ ] Duplicate import does not create duplicate visible rows.
- [ ] App Group `keys.pgp` is refreshed after import.

#### CORE-KEYSERVER-1.3: Search by Name

**Steps:**

1. Open "Search Keyserver".
2. Search for a known public test key by display name.
3. Review returned results.

**Expected:**

- [ ] Search accepts a name query.
- [ ] Matching result appears when the server supports name search.
- [ ] No-result state is clear when the server does not return a match.
- [ ] Any unsupported name-search behavior is linked as a release issue if name search is in scope.

#### CORE-KEYSERVER-1.4: No Results and Try Different Server

**Steps:**

1. Open "Search Keyserver".
2. Search for a random value that should not exist.
3. Confirm the no-results state.
4. Click "Try Different Server".

**Expected:**

- [ ] No-results state includes the searched query.
- [ ] "Try Different Server" is visible.
- [ ] Clicking "Try Different Server" allows selecting another server or retrying with another server.
- [ ] The flow does not lose the tester's ability to search again.

#### CORE-KEYSERVER-1.5: Multiple Results Selection

**Steps:**

1. Search for a query that returns multiple public keys.
2. Select one result.
3. Confirm only that result is selected.
4. Click "Import".

**Expected:**

- [ ] Multiple results render clearly.
- [ ] Only one selected result is imported.
- [ ] Imported key identity matches the selected result.
- [ ] App reports import errors clearly.

#### CORE-KEYSERVER-2.1: Upload Public Key

**Steps:**

1. Generate a disposable test key intended for upload.
2. Right-click the key.
3. Select "Upload to Keyserver...".
4. Confirm upload to the default server.

**Expected:**

- [ ] Only public key data is uploaded.
- [ ] Secret key material is never uploaded.
- [ ] Success confirmation names the destination server.
- [ ] Network or server failures show a clear error.

#### CORE-KEYSERVER-2.2: Refresh Key From Server

**Steps:**

1. Use a key known to exist on the selected keyserver.
2. Right-click the key.
3. Select "Refresh from Keyserver".

**Expected:**

- [ ] Refresh starts without blocking the UI.
- [ ] Success updates or preserves the key without duplication.
- [ ] App reports the result clearly.
- [ ] App Group `keys.pgp` is refreshed if key data changes.

#### CORE-KEYSERVER-2.3: Refresh Key Not Found

**Steps:**

1. Use a local-only disposable key that is not uploaded to the selected server.
2. Right-click the key.
3. Select "Refresh from Keyserver".

**Expected:**

- [ ] App reports that the key was not found on the server.
- [ ] Existing local key remains unchanged.
- [ ] Error does not remove or corrupt local key data.

#### CORE-KEYSERVER-3.1: Default Keyserver Setting Integration

**Steps:**

1. Open MacPGP > Settings > Keyserver.
2. Change the selected default server.
3. Close Settings.
4. Open "Search Keyserver".
5. Upload or refresh a disposable key where safe.

**Expected:**

- [ ] Default keyserver selection persists after closing Settings.
- [ ] Search uses the selected default server or clearly allows choosing it.
- [ ] Upload and refresh use the selected default server.
- [ ] If any operation ignores the selected default, link the behavior as a release issue.

#### CORE-KEYSERVER-3.2: Enable/Disable Servers and At-Least-One Constraint

**Steps:**

1. Open Settings > Keyserver.
2. Disable one configured server.
3. Attempt to disable every configured server.
4. Re-enable a disabled server.

**Expected:**

- [ ] Individual servers can be disabled and re-enabled if server management is in the release UI.
- [ ] App prevents saving a zero-enabled-server configuration.
- [ ] User sees a clear explanation when at least one server must remain enabled.
- [ ] If server enable/disable controls are absent from the release UI, link the missing coverage to the relevant release issue.

#### CORE-KEYSERVER-3.3: Timeout and Unreachable Server Handling

**Steps:**

1. Open Settings > Keyserver.
2. Set timeout to a short value such as 15 seconds.
3. Configure or select an unreachable server if supported.
4. Run search, upload, and refresh flows.
5. Confirm recovery options.

**Expected:**

- [ ] Timeout setting persists.
- [ ] Network timeout fails with a clear timeout or network error.
- [ ] Unreachable server does not hang the app.
- [ ] "Try Different Server" behavior is available where applicable.
- [ ] If "Try Different Server" does not recover correctly, link known issue `#48`.

### CORE-SETTINGS: Settings and Preferences

#### CORE-SETTINGS-1.1: General Tab Defaults and Persistence

**Steps:**

1. Open MacPGP > Settings > General.
2. Change language to a non-English supported language if available.
3. Relaunch MacPGP.
4. Confirm primary main-window strings update by checking the sidebar labels such as "Keyring", "Encrypt", "Decrypt", "Sign", and "Verify" against the selected language.
5. Confirm a menu item updates by checking a localized app command such as File > "Generate New Key..." or MacPGP > "Settings"/"Preferences" against the selected language.
6. Confirm system-facing Services labels update where localized service names are shipped by checking Services menu entries such as "Decrypt with MacPGP" and "Sign with MacPGP".
7. Confirm an extension-facing string updates where extension localization is shipped by checking one stable extension label such as the Quick Look "PGP Encrypted File" title, Quick Look "Decrypt Preview" button, or FinderSync "Encrypt with MacPGP"/"Decrypt with MacPGP" context menu item.
8. Reopen MacPGP > Settings > General.
9. Toggle "Show Key ID in list".
10. Toggle "Confirm before deleting keys".
11. Toggle "ASCII armor output by default".
12. Toggle "Auto-save keyring changes".
13. Close and reopen Settings.
14. Relaunch MacPGP and check again.
15. Click "Reset to Defaults", relaunch MacPGP, and repeat the main-window, menu, Services, and extension-facing string spot checks.

**Expected:**

- [ ] General tab opens without errors.
- [ ] Selected language persists after relaunch.
- [ ] Primary main-window strings display in the selected language after relaunch.
- [ ] Menu item text displays in the selected language after relaunch.
- [ ] Services menu labels display in the selected language when localized service names are shipped; otherwise the missing localization is linked as a bug.
- [ ] Extension-facing strings display in the selected language when extension localization is shipped; otherwise the missing localization is linked as a bug.
- [ ] Each changed setting persists after closing Settings.
- [ ] Each changed setting persists after relaunch.
- [ ] Keyring location is displayed.
- [ ] Reset to defaults restores documented defaults, including the default language behavior after relaunch.

#### CORE-SETTINGS-1.2: Clipboard Shortcut Toggles and Default Behavior Settings

**Steps:**

1. Open Settings > General.
2. Locate clipboard shortcut or clipboard behavior controls if present.
3. Change each clipboard-related setting.
4. Exercise the matching encrypt, decrypt, sign, or verify clipboard flow.
5. Restore defaults.

**Expected:**

- [ ] Clipboard-related controls are present if they are part of the release UI.
- [ ] Changed clipboard defaults affect the relevant workflow.
- [ ] Settings persist after relaunch.
- [ ] If clipboard shortcut controls are absent but expected for release, link a release issue.

#### CORE-SETTINGS-2.1: Keys Tab Algorithm and Key Size Persistence

**Steps:**

1. Open Settings > Keys.
2. Set default algorithm to RSA.
3. Set default key size to `2048 bits`.
4. Close Settings.
5. Open "Generate New Key".
6. Repeat for `3072 bits` and `4096 bits`.

**Expected:**

- [ ] RSA is available as the release-supported algorithm.
- [ ] Unsupported algorithms are absent, disabled, or clearly handled per issue `#50`.
- [ ] Default key size persists after closing Settings.
- [ ] Generate New Key starts with the selected default key size.
- [ ] Defaults persist after relaunch.

#### CORE-SETTINGS-2.2: Keys Tab Expiration Defaults

**Steps:**

1. Open Settings > Keys.
2. Change default expiration to each available value: 6 months, 1 year, 2 years, 5 years, and Never.
3. Open "Generate New Key" after each change.

**Expected:**

- [ ] Default expiration persists.
- [ ] Generate New Key reflects the selected default.
- [ ] "Never" maps to "Never expires".
- [ ] Generated key details match the selected expiration.

#### CORE-SETTINGS-3.1: Security Tab Keychain Passphrase Storage

**Steps:**

1. Open Settings > Security.
2. Toggle "Remember passphrases in Keychain".
3. Change the passphrase timeout.
4. Generate or use a key with "Store passphrase in Keychain".
5. Exercise a sign or decrypt flow that can use stored credentials.

**Expected:**

- [ ] Keychain storage toggle persists.
- [ ] Passphrase timeout setting persists.
- [ ] Stored passphrase behavior follows the setting.
- [ ] Disabling storage prevents new passphrases from being saved.

#### CORE-SETTINGS-3.2: Clear Keychain Data

**Steps:**

1. Use a Populated Keyring state with at least one stored passphrase.
2. Open Settings > Security.
3. Click the clear Keychain data button.
4. Cancel the confirmation.
5. Repeat and confirm clearing.
6. Attempt a sign or decrypt flow that previously used the stored passphrase.

**Expected:**

- [ ] Confirmation dialog appears before clearing.
- [ ] Cancel preserves stored passphrases.
- [ ] Confirm removes stored passphrases.
- [ ] Later sign or decrypt flow asks for passphrase again.
- [ ] Errors are reported clearly if Keychain clearing fails.

#### CORE-SETTINGS-4.1: Backup Tab Reminder Frequency

**Steps:**

1. Open Settings > Backup.
2. Confirm backup reminders are off on a fresh preference state.
3. Enable backup reminders and confirm the macOS notification permission prompt appears in this context if permission has not already been decided.
4. Select each reminder frequency: 7, 14, 30, 60, and 90 days.
5. Disable backup reminders.
6. Close and reopen Settings after each change.

**Expected:**

- [ ] Fresh installs do not request notification permission before this opt-in.
- [ ] Backup reminders toggle persists.
- [ ] Each reminder interval can be selected.
- [ ] Selected interval persists after closing Settings.
- [ ] Changing the reminder interval reschedules the next pending reminder using the new interval.
- [ ] Last backup date or "Never" status is visible.
- [ ] Disabling reminders suppresses future reminder scheduling.
- [ ] Re-enabling reminders does not show a second system prompt after permission has already been decided.

#### CORE-SETTINGS-5.1: Keyserver Tab Server Selection and Timeout

**Steps:**

1. Open Settings > Keyserver.
2. Change the default server.
3. Change timeout to 15, 30, 60, and 90 seconds.
4. Toggle automatic refresh if present.
5. Close and reopen Settings.
6. Relaunch MacPGP and check again.

**Expected:**

- [ ] Default server selection persists.
- [ ] Timeout selection persists for every available value.
- [ ] Automatic refresh setting persists.
- [ ] Keyserver operations use the saved default and timeout.
- [ ] If server list management is exposed, add or remove server behavior is tested and linked here.

### CORE-SVC-DEC: Decrypt Services

#### CORE-SVC-DEC-1.1: Basic Decryption

**Steps:**

1. Open TextEdit.
2. Paste an encrypted PGP message that starts with an ASCII-armored PGP message begin marker, such as `BEGIN PGP MESSAGE (example marker)`.
3. Select all the encrypted text with Cmd+A.
4. Go to TextEdit > Services > Decrypt with MacPGP.
5. In the dialog, select your secret key, enter the passphrase, and click "Decrypt Message".

**Expected:**

- [ ] The encrypted text is replaced with the decrypted plaintext message.
- [ ] No error dialogs appear.

#### CORE-SVC-DEC-1.2: Wrong Passphrase

**Steps:**

1. Select an encrypted PGP message in TextEdit.
2. Choose Services > Decrypt with MacPGP.
3. Select the correct key but enter the wrong passphrase.
4. Click "Decrypt Message".

**Expected:**

- [ ] Error dialog appears: "Decryption failed".
- [ ] Original text remains unchanged.

#### CORE-SVC-DEC-1.3: Invalid PGP Message

**Steps:**

1. Type plain text in TextEdit: `This is not encrypted`.
2. Select the text.
3. Choose Services > Decrypt with MacPGP.

**Expected:**

- [ ] Error dialog appears: "Invalid PGP message".
- [ ] Description says the selected text does not appear to be a PGP encrypted message.

#### CORE-SVC-DEC-1.4: No Secret Keys

**Steps:**

1. Use the Empty Keyring state.
2. Select an encrypted message.
3. Choose Services > Decrypt with MacPGP.

**Expected:**

- [ ] Error dialog appears: "No secret keys available".
- [ ] Description says to import a secret key to decrypt messages.

#### CORE-SVC-DEC-1.5: No Text Selected

**Steps:**

1. Open TextEdit.
2. Do not select text.
3. Choose Services > Decrypt with MacPGP.

**Expected:**

- [ ] Error dialog appears: "No text selected".
- [ ] Description says to select a PGP encrypted message to decrypt.

#### CORE-SVC-DEC-1.6: Cancel Operation

**Steps:**

1. Select an encrypted message.
2. Choose Services > Decrypt with MacPGP.
3. Click "Cancel" in the key picker dialog.

**Expected:**

- [ ] Dialog closes.
- [ ] Original encrypted text remains unchanged.

### CORE-SVC-SIGN: Sign Services

#### CORE-SVC-SIGN-1.1: Basic Signing

**Steps:**

1. Open TextEdit.
2. Type plaintext: `Hello, this is a test message.`
3. Select all the text.
4. Go to TextEdit > Services > Sign with MacPGP.
5. In the dialog, select your secret key, enter the passphrase, and click "Sign Message".

**Expected:**

- [ ] The plaintext is replaced with a clearsigned message.
- [ ] Output starts with an ASCII-armored signed message begin marker, such as `BEGIN PGP SIGNED MESSAGE (example marker)`.
- [ ] Original message is still readable.
- [ ] Signature block appears at the bottom.

#### CORE-SVC-SIGN-1.2: Wrong Passphrase

**Steps:**

1. Select plaintext in TextEdit.
2. Choose Services > Sign with MacPGP.
3. Select the correct key but enter the wrong passphrase.
4. Click "Sign Message".

**Expected:**

- [ ] Error dialog appears: "Signing failed".
- [ ] Original text remains unchanged.

#### CORE-SVC-SIGN-1.3: No Secret Keys

**Steps:**

1. Use the Empty Keyring state.
2. Select text in TextEdit.
3. Choose Services > Sign with MacPGP.

**Expected:**

- [ ] Error dialog appears: "No secret keys available".
- [ ] Description says to import or generate a key pair to sign messages.

#### CORE-SVC-SIGN-1.4: No Text Selected

**Steps:**

1. Open TextEdit with an empty document.
2. Choose Services > Sign with MacPGP without selecting text.

**Expected:**

- [ ] Error dialog appears: "No text selected".
- [ ] Description says to select text to sign.

#### CORE-SVC-SIGN-1.5: Cancel Operation

**Steps:**

1. Select plaintext in TextEdit.
2. Choose Services > Sign with MacPGP.
3. Click "Cancel" in the key picker dialog.

**Expected:**

- [ ] Dialog closes.
- [ ] Original text remains unchanged.

### CORE-BACKUP: Key Backup and Recovery

#### CORE-BACKUP-5.1: Create Unencrypted Backup

**Steps:**

1. Launch MacPGP with a Populated Keyring state.
2. Right-click any secret key in the keyring.
3. Select "Backup Keys..." from the context menu.
4. Select the test key.
5. Click "Next".
6. Uncheck "Encrypt backup with passphrase".
7. Click "Next".
8. Choose a destination file such as `~/Desktop/test-backup-unencrypted.macpgp`.
9. Click "Create Backup".

**Expected:**

- [ ] Backup wizard opens without errors.
- [ ] Key selection shows available secret keys.
- [ ] File save dialog appears.
- [ ] Backup file is created at the chosen location.
- [ ] Success message appears.
- [ ] Wizard shows confirmation screen.
- [ ] Settings > Backup shows updated "Last backup" date.

#### CORE-BACKUP-5.2: Create Encrypted Backup

**Steps:**

1. Launch MacPGP with a Populated Keyring state.
2. Choose File > Backup Keys... or press Cmd+Shift+B.
3. Select one or more keys.
4. Click "Next".
5. Check "Encrypt backup with passphrase".
6. Enter passphrase `TestPass123!`.
7. Confirm passphrase `TestPass123!`.
8. Click "Next".
9. Choose destination `~/Desktop/test-backup-encrypted.macpgp`.
10. Click "Create Backup".

**Expected:**

- [ ] Passphrase fields validate and show an error if they mismatch.
- [ ] "Next" button is disabled until passphrases match.
- [ ] Encrypted backup file is created.
- [ ] File header starts with `MACPGP-ENC-V1`.
- [ ] Success notification is displayed.
- [ ] Last backup date updates in Settings.

#### CORE-BACKUP-6.1: Restore Unencrypted Backup

**Steps:**

1. Delete the test key from the keyring.
2. Confirm deletion.
3. Choose File > Restore Keys... or press Cmd+Shift+R.
4. Click "Choose File...".
5. Select `test-backup-unencrypted.macpgp`.
6. Confirm the wizard shows the backup validation screen.
7. Confirm preview shows key fingerprints from the backup.
8. Click "Next".
9. Confirm import.
10. Click "Restore".

**Expected:**

- [ ] Restore wizard opens.
- [ ] File chooser filters for `.macpgp` files.
- [ ] Backup validates successfully.
- [ ] Preview shows correct key fingerprints.
- [ ] Key is imported back into the keyring.
- [ ] Success message appears.
- [ ] Restored key appears in keyring view.

#### CORE-BACKUP-6.2: Restore Encrypted Backup

**Steps:**

1. Delete the test key again.
2. Choose File > Restore Keys...
3. Select `test-backup-encrypted.macpgp`.
4. Confirm the wizard detects encryption and shows a passphrase field.
5. Enter incorrect passphrase `WrongPass`.
6. Click "Decrypt".
7. Confirm an error appears.
8. Enter correct passphrase `TestPass123!`.
9. Click "Decrypt".
10. Click "Next" and then "Restore".

**Expected:**

- [ ] Wizard detects encrypted backup.
- [ ] Passphrase field appears.
- [ ] Wrong passphrase shows an error message.
- [ ] Correct passphrase decrypts successfully.
- [ ] Preview shows key information.
- [ ] Keys restore successfully.
- [ ] Restored key appears in keyring.

#### CORE-BACKUP-7.1: Generate Paper Backup

**Steps:**

1. Generate or select a test RSA 2048-bit key.
2. Right-click the test key.
3. Select "Print Paper Backup..." from the context menu.
4. Confirm the paper backup window opens.

**Expected:**

- [ ] Window shows key details, including user ID, email, key type, creation date, expiration, and fingerprint.
- [ ] ASCII-armored private key is displayed.
- [ ] QR code appears for keys small enough to fit.
- [ ] Security warning is displayed.
- [ ] "Copy Fingerprint" button works.
- [ ] "Copy Key" button works.
- [ ] "Print..." button opens the print dialog.

#### CORE-BACKUP-7.2: Paper Backup for Large Key

**Steps:**

1. Generate or select a large RSA 4096-bit key.
2. Right-click the key.
3. Select "Print Paper Backup...".

**Expected:**

- [ ] Paper backup opens.
- [ ] Key details display correctly.
- [ ] ASCII-armored key is displayed.
- [ ] QR code does not appear if the key is too large.
- [ ] Message explains that QR code is not shown because the key is too large.
- [ ] Copy and print functions work.

#### CORE-BACKUP-8.1: Backup Reminder Settings

**Steps:**

1. Choose MacPGP > Settings or press Cmd+,.
2. Navigate to the Backup tab.
3. Verify the backup reminder UI.

**Expected:**

- [ ] "Backup" tab exists in settings.
- [ ] "Enable backup reminders" toggle is present.
- [ ] "Reminder interval" picker includes 7, 14, 30, 60, and 90 days.
- [ ] "Last backup" date is displayed, or "Never" appears if no backup exists.
- [ ] Settings persist when changed.

#### CORE-BACKUP-8.2: Backup Reminder Logic

**Steps:**

1. Open Settings > Backup.
2. Set "Reminder interval" to 7 days.
3. Enable backup reminders.
4. Check "Last backup" date.
5. Set the test account to an overdue backup state where `lastBackupDate + reminder interval` is in the past, then launch MacPGP.
6. Wait for notification or verify scheduling behavior.
7. Relaunch MacPGP while still overdue.
8. Disable backup reminders and relaunch again.

**Expected:**

- [ ] Settings save correctly.
- [ ] Reminder schedules based on last backup plus interval.
- [ ] If no backup exists, reminder schedules for the next day.
- [ ] If overdue, one reminder fires immediately on app launch and uses non-alarming copy and the default notification sound.
- [ ] Relaunching while still overdue does not repeatedly deliver reminders inside the configured reminder interval.
- [ ] Disabling reminders cancels pending backup reminder notifications.
- [ ] After creating a backup, "Last backup" updates.
- [ ] Reminder reschedules automatically.

#### CORE-BACKUP-9.1: Multiple Key Selection

**Steps:**

1. Choose File > Backup Keys...
2. Select three or more keys.
3. Create a backup.
4. Delete all selected keys.
5. Restore the backup.
6. Verify all keys are restored.

**Expected:**

- [ ] Multiple keys can be selected.
- [ ] Backup wizard shows the selected key count.
- [ ] All selected keys are included in the backup.
- [ ] All selected keys are restored from the backup.
- [ ] Preview shows all key fingerprints.

#### CORE-BACKUP-9.2: Invalid Backup File Handling

**Steps:**

1. Create a text file: `echo "invalid data" > ~/Desktop/invalid.macpgp`.
2. Choose File > Restore Keys...
3. Select `invalid.macpgp`.

**Expected:**

- [ ] Error message appears: "Invalid backup file format".
- [ ] Wizard does not proceed to the next step.
- [ ] No crash or undefined behavior occurs.

#### CORE-BACKUP-9.3: Corrupted Encrypted Backup

**Steps:**

1. Copy `test-backup-encrypted.macpgp` to `corrupted.macpgp`.
2. Change a few bytes in `corrupted.macpgp` with a hex editor.
3. Choose File > Restore Keys...
4. Select `corrupted.macpgp`.
5. Enter the correct passphrase.

**Expected:**

- [ ] Error message appears: "Failed to decrypt backup" or "Corrupted backup file".
- [ ] No crash occurs.
- [ ] Wizard allows retry or cancel.

---

## Part 4: Extensions

This part covers the three shipped v1.0 extensions: FinderSyncExtension, QuickLookExtension, and ThumbnailExtension. Run extension tests against Fresh Install, Upgrade Install, Empty Keyring, and Populated Keyring states where applicable. Use Finder column view and icon view for visual checks because Finder may cache badges and thumbnails differently by view mode.

Before running extension tests:

- [ ] Confirm the release candidate app includes FinderSyncExtension, QuickLookExtension, and ThumbnailExtension.
- [ ] Confirm Finder extensions are enabled in System Settings > General > Login Items & Extensions > Finder Extensions where required by the OS version.
- [ ] Relaunch Finder after installing a new build if badges, menus, Quick Look, or thumbnails do not refresh.
- [ ] Prepare encrypted binary `.gpg` and `.pgp` files, encrypted ASCII-armored `.asc` files, and non-encrypted `.asc` public key exports.
- [ ] Record each test result in the execution tracking table.

### EXT-FINDER: FinderSyncExtension

FinderSyncExtension does not read `group.com.macpgp.shared/keys.pgp`. It analyzes selected files and hands file URLs to the main app.

#### EXT-FINDER-1.1: Badge on Encrypted `.gpg` File

**Steps:**

1. Use Finder to open a folder watched by FinderSyncExtension.
2. Place an encrypted binary `.gpg` file in the folder.
3. Switch Finder between icon view and column view.
4. Wait for Finder to request badges, or relaunch Finder if needed.

**Expected:**

- [ ] `.gpg` file shows the MacPGP encrypted lock badge.
- [ ] Badge label is "Encrypted" where Finder exposes badge labels.
- [ ] Badge remains visible after switching Finder views.
- [ ] Badge returns after Finder relaunch.

#### EXT-FINDER-1.2: Badge on Encrypted `.asc` File

**Steps:**

1. Place an ASCII-armored encrypted `.asc` file in the watched Finder folder.
2. Confirm the file contains an ASCII-armored PGP message begin marker, such as `BEGIN PGP MESSAGE (example marker)`.
3. Switch Finder between icon view and column view.

**Expected:**

- [ ] Encrypted `.asc` file shows the MacPGP encrypted lock badge.
- [ ] Finder does not confuse encrypted `.asc` with public-key `.asc`.
- [ ] Badge remains visible after Finder refresh.

#### EXT-FINDER-1.3: No Badge on Non-Encrypted `.asc` Public Key

**Steps:**

1. Export or prepare an ASCII-armored public key file ending in `.asc`.
2. Confirm the file contains an ASCII-armored public key begin marker, such as `BEGIN PGP PUBLIC KEY BLOCK (example marker)`.
3. Place the file in the watched Finder folder.
4. Switch Finder between icon view and column view.

**Expected:**

- [ ] Public key `.asc` file does not show the encrypted lock badge.
- [ ] Finder still displays the file normally.
- [ ] No false encrypted-file indicator appears.

#### EXT-FINDER-1.4: Badge Appears on Newly Created Encrypted File

**Steps:**

1. Use MacPGP to encrypt a plaintext file into the watched Finder folder.
2. Save output as `.gpg` or encrypted `.asc`.
3. Observe the file immediately after creation.
4. Relaunch Finder only if the badge does not appear within a reasonable refresh window.

**Expected:**

- [ ] Newly created encrypted file receives the lock badge.
- [ ] Badge appears without requiring MacPGP relaunch.
- [ ] Finder refresh delay, if any, is recorded in the tracking table.

#### EXT-FINDER-2.1: Context Menu for Regular Files

**Steps:**

1. In Finder, right-click a regular plaintext file.
2. Open the Finder extension context menu area.
3. Repeat with multiple regular files selected.

**Expected:**

- [ ] "Encrypt with MacPGP" appears for any selected regular file.
- [ ] "Decrypt with MacPGP" does not appear for regular files.
- [ ] Multi-file selection still offers "Encrypt with MacPGP".

#### EXT-FINDER-2.2: Context Menu for Encrypted Files

**Steps:**

1. In Finder, right-click an encrypted `.gpg`, `.pgp`, or encrypted `.asc` file.
2. Open the Finder extension context menu area.
3. Repeat with multiple encrypted files selected.

**Expected:**

- [ ] "Decrypt with MacPGP" appears for encrypted files.
- [ ] "Encrypt with MacPGP" remains available where FinderSyncExtension offers it.
- [ ] Multi-file encrypted selection forwards only encrypted files for decrypt.

#### EXT-FINDER-2.3: Context Menu Is Absent for Directories

**Steps:**

1. In Finder, right-click a directory.
2. Open the Finder extension context menu area.
3. Repeat with a selection that contains only directories.

**Expected:**

- [ ] MacPGP file actions are absent for directory-only selections.
- [ ] No directory URL is handed to the main app for encryption or decryption.
- [ ] If a directory receives a file action, link a release issue.

#### EXT-FINDER-3.1: Encrypt Action Opens Main App With File Preloaded

**Steps:**

1. Quit MacPGP.
2. In Finder, right-click a regular file.
3. Select "Encrypt with MacPGP".
4. Wait for MacPGP to launch.

**Expected:**

- [ ] MacPGP launches.
- [ ] App navigates to the Encrypt view.
- [ ] File mode is active or the selected file is listed for encryption.
- [ ] Selected Finder file path matches the file shown in MacPGP.
- [ ] Empty Keyring state shows the no-recipient behavior without losing the file selection.
- [ ] Populated Keyring state allows selecting recipients and completing encryption.

#### EXT-FINDER-3.2: Decrypt Action Opens Main App With File Preloaded

**Steps:**

1. Quit MacPGP.
2. In Finder, right-click an encrypted file.
3. Select "Decrypt with MacPGP".
4. Wait for MacPGP to launch.

**Expected:**

- [ ] MacPGP launches.
- [ ] App navigates to the Decrypt view.
- [ ] File mode is active or the selected encrypted file is listed for decryption.
- [ ] Selected Finder file path matches the file shown in MacPGP.
- [ ] Empty Keyring state shows the no-secret-key behavior without losing the file selection.
- [ ] Populated Keyring state allows decryption with the matching secret key.

#### EXT-FINDER-4.1: Main App Not Installed or Not Found

**Steps:**

1. Use a test machine or temporary install state where FinderSyncExtension is present but the containing MacPGP app cannot be resolved.
2. In Finder, choose "Encrypt with MacPGP" or "Decrypt with MacPGP".
3. Launch MacPGP after the failed handoff, if available.
4. Inspect Console.app for `Finder Sync error` and `ExtensionCommunicationService` log entries.

**Expected:**

- [ ] FinderSyncExtension does not crash.
- [ ] Error payload is written to the App Group defaults under the Finder Sync errors queue.
- [ ] Main app processes the pending error through `ExtensionCommunicationService` on launch.
- [ ] User sees a notification or clear error such as "MacPGP app not found" or "Could not open MacPGP".
- [ ] Error payload is cleared after delivery.

#### EXT-FINDER-5.1: Empty and Populated Keyring State Coverage

**Steps:**

1. Run EXT-FINDER-1.x through EXT-FINDER-4.x in Empty Keyring state.
2. Run the same cases in Populated Keyring state.
3. Compare Finder badge and context menu behavior across states.

**Expected:**

- [ ] Badge behavior is independent of keyring state.
- [ ] Context menu availability is independent of keyring state.
- [ ] Main-app handoff preserves selected files in both states.
- [ ] Empty Keyring failures happen in the main app with clear no-key messages.
- [ ] Populated Keyring flows can complete encryption and decryption.

### EXT-QL: QuickLookExtension

QuickLookExtension reads the shared App Group keyring projection at `group.com.macpgp.shared/keys.pgp`. Fresh Install and Empty Keyring states must be tested before any keyring sync, and Populated Keyring tests must be repeated after the main app writes shared key data.

#### EXT-QL-1.1: Metadata Display for Encrypted File

**Steps:**

1. Select an encrypted `.gpg` file in Finder.
2. Press Space to open Quick Look.
3. Inspect the preview metadata.

**Expected:**

- [ ] Preview title identifies the file as a PGP encrypted file.
- [ ] Algorithm is shown when metadata can be extracted, for example AES-256 or equivalent OpenPGP algorithm text.
- [ ] Integrity Protection is shown as "Yes (MDC)" when MDC is present.
- [ ] Recipient key IDs are listed when present.
- [ ] File size is shown.
- [ ] Creation date is shown when metadata or file attributes provide it.

#### EXT-QL-1.2: Metadata Display for `.pgp` and ASCII-Armored `.asc`

**Steps:**

1. Open Quick Look for an encrypted binary `.pgp` file.
2. Open Quick Look for an encrypted ASCII-armored `.asc` file.
3. Compare metadata fields with the `.gpg` baseline.

**Expected:**

- [ ] `.pgp` encrypted file renders metadata preview.
- [ ] Encrypted `.asc` file renders metadata preview.
- [ ] Recipient key IDs are shown when present.
- [ ] Integrity and file information fields are present for each supported file type.
- [ ] Non-encrypted key exports are not presented as decryptable encrypted messages.

#### EXT-QL-2.1: Decrypt Preview With Populated Shared Keyring

**Steps:**

1. Use a Populated Keyring state with the matching secret key.
2. Launch MacPGP and ensure `group.com.macpgp.shared/keys.pgp` is written.
3. Select an encrypted file for that secret key in Finder.
4. Press Space to open Quick Look.
5. Click "Decrypt Preview".
6. Enter the passphrase.

**Expected:**

- [ ] "Decrypt Preview" button appears.
- [ ] Passphrase prompt appears.
- [ ] Correct passphrase decrypts successfully.
- [ ] Text content is displayed as readable text.
- [ ] Image content is displayed as an image preview when supported.
- [ ] Binary content is displayed with an appropriate binary-content view.
- [ ] Wrong passphrase shows a clear error and allows retry.

#### EXT-QL-2.2: Decrypt Preview Hidden With Empty Shared Container

**Steps:**

1. Use Fresh Install or Empty Keyring state.
2. Confirm `~/Library/Group Containers/group.com.macpgp.shared/keys.pgp` is absent, empty, or contains no secret keys.
3. Select an encrypted file in Finder.
4. Press Space to open Quick Look.

**Expected:**

- [ ] Metadata preview still renders.
- [ ] "Decrypt Preview" button is hidden.
- [ ] Preview shows a message directing the user to open MacPGP to sync or import keys.
- [ ] Quick Look does not fall back to Application Support.
- [ ] Quick Look does not crash when shared key data is missing.

#### EXT-QL-2.3: Fresh Install Before and After Keyring Sync

**Steps:**

1. Start from Fresh Install state.
2. Open Quick Look for an encrypted test file before launching MacPGP or creating keys.
3. Generate or import the matching secret key in MacPGP.
4. Confirm `group.com.macpgp.shared/keys.pgp` is written.
5. Reopen Quick Look for the same encrypted file.

**Expected:**

- [ ] Before sync, Quick Look shows metadata and disables decrypt preview.
- [ ] After sync, "Decrypt Preview" appears for files matching available secret keys.
- [ ] Decryption succeeds after sync with the correct passphrase.
- [ ] Behavior matches `docs/SHARED_STORAGE.md`.

#### EXT-QL-3.1: File Type Coverage

**Steps:**

1. Open Quick Look for a binary `.gpg` encrypted file.
2. Open Quick Look for a binary `.pgp` encrypted file.
3. Open Quick Look for an ASCII-armored encrypted `.asc` file.
4. Open Quick Look for a non-encrypted public key `.asc` file.

**Expected:**

- [ ] Binary `.gpg` file previews correctly.
- [ ] Binary `.pgp` file previews correctly.
- [ ] ASCII-armored encrypted `.asc` file previews correctly.
- [ ] Non-encrypted public key `.asc` is not treated as a decryptable encrypted file.
- [ ] Unsupported or malformed files fail gracefully.

### EXT-THUMB: ThumbnailExtension

ThumbnailExtension does not read shared key data. It analyzes file content and renders a custom thumbnail only for encrypted PGP files.

#### EXT-THUMB-1.1: Binary Encrypted File Visual Theme

**Steps:**

1. Place a binary encrypted `.gpg` or `.pgp` file in Finder.
2. Switch Finder to icon view.
3. Increase icon size enough to inspect the thumbnail.
4. Repeat in column view or gallery view where thumbnails are visible.

**Expected:**

- [ ] Binary encrypted file gets a custom thumbnail.
- [ ] Thumbnail uses the binary encrypted visual theme with blue accent/gradient treatment.
- [ ] Thumbnail includes the `lock.fill` icon.
- [ ] "PGP" badge is visible.
- [ ] Encoding format label is "Binary".

#### EXT-THUMB-1.2: ASCII-Armored Encrypted File Visual Theme

**Steps:**

1. Place an ASCII-armored encrypted `.asc` file in Finder.
2. Switch Finder to icon view.
3. Increase icon size enough to inspect the thumbnail.
4. Repeat in column view or gallery view where thumbnails are visible.

**Expected:**

- [ ] ASCII-armored encrypted file gets a custom thumbnail.
- [ ] Thumbnail uses the ASCII-armored visual theme with green accent/gradient treatment.
- [ ] Thumbnail includes the `lock.doc.fill` icon.
- [ ] "PGP" badge is visible.
- [ ] Encoding format label is "ASCII Armored".

#### EXT-THUMB-2.1: Non-Encrypted PGP File Negative Case

**Steps:**

1. Export a public key to an ASCII-armored `.asc` file.
2. Place the file in Finder.
3. Switch Finder to icon view.
4. Refresh Finder thumbnails.

**Expected:**

- [ ] Non-encrypted public key export does not get the encrypted custom thumbnail.
- [ ] "PGP" encrypted badge is not shown.
- [ ] File remains usable as a normal key export file.
- [ ] No thumbnail extension crash appears in Console.app.

#### EXT-THUMB-3.1: Thumbnail Refresh for Newly Encrypted File

**Steps:**

1. Use MacPGP to encrypt a new file into a Finder-visible folder.
2. Save output as binary `.gpg` or ASCII-armored `.asc`.
3. Open the folder in Finder icon view.
4. Switch to column view and back to icon view.
5. Relaunch Finder only if the thumbnail does not update.

**Expected:**

- [ ] Newly encrypted file receives a custom thumbnail.
- [ ] Thumbnail appears in Finder column view.
- [ ] Thumbnail appears in Finder icon view.
- [ ] Thumbnail theme matches the output encoding.
- [ ] Any refresh delay or cache issue is recorded in the tracking table.

### EXT-SHARE: ShareExtension Exclusion

ShareExtension is postponed for v1.0 per `docs/V1_SCOPE.md` and issue `#49`. It remains a development target, but it must not be embedded in the public release app bundle. ShareExtension tests should be added in a future release when share-sheet support is in scope.

#### EXT-SHARE-1.1: Release Bundle Does Not Embed ShareExtension

**Steps:**

1. Build or obtain the release candidate `MacPGP.app`.
2. Inspect `MacPGP.app/Contents/PlugIns/`.
3. Confirm shipped extension bundles.

**Expected:**

- [ ] `FinderSyncExtension.appex` is present.
- [ ] `QuickLookExtension.appex` is present.
- [ ] `ThumbnailExtension.appex` is present.
- [ ] ShareExtension.appex must not be present in release bundle.
- [ ] Any embedded `ShareExtension.appex` is linked as a release-blocking issue.

#### EXT-SHARE-1.2: Release Guardrail Script

**Steps:**

1. From the repository root, run the release guardrail script against the project file:

```bash
CONFIGURATION=Release scripts/check-no-shareextension-in-release.sh
```

2. If testing a built app bundle, rerun with `APP_BUNDLE` set to the release candidate path:

```bash
CONFIGURATION=Release APP_BUNDLE="/path/to/MacPGP.app" scripts/check-no-shareextension-in-release.sh
```

**Expected:**

- [ ] Script passes for Release when ShareExtension is not embedded.
- [ ] Script fails if `ShareExtension.appex` is embedded.
- [ ] CI uses this guardrail for release validation.
- [ ] Failure output is clear enough to identify the offending bundle or project phase.

### EXT-CROSS: Cross-Extension Integration

#### EXT-CROSS-1.1: Shared Container Sync From Main App to Quick Look

**Steps:**

1. Start from Fresh Install state.
2. Confirm `~/Library/Group Containers/group.com.macpgp.shared/keys.pgp` is absent or empty.
3. Generate a new key in MacPGP.
4. Confirm `keys.pgp` is written after key generation.
5. Encrypt a file to the generated key.
6. Open the encrypted file in Quick Look.
7. Click "Decrypt Preview" and enter the passphrase.

**Expected:**

- [ ] Main app writes `group.com.macpgp.shared/keys.pgp` after key generation.
- [ ] Quick Look can read the shared keyring projection.
- [ ] "Decrypt Preview" appears after sync.
- [ ] Quick Look decrypts the file with the generated key.
- [ ] Shared storage behavior matches `docs/SHARED_STORAGE.md`.

#### EXT-CROSS-1.2: FinderSync Badge Updates for Files Encrypted to Synced Key

**Steps:**

1. Continue from EXT-CROSS-1.1.
2. Save the encrypted file in a Finder-visible folder.
3. Inspect the file in Finder icon view and column view.
4. Relaunch Finder if necessary.

**Expected:**

- [ ] FinderSync badge appears on the encrypted file.
- [ ] Badge behavior does not depend on reading `keys.pgp`.
- [ ] Badge remains visible after Finder refresh.
- [ ] Quick Look can still decrypt the same file when shared secret key data is present.

#### EXT-CROSS-1.3: App Group Data Freshness After Key Import

**Steps:**

1. Start with MacPGP running and Quick Look available.
2. Import a new secret key into MacPGP.
3. Without restarting MacPGP, confirm `group.com.macpgp.shared/keys.pgp` is updated.
4. Open Quick Look for a file encrypted to the imported key.
5. Attempt "Decrypt Preview".

**Expected:**

- [ ] Main app updates `keys.pgp` immediately after import.
- [ ] Quick Look can use the imported key without restarting MacPGP.
- [ ] If Quick Look requires reopening the preview to see fresh data, record that behavior.
- [ ] No stale empty-keyring message remains after the shared projection is updated.

#### EXT-CROSS-1.4: Stale Shared Container Behavior

**Steps:**

1. Use a Populated Keyring state and confirm Quick Look can decrypt a test file.
2. Simulate stale shared data by replacing or preserving an older `keys.pgp` while changing the main app keyring.
3. Open Quick Look for files that require old and new keys.
4. Launch MacPGP or perform a keyring save.
5. Reopen Quick Look.

**Expected:**

- [ ] Extensions tolerate stale `keys.pgp` data without crashing.
- [ ] Quick Look may continue using stale shared data until the main app next launches or saves the keyring.
- [ ] Main app refreshes the shared projection on launch or save.
- [ ] After refresh, Quick Look behavior matches the current keyring projection.
- [ ] This behavior is documented as expected per `docs/SHARED_STORAGE.md`.


---

## Part 5: Cross-Cutting Scenarios

### CROSS-E2E-1.1: Full Two-Key Round Trip

This test simulates two machines by using two isolated keyring states or two macOS test accounts. Record which isolation method was used.

**Steps:**

1. Start from Fresh Install or Empty Keyring state for Machine A.
2. Generate an RSA keypair for Machine A.
3. Export Machine A's public key.
4. Create or switch to a separate simulated Machine B state.
5. Import Machine A's public key into Machine B.
6. Generate an RSA keypair for Machine B.
7. Export Machine B's public key.
8. Import Machine B's public key into Machine A.
9. On Machine A, encrypt a text message to Machine B.
10. On Machine B, decrypt the message with Machine B's secret key.
11. On Machine B, sign a reply message.
12. On Machine A, verify Machine B's signed reply.

**Expected:**

- [ ] Public key export from Machine A succeeds.
- [ ] Public key import into Machine B succeeds.
- [ ] Public key export from Machine B succeeds.
- [ ] Public key import into Machine A succeeds.
- [ ] Machine A can encrypt to Machine B's public key.
- [ ] Machine B can decrypt with its secret key and correct passphrase.
- [ ] Machine B can sign a reply.
- [ ] Machine A verifies the signed reply when Machine B's public key is present.
- [ ] Signer attribution appears when supported; missing attribution is linked to `#9`.
- [ ] No secret key is exported or imported where only a public key exchange is intended.

### CROSS-E2E-1.2: Full File Round Trip

**Steps:**

1. Continue from CROSS-E2E-1.1 with both simulated machines configured.
2. On Machine A, create a text file and a small binary file.
3. Encrypt both files to Machine B.
4. Transfer the encrypted outputs to Machine B.
5. Decrypt both files on Machine B.
6. Compare decrypted output with the original files.
7. Sign one decrypted file on Machine B.
8. Verify the signed file on Machine A.

**Expected:**

- [ ] File encryption succeeds for text and binary input.
- [ ] Encrypted files use the selected output location.
- [ ] Machine B decrypts both files successfully.
- [ ] Decrypted files match original file contents.
- [ ] File signing succeeds.
- [ ] Machine A verifies the signed file with Machine B's public key.

### CROSS-BACKUP-1.1: Backup, Delete, Restore, and Revalidate

**Steps:**

1. Use a Populated Keyring state with at least one secret key and one imported public key.
2. Create an encrypted backup containing all secret keys.
3. Record fingerprints for every key in the keyring.
4. Delete all keys from the keyring.
5. Relaunch MacPGP and confirm the keyring is empty.
6. Restore the backup.
7. Relaunch MacPGP again.
8. Compare restored fingerprints against the recorded fingerprints.

**Expected:**

- [ ] Encrypted backup is created successfully.
- [ ] Deleting all keys removes them from the keyring.
- [ ] Empty state appears after relaunch before restore.
- [ ] Restore imports all backed-up keys.
- [ ] Restored fingerprints match the pre-delete records.
- [ ] Restored secret keys can decrypt previously encrypted test data.
- [ ] Restored secret keys can sign new test data.
- [ ] Restored public keys can be used as encryption recipients.
- [ ] App Group `keys.pgp` is refreshed after restore.

### CROSS-BACKUP-1.2: Restored Keys Work Across Extensions

**Steps:**

1. Continue from CROSS-BACKUP-1.1 after restore.
2. Encrypt a new file to a restored key.
3. Confirm FinderSync badge appears on the encrypted file.
4. Open the file in Quick Look.
5. Use "Decrypt Preview" with the restored secret key.
6. Inspect Finder thumbnail for the encrypted file.

**Expected:**

- [ ] FinderSync detects the restored-key encrypted file as encrypted.
- [ ] Quick Look can decrypt after restore and shared keyring sync.
- [ ] ThumbnailExtension renders a custom encrypted thumbnail.
- [ ] Extension behavior matches the restored keyring state without requiring another import.

### CROSS-KNOWN-1.1: Known Issues Source Check

`docs/KNOWN_ISSUES.md` is not currently present in this checkout. Until that file exists, use `docs/V1_SCOPE.md`, `docs/app-store-v1-detailed-issues.md`, and linked GitHub issues as the known-issue source for manual QA. If `docs/KNOWN_ISSUES.md` is added later, add one row per issue from that file to this section.

**Steps:**

1. Confirm whether `docs/KNOWN_ISSUES.md` exists in the release candidate.
2. If it exists, list every issue in the Bugs Found or Known Issues Verification tables.
3. If it does not exist, use the existing issue references listed below.
4. For each known issue, run the matching manual test and verify the documented behavior or workaround.
5. Link any mismatch as a new bug.

**Expected:**

- [ ] Every known issue has a matching manual verification result.
- [ ] Workarounds documented in the repo still match the app behavior.
- [ ] Fixed known issues no longer reproduce and are marked for doc cleanup.
- [ ] Missing `docs/KNOWN_ISSUES.md` does not block QA as long as the issue source used for the run is recorded.

### CROSS-KNOWN-1.2: Existing Issue Verification Checklist

Use these references during release QA. Add more rows as GitHub issues are filed or as `docs/KNOWN_ISSUES.md` grows.

**Steps:**

1. Review each issue reference in the table below.
2. Run the linked manual cases for the current release candidate.
3. Record the result in the Known Issues Verification table near the end of this guide.
4. File or link a follow-up bug if the documented behavior or workaround is wrong.

| Issue Ref | Verification Focus | Manual Cases |
| --- | --- | --- |
| `#4` | FinderSync app resolution and release-like installs | EXT-FINDER-3.1, EXT-FINDER-3.2, EXT-FINDER-4.1 |
| `#5` | Shared-container data flow between app and extensions | EXT-QL-2.2, EXT-QL-2.3, EXT-CROSS-1.1, EXT-CROSS-1.4 |
| `#9` | Signer attribution in verification results | CORE-SIGNVERIFY-2.1, CORE-SIGNVERIFY-2.2, CROSS-E2E-1.1 |
| `#10` | Web of Trust/key metadata release-scope behavior, depending on the filed GitHub issue in this repo | CORE-KEY-1.x, CORE-SETTINGS-2.1, release-scope review against `docs/V1_SCOPE.md` |
| `#16` | Keyserver defaults, timeout, and network UX | CORE-KEYSERVER-3.1, CORE-KEYSERVER-3.3, CORE-SETTINGS-5.1 |
| `#43` | Invalid signature versus operational error distinction | CORE-SIGNVERIFY-2.3 |
| `#48` | "Try Different Server" recovery behavior | CORE-KEYSERVER-1.4, CORE-KEYSERVER-3.3 |
| `#49` | ShareExtension excluded from v1.0 release bundle | EXT-SHARE-1.1, EXT-SHARE-1.2 |
| `#50` | RSA-only or unsupported key algorithm behavior | CORE-SETTINGS-2.1, CORE-KEY-1.1, CORE-KEY-1.2, CORE-KEY-1.3 |

**Expected:**

- [ ] Each issue reference has a Pass, Fail, Blocked, or Not run result.
- [ ] Failures are linked to the existing issue or a new follow-up issue.
- [ ] Known postponed features remain hidden or clearly out of scope for v1.0.
- [ ] Known fixed issues are verified as fixed before release sign-off.

### CROSS-SVC-3.1: Decrypt and Sign in Mail.app

**Steps:**

1. Open Mail.app.
2. Compose a new message.
3. Paste encrypted text or type plaintext.
4. Select text.
5. Choose Mail > Services > Decrypt with MacPGP or Sign with MacPGP.

**Expected:**

- [ ] Services work identically to TextEdit.
- [ ] Text is replaced with the decrypted or signed version.

### CROSS-SVC-3.2: Decrypt and Sign in Notes.app

**Steps:**

1. Open Notes.app.
2. Create a new note with test text.
3. Select text.
4. Choose Notes > Services > Decrypt with MacPGP or Sign with MacPGP.

**Expected:**

- [ ] Services work in Notes.
- [ ] Operations complete successfully.

### CROSS-SVC-3.3: Decrypt and Sign in Safari

**Steps:**

1. Open Safari.
2. Navigate to a text input such as webmail compose.
3. Type or paste test text.
4. Select text.
5. Right-click and choose Services > Decrypt with MacPGP or Sign with MacPGP.

**Expected:**

- [ ] Services appear in the context menu.
- [ ] Operations work in web forms.

### CROSS-SHORTCUT-4.1: Assign Keyboard Shortcuts

**Steps:**

1. Open System Settings > Keyboard > Keyboard Shortcuts.
2. Select Services.
3. Scroll to the Text section.
4. Find "Decrypt with MacPGP" and "Sign with MacPGP".
5. Add keyboard shortcuts such as Cmd+Opt+D and Cmd+Opt+S.
6. Test shortcuts in TextEdit.

**Expected:**

- [ ] Services appear in Keyboard Shortcuts settings.
- [ ] Custom shortcuts can be assigned.
- [ ] Shortcuts work system-wide in supported apps.

### Services Verification Checklist

For Services troubleshooting, see Section 1.3 (Services Setup).

#### Decrypt Service

- [ ] Basic decryption works with the correct passphrase.
- [ ] Wrong passphrase shows an error.
- [ ] Invalid PGP message shows an error.
- [ ] Missing secret keys shows an error.
- [ ] Empty selection shows an error.
- [ ] Cancel leaves original text unchanged.
- [ ] Works in TextEdit.
- [ ] Works in Mail.app.
- [ ] Works in Notes.app.
- [ ] Works in Safari text fields.

#### Sign Service

- [ ] Basic signing creates a cleartext signature.
- [ ] Signed message starts with an ASCII-armored signed message begin marker, such as `BEGIN PGP SIGNED MESSAGE (example marker)`.
- [ ] Original message remains readable in signed output.
- [ ] Wrong passphrase shows an error.
- [ ] Missing secret keys shows an error.
- [ ] Empty selection shows an error.
- [ ] Cancel leaves original text unchanged.
- [ ] Works in TextEdit.
- [ ] Works in Mail.app.
- [ ] Works in Notes.app.
- [ ] Works in Safari text fields.

#### System Integration

- [ ] Services appear in the Services menu after app launch.
- [ ] Services can be assigned keyboard shortcuts.
- [ ] Keyboard shortcuts work system-wide.

---

## Bug Tracking and Sign-Off

### Bugs Found

Add one row for every bug found during manual QA, including bugs already covered by an existing issue. Use Severity values `Critical`, `High`, `Medium`, or `Low`.

| Issue Number | Test ID | Description | Severity | Linked GitHub Issue |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

### Known Issues Verification

Use this table to record known issue checks from `docs/KNOWN_ISSUES.md` when present. If that file is absent, record checks from `docs/V1_SCOPE.md`, `docs/app-store-v1-detailed-issues.md`, and the issue references in CROSS-KNOWN-1.2.

| Known Issue Ref | Test ID | Expected Current Behavior or Workaround | Result | Follow-Up |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

### Filing New Bugs

File new bugs as GitHub issues and link them in both the top-level tracking table and the Bugs Found table. Follow the issue-body format used in `docs/app-store-v1-detailed-issues.md`:

```markdown
**Summary**
One or two sentences describing the user-visible problem.

**Current repo evidence**
- Test ID and install/keyring state used.
- Build/archive identifier.
- Exact steps that reproduce the issue.
- Expected result from this guide.
- Actual result observed.
- Screenshots, logs, Console.app excerpts, or sample files when useful.

**What needs to happen**
- Concrete fix or investigation needed.
- Any release-blocking decision needed.

**Acceptance criteria**
- Observable behavior required to close the issue.
- Retest ID from this guide.
```

Bug filing rules:

- [ ] File Critical and High severity issues immediately during the QA run.
- [ ] Link the issue number in the affected test row before continuing.
- [ ] Attach screenshots or screen recordings for visual extension failures.
- [ ] Attach sample files only when they contain no private key material or sensitive plaintext.
- [ ] Never attach secret keys, production passphrases, or private user data.
- [ ] Add a retest row after the fix lands instead of overwriting the original failed result.

### Final Release QA Sign-Off

- [ ] All critical paths pass.
- [ ] All shipped core app features tested.
- [ ] All shipped extensions tested.
- [ ] ShareExtension exclusion verified.
- [ ] All install states tested.
- [ ] Empty Keyring and Populated Keyring states tested.
- [ ] All known issues verified.
- [ ] All Critical bugs closed or explicitly accepted by release owner.
- [ ] All High bugs closed, deferred with written approval, or converted into release notes.
- [ ] QA lead approval recorded with date.

QA lead:
Date:
Release candidate build/archive:
Known issue source used:
Open release blockers:
