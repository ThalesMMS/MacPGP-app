# Manual Testing Guide

This guide provides comprehensive testing instructions for MacPGP features that require manual verification due to macOS system integration (Services, notifications, Keychain).

## Prerequisites

1. macOS system with Xcode installed
2. MacPGP app built and running
3. At least one PGP key in the keyring (generate a test key if needed)
4. Allow notifications for MacPGP (System Settings > Notifications)

### Build Instructions

```bash
# From the repository root
open MacPGP/MacPGP.xcodeproj

# In Xcode:
# 1. Select MacPGP scheme
# 2. Product > Build (Cmd+B)
# 3. Product > Run (Cmd+R)
```

### Services Setup

If services don't appear after launching MacPGP:

```bash
# Flush services cache
/System/Library/CoreServices/pbs -flush

# Relaunch MacPGP
open ./build/Debug/MacPGP.app

# Wait 5-10 seconds for registration
```

---

## Part 1: Decrypt and Sign Services

### Decrypt Service Tests

#### Test 1.1: Basic Decryption (Happy Path)

**Steps:**
1. Open TextEdit
2. Paste an encrypted PGP message (must start with `-----BEGIN PGP MESSAGE-----`)
3. Select all the encrypted text (Cmd+A)
4. Go to TextEdit > Services > Decrypt with MacPGP
5. In the dialog:
   - Select your secret key from dropdown
   - Enter your passphrase
   - Click "Decrypt Message"

**Expected:**
- [ ] The encrypted text is replaced with the decrypted plaintext message
- [ ] No error dialogs appear

#### Test 1.2: Decrypt - Wrong Passphrase

**Steps:**
1. Select an encrypted PGP message in TextEdit
2. Services > Decrypt with MacPGP
3. Select correct key but enter wrong passphrase
4. Click "Decrypt Message"

**Expected:**
- [ ] Error dialog appears: "Decryption failed"
- [ ] Original text remains unchanged

#### Test 1.3: Decrypt - Invalid PGP Message

**Steps:**
1. Type plain text in TextEdit: "This is not encrypted"
2. Select the text
3. Services > Decrypt with MacPGP

**Expected:**
- [ ] Error dialog appears: "Invalid PGP message"
- [ ] Description: "The selected text does not appear to be a PGP encrypted message"

#### Test 1.4: Decrypt - No Secret Keys

**Steps:**
1. Remove all secret keys from keyring (or use fresh install)
2. Select an encrypted message
3. Services > Decrypt with MacPGP

**Expected:**
- [ ] Error dialog appears: "No secret keys available"
- [ ] Description: "Import a secret key to decrypt messages"

#### Test 1.5: Decrypt - No Text Selected

**Steps:**
1. Open TextEdit
2. Don't select any text (or select empty area)
3. Services > Decrypt with MacPGP

**Expected:**
- [ ] Error dialog appears: "No text selected"
- [ ] Description: "Please select a PGP encrypted message to decrypt"

#### Test 1.6: Decrypt - Cancel Operation

**Steps:**
1. Select encrypted message
2. Services > Decrypt with MacPGP
3. Click "Cancel" in the key picker dialog

**Expected:**
- [ ] Dialog closes
- [ ] Original encrypted text remains unchanged

---

### Sign Service Tests

#### Test 2.1: Basic Signing (Happy Path)

**Steps:**
1. Open TextEdit
2. Type plaintext: "Hello, this is a test message."
3. Select all the text
4. Go to TextEdit > Services > Sign with MacPGP
5. In the dialog:
   - Select your secret key from dropdown
   - Enter your passphrase
   - Click "Sign Message"

**Expected:**
- [ ] The plaintext is replaced with a clearsigned message:
```
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

Hello, this is a test message.
-----BEGIN PGP SIGNATURE-----

iQEzBAEB... (signature)
-----END PGP SIGNATURE-----
```
- [ ] Original message is still readable
- [ ] Signature block appears at the bottom

#### Test 2.2: Sign - Wrong Passphrase

