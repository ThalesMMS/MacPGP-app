# Changelog

All notable changes to this project should be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for Git tags and release names.

## [Unreleased]

- No unreleased changes yet.

## [1.0.0] - 2026-04-21

### Key Management
- Added native macOS workflows to generate new RSA keys and import, export, and delete OpenPGP public and private keys.

### Encryption and Decryption
- Added message and file encryption and decryption, including support for encrypting to multiple recipients.

### Signing and Verification
- Added signing workflows for messages and files, plus signature verification when the relevant public key is available.

### Keychain Integration
- Added macOS Keychain-backed passphrase storage for supported release-visible workflows.

### ASCII Armor Support
- Added ASCII-armored input and output support for compatible keys, messages, and signatures.

### Extensions
- Added Finder Sync integration for encrypted-file badges and Finder context menu actions.
- Added Quick Look integration for encrypted-file metadata previews and in-preview decryption when the required data is available.
- Added Thumbnail integration for custom previews of supported encrypted files.

### Session State
- Added release-visible session state persistence so users can return to core workflows without losing expected local context.
