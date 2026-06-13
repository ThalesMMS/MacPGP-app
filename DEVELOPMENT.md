# Development

## Requirements

- macOS Tahoe 26.2 or later
- Xcode 26.2+
- Apple Silicon (`arm64`) build host. The vendored `RNPBridge.xcframework` currently ships only an `arm64` macOS slice, so Intel `x86_64` builds are intentionally excluded and Intel Macs are not recommended for development.
- Bash 4+ for shell test harnesses such as `scripts/test-manual-testing-guide-modules.sh`; CI and supported dev shells should resolve `/usr/bin/env bash` to Bash 4+.

## Local Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/ThalesMMS/MacPGP-app.git
   cd MacPGP-app
   ```

2. Open the Xcode project:
   ```bash
   open MacPGP/MacPGP.xcodeproj
   ```

3. Build and run:
   Use `⌘R` in Xcode.

## Dependencies

- Local `RNPKit` Swift wrapper backed by the vendored `Vendor/RNPBridge/RNPBridge.xcframework`
- CI, the Xcode project, and `Vendor/RNPKit/Package.swift` intentionally target macOS 26.2. The vendored bridge archive currently reports `minos 26.0`, which is compatible with that deployment target; `Vendor/RNPBridge/scripts/check-rnp-bridge-minos.sh` guards against accidentally vendoring a newer bridge.
- CI hides the Dock before `MacPGPUITests` so the hosted macOS desktop cannot cover sheet confirmation buttons and steal synthesized clicks.

## Project Structure

```text
MacPGP/
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Security/
│   └── Persistence/
├── Features/
│   ├── Keyring/
│   ├── KeyDetails/
│   ├── KeyGeneration/
│   ├── Encryption/
│   ├── Signing/
│   └── Settings/
├── Navigation/
└── Shared/
    ├── Components/
    └── Extensions/
```