**Steps:**
1. Select plaintext in TextEdit
2. Services > Sign with MacPGP
3. Select correct key but enter wrong passphrase
4. Click "Sign Message"

**Expected:**
- [ ] Error dialog appears: "Signing failed"
- [ ] Original text remains unchanged

#### Test 2.3: Sign - No Secret Keys

**Steps:**
1. Remove all secret keys from keyring
2. Select text in TextEdit
3. Services > Sign with MacPGP

**Expected:**
- [ ] Error dialog appears: "No secret keys available"
- [ ] Description: "Import or generate a key pair to sign messages"

#### Test 2.4: Sign - No Text Selected

**Steps:**
1. Open TextEdit with empty document
2. Services > Sign with MacPGP (without selecting text)

**Expected:**
- [ ] Error dialog appears: "No text selected"
- [ ] Description: "Please select text to sign"

#### Test 2.5: Sign - Cancel Operation

**Steps:**
1. Select plaintext in TextEdit
2. Services > Sign with MacPGP
3. Click "Cancel" in the key picker dialog

**Expected:**
- [ ] Dialog closes
- [ ] Original text remains unchanged

---

### Cross-App Service Tests

#### Test 3.1: Decrypt/Sign in Mail.app

**Steps:**
1. Open Mail.app
2. Compose new message
3. Paste encrypted text or type plaintext
4. Select text
5. Mail > Services > (Decrypt/Sign) with MacPGP

**Expected:**
- [ ] Services work identically to TextEdit
- [ ] Text is replaced with decrypted/signed version

#### Test 3.2: Decrypt/Sign in Notes.app

**Steps:**
1. Open Notes.app
2. Create new note with test text
3. Select text
4. Notes > Services > (Decrypt/Sign) with MacPGP

**Expected:**
- [ ] Services work in Notes
- [ ] Operations complete successfully

#### Test 3.3: Decrypt/Sign in Safari

**Steps:**
1. Open Safari
2. Navigate to any text input (e.g., web email compose)
3. Type or paste test text
4. Select text
5. Right-click > Services > (Decrypt/Sign) with MacPGP

**Expected:**
- [ ] Services appear in context menu
- [ ] Operations work in web forms

---

### Keyboard Shortcuts

#### Test 4.1: Assign Keyboard Shortcuts

**Steps:**
1. Open System Preferences > Keyboard > Shortcuts
2. Select "Services" in left sidebar
3. Scroll to "Text" section
4. Find "Decrypt with MacPGP" and "Sign with MacPGP"
5. Click to add keyboard shortcuts:
   - Decrypt: Cmd+Opt+D (or your choice)
   - Sign: Cmd+Opt+S (or your choice)
6. Test shortcuts in TextEdit

**Expected:**
- [ ] Services appear in Keyboard Shortcuts preferences
- [ ] Custom shortcuts can be assigned
- [ ] Shortcuts work system-wide in any app

---

## Part 2: Key Backup and Recovery

### Test Suite 5: Backup Creation

#### Test 5.1: Create Unencrypted Backup

**Steps:**
1. Launch MacPGP
2. Right-click on any secret key in the keyring
3. Select "Backup Keys..." from context menu
4. Backup wizard should open
5. Select the test key (checkbox should be checked)
6. Click "Next"
7. Uncheck "Encrypt backup with passphrase"
8. Click "Next"
9. Choose a destination file (e.g., `~/Desktop/test-backup-unencrypted.macpgp`)
10. Click "Create Backup"

**Expected:**
- [ ] Backup wizard opens without errors
- [ ] Key selection shows available secret keys
- [ ] File save dialog appears
- [ ] Backup file is created at chosen location
- [ ] Success message: "Backup created successfully"
- [ ] Wizard shows confirmation screen
- [ ] Settings > Backup shows updated "Last backup" date

#### Test 5.2: Create Encrypted Backup

