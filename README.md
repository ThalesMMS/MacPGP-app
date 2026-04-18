# MacPGP

![Platform: macOS Tahoe](https://img.shields.io/badge/platform-macOS%20Tahoe-blue)
![UI: SwiftUI](https://img.shields.io/badge/UI-SwiftUI-orange)
![License: BSD 3-Clause](https://img.shields.io/badge/license-BSD%203--Clause-lightgrey)

![UI Screenshot](screenshot.png)

MacPGP is a native macOS OpenPGP app built with SwiftUI for PGP key management, message and file encryption/decryption, digital signing, signature verification, and Finder-integrated workflows through FinderSync, QuickLook, and Thumbnail extensions.

## Features

- **Key Management** - Generate, import, export, and delete PGP keys
- **Encryption** - Encrypt messages and files for one or more recipients
- **Decryption** - Decrypt PGP-encrypted messages and files
- **Signing** - Create digital signatures with support for:
  - Cleartext signed messages (human-readable)
  - Detached signatures
  - Armored output
- **Verification** - Verify PGP signatures and extract original messages
- **Keychain Integration** - Securely store passphrases in macOS Keychain
- **ASCII Armor Support** - Import/export keys and messages in armored format
- **Session State** - Preserves input/output state across view navigation

The authoritative Mac App Store v1.0 release boundary is defined in [docs/V1_SCOPE.md](docs/V1_SCOPE.md).

## Finder Integration

MacPGP v1.0 ships three Finder-facing macOS extensions:

- **FinderSyncExtension** - Encrypted files (.gpg, .asc, .pgp) display a lock badge in Finder, and Finder context menu actions open supported encrypt/decrypt workflows in MacPGP
- **QuickLookExtension** - Press Space on an encrypted file to see:
  - Encryption metadata (algorithm, recipients, file size)
  - Decrypt preview button with secure passphrase prompt
  - In-place content preview (text and images) without saving to disk
- **ThumbnailExtension** - Encrypted files get custom thumbnails for quick visual distinction:
  - Binary files (.gpg, .pgp): Blue gradient with lock icon
  - ASCII armored files (.asc): Green gradient with document-lock icon

**Enabling Extensions:**
After first launch, enable the shipping extensions in System Settings → Privacy & Security → Extensions → Finder Extensions / Quick Look / Thumbnails.

`ShareExtension.appex` remains in the repository for future work, but it is not embedded in the public v1.0 build. See [docs/V1_SCOPE.md](docs/V1_SCOPE.md) for the release boundary.

## Future Features

These capabilities are planned for future releases and are not part of the v1.0 shipping UI:

- Web of Trust backed by proper PGP certification support
- ShareExtension remains in the codebase for future share-sheet workflows, but it is not shipped in the public v1.0 build
- Key expiration editing and revocation certificate workflows remain hidden until ObjectivePGP support is ready

## Requirements

- Minimum supported: macOS Tahoe (macOS 26)
- Tested on: macOS Tahoe (macOS 26)
- Xcode 16.0+

## Release status

This repository does not publish GitHub releases yet.
Until the first tagged release is cut, MacPGP should be treated as a source-build project.
Release prep lives in [CHANGELOG.md](CHANGELOG.md) and [RELEASING.md](RELEASING.md), and the first public tag should stay a prerelease if signing/notarization or final smoke testing is still incomplete.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ThalesMMS/MacPGP.git
   cd MacPGP
   ```

2. Open the Xcode project:
   ```bash
   open MacPGP/MacPGP.xcodeproj
   ```

3. Build and run (⌘R)

## Dependencies

- [ObjectivePGP](https://github.com/krzyzanowskim/ObjectivePGP) - OpenPGP implementation for iOS and macOS

## Project Structure

```
MacPGP/
├── Core/
│   ├── Models/          # Data models (PGPKeyModel, KeyAlgorithm, etc.)
│   ├── Services/        # Business logic (KeyringService, EncryptionService, SigningService, SessionStateManager)
│   ├── Security/        # Keychain integration
│   └── Persistence/     # Key storage and preferences
├── Features/
│   ├── Keyring/         # Key list and management UI
│   ├── KeyDetails/      # Key details and fingerprint views
│   ├── KeyGeneration/   # Key generation wizard
│   ├── Encryption/      # Encrypt and decrypt views
│   ├── Signing/         # Sign and verify views
│   └── Settings/        # App preferences
├── Navigation/          # App navigation (sidebar, content view)
└── Shared/
    ├── Components/      # Reusable UI components (CopyableText, PassphraseField)
    └── Extensions/      # Swift extensions
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Generate New Key | ⌘N |
| Import Key | ⌘I |

## License

BSD 3-Clause License - see [LICENSE](LICENSE) for details.

This software uses [ObjectivePGP](https://github.com/krzyzanowskim/ObjectivePGP) which is licensed under its own terms.
