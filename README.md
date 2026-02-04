# MacPGP

A native macOS application for PGP encryption, decryption, signing, and key management built with SwiftUI.

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

## Requirements

- macOS 15.0+
- Xcode 16.0+

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/thalesmms/MacPGP.git
   cd MacPGP
   ```

2. Open the Xcode project:
   ```bash
   open MacPGP/MacPGP.xcodeproj
   ```

3. Build and run (⌘R)

## Security Checks (Optional)

Enable the secret-scanning pre-commit hook:
```bash
brew install pre-commit
pre-commit install
```

Run it manually:
```bash
pre-commit run --all-files
```

If gitleaks flags the PGP armor header literals, the allowlist is in
`.gitleaks.toml`.

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