**Steps:**
1. Launch MacPGP (or continue from previous test)
2. File > Backup Keys... (or Cmd+Shift+B)
3. Select one or more keys
4. Click "Next"
5. Check "Encrypt backup with passphrase"
6. Enter passphrase: `TestPass123!`
7. Confirm passphrase: `TestPass123!`
8. Click "Next"
9. Choose destination: `~/Desktop/test-backup-encrypted.macpgp`
10. Click "Create Backup"

**Expected:**
- [ ] Passphrase fields validate (show error if mismatch)
- [ ] "Next" button disabled until passphrases match
- [ ] Encrypted backup file created
- [ ] File header shows encryption (open in text editor: should start with `MACPGP-ENC-V1`)
- [ ] Success notification displayed
- [ ] Last backup date updated in Settings

---

### Test Suite 6: Backup Restore

#### Test 6.1: Restore Unencrypted Backup

**Steps:**
1. Delete the test key from keyring (right-click > Delete Key)
2. Confirm deletion
3. File > Restore Keys... (or Cmd+Shift+R)
4. Restore wizard opens
5. Click "Choose File..."
6. Select `test-backup-unencrypted.macpgp`
7. Wizard shows backup validation screen
8. Preview should show key fingerprints from backup
9. Click "Next"
10. Confirm import
11. Click "Restore"

**Expected:**
- [ ] Restore wizard opens
- [ ] File chooser filters for `.macpgp` files
- [ ] Backup validates successfully
- [ ] Preview shows correct key fingerprints
- [ ] Key is imported back into keyring
- [ ] Success message: "Keys restored successfully"
- [ ] Restored key appears in keyring view

#### Test 6.2: Restore Encrypted Backup

**Steps:**
1. Delete the test key again
2. File > Restore Keys...
3. Select `test-backup-encrypted.macpgp`
4. Wizard detects encryption, shows passphrase field
5. Enter incorrect passphrase: `WrongPass`
6. Click "Decrypt"
7. Error should appear
8. Enter correct passphrase: `TestPass123!`
9. Click "Decrypt"
10. Backup validates, shows preview
11. Click "Next" > "Restore"

**Expected:**
- [ ] Wizard detects encrypted backup
- [ ] Passphrase field appears
- [ ] Wrong passphrase shows error message
- [ ] Correct passphrase decrypts successfully
- [ ] Preview shows key information
- [ ] Keys restore successfully
- [ ] Restored key appears in keyring

---

### Test Suite 7: Paper Backup

#### Test 7.1: Generate Paper Backup (Small Key)

**Steps:**
1. Generate a small test key (RSA 2048-bit)
2. Right-click on the test key
3. Select "Print Paper Backup..." from context menu
4. Paper backup window opens

**Expected:**
- [ ] Window shows key details (User ID, email, key type, creation date, expiration, fingerprint)
- [ ] ASCII-armored private key displayed (scrollable)
- [ ] QR code appears (for keys < 2KB)
- [ ] Security warning displayed
- [ ] "Copy Fingerprint" button works
- [ ] "Copy Key" button works
- [ ] "Print..." button opens print dialog

#### Test 7.2: Paper Backup for Large Key

**Steps:**
1. Generate or select a large key (RSA 4096-bit)
2. Right-click > "Print Paper Backup..."

**Expected:**
- [ ] Paper backup opens
- [ ] Key details displayed correctly
- [ ] ASCII-armored key displayed
- [ ] QR code does NOT appear (key too large)
- [ ] Message: "QR code not shown (key too large)"
- [ ] All other functions work (copy, print)

---

### Test Suite 8: Backup Reminders

#### Test 8.1: Backup Reminder Settings

**Steps:**
1. MacPGP > Settings (or Cmd+,)
2. Navigate to "Backup" tab
3. Verify UI elements

**Expected:**
- [ ] "Backup" tab exists in settings
- [ ] "Enable backup reminders" toggle present
- [ ] "Reminder interval" picker with options: 7, 14, 30, 60, 90 days
- [ ] "Last backup" date displayed (or "Never" if no backup)
- [ ] Settings persist when changed

#### Test 8.2: Backup Reminder Logic

**Steps:**
1. Settings > Backup
2. Set "Reminder interval" to 7 days
3. Enable "backup reminders"
4. Check "Last backup" date
5. Wait for notification (or verify scheduling logic)

**Expected:**
- [ ] Settings save correctly
- [ ] Reminder scheduled based on last backup + interval
- [ ] If no backup: reminder schedules for next day
- [ ] If overdue: reminder shows immediately
- [ ] After creating backup: "Last backup" updates
- [ ] Reminder reschedules automatically

---

### Test Suite 9: Integration and Error Handling

#### Test 9.1: Multiple Key Selection

**Steps:**
1. File > Backup Keys...
2. Select multiple keys (3+)
3. Create backup
4. Delete all selected keys
5. Restore backup
6. Verify all keys restored

**Expected:**
- [ ] Multiple keys can be selected
- [ ] Backup wizard shows count (e.g., "3 keys selected")
- [ ] All keys included in backup
- [ ] All keys restored from backup
- [ ] Preview shows all key fingerprints

#### Test 9.2: Invalid Backup File Handling

**Steps:**
1. Create a text file: `echo "invalid data" > ~/Desktop/invalid.macpgp`
2. File > Restore Keys...
3. Select `invalid.macpgp`

**Expected:**
- [ ] Error message: "Invalid backup file format"
- [ ] Wizard does not proceed to next step
- [ ] No crash or undefined behavior

#### Test 9.3: Corrupted Encrypted Backup

**Steps:**
1. Copy `test-backup-encrypted.macpgp` to `corrupted.macpgp`
2. Open `corrupted.macpgp` in a hex editor and change a few bytes
3. File > Restore Keys...
4. Select `corrupted.macpgp`
5. Enter correct passphrase

**Expected:**
- [ ] Error message: "Failed to decrypt backup" or "Corrupted backup file"
- [ ] No crash
- [ ] Wizard allows retry or cancel

---

## Services Verification Checklist

### Decrypt Service
- [ ] Basic decryption works with correct passphrase
- [ ] Wrong passphrase shows error
- [ ] Invalid PGP message shows error
- [ ] Missing secret keys shows error
- [ ] Empty selection shows error
- [ ] Cancel works without modifying text
- [ ] Works in TextEdit
- [ ] Works in Mail.app
- [ ] Works in Notes.app
- [ ] Works in Safari text fields

### Sign Service
- [ ] Basic signing creates cleartext signature
- [ ] Signed message starts with `-----BEGIN PGP SIGNED MESSAGE-----`
- [ ] Original message remains readable in signed output
- [ ] Wrong passphrase shows error
- [ ] Missing secret keys shows error
- [ ] Empty selection shows error
- [ ] Cancel works without modifying text
- [ ] Works in TextEdit
- [ ] Works in Mail.app
- [ ] Works in Notes.app
- [ ] Works in Safari text fields

### System Integration
- [ ] Services appear in Services menu after app launch
- [ ] Services can be assigned keyboard shortcuts
- [ ] Keyboard shortcuts work system-wide

---

## Troubleshooting

### Services Don't Appear

```bash
# Flush services cache
/System/Library/CoreServices/pbs -flush

# Relaunch MacPGP
open ./build/Debug/MacPGP.app

# Wait 5-10 seconds for registration
```

### Dialog Doesn't Appear
- Check Console.app for errors
- Verify MacPGP is running in foreground
- Try clicking Services menu item multiple times

### Wrong Key Used for Decryption
- Ensure the message was encrypted for the selected key
- Try different secret keys from dropdown
- Verify key is not expired

### Signature Not Verifiable
- Check that cleartext format is used (`-----BEGIN PGP SIGNED MESSAGE-----`)
- Verify signature includes hash algorithm line (e.g., `Hash: SHA256`)
- Ensure signature block is complete

---

## Notes

- This is a manual testing guide - automated tests are not feasible for macOS Services or notification-dependent workflows
- Services may take 5-10 seconds to appear after first app launch
- Services cache may need flushing after app updates
- All services use the system pasteboard for input/output
- Services work with any app that supports text services
