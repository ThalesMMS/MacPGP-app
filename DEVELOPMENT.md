# Development

## Requirements

- macOS Tahoe 26.2 or later
- Xcode 26.2+
- Apple Silicon (`arm64`) build host. The vendored `RNPBridge.xcframework` ships only an `arm64` macOS slice, so Intel `x86_64` builds are not supported and Intel Macs cannot build or run MacPGP.
- Bash 4+ for shell test harnesses such as `scripts/test-manual-testing-guide-modules.sh`; CI and supported dev shells should resolve `/usr/bin/env bash` to Bash 4+.

### Architecture support matrix

The Apple Silicon requirement applies at every layer. These are distinct requirements that happen to share the same answer today:

| Layer | Requirement |
| --- | --- |
| Runtime (users) | Apple Silicon Mac (`arm64`). Intel Macs are not supported. |
| Development host | Apple Silicon Mac (`arm64`). Intel Macs cannot build the project. |
| Archive / CI architecture | `arm64`-only. The release app and `RNPBridge.xcframework` contain no `x86_64` slice. |

`scripts/check-bridge-architectures.sh` reports the architectures vendored in `RNPBridge.xcframework` (and, when an app bundle is provided, the final archive's executable) and fails if they diverge from the documented `arm64`-only matrix.

> Universal (`arm64` + `x86_64`) or Intel support is **not** a current goal. Adding it would require rebuilding `RNPBridge.xcframework` with an `x86_64` macOS slice, re-validating librnp on Intel, and updating this matrix together with `scripts/check-bridge-architectures.sh`. Track it as a separate roadmap item if it is ever pursued.

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
   - In Xcode: press `⌘R`.
   - From the command line: `scripts/build.sh run` builds and launches the app.
     Use `scripts/build.sh` to just build, `scripts/build.sh test` for the unit
     tests, and `scripts/build.sh --help` for all commands. It wraps the same
     `xcodebuild` invocation as CI, so by default it builds unsigned (no team or
     provisioning profile required); add `--signed` when you need entitlements
     (App Groups / keychain) to exercise the bundled extensions.

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

## Signing and entitlements

The shipped targets are the Main App plus four extensions: FinderSyncExtension,
QuickLookExtension, ThumbnailExtension, and ShareExtension. Each target's
minimum entitlement set and rationale are recorded in `MacPGP/ENTITLEMENTS.md`,
with the machine-readable source of truth in `scripts/entitlements-manifest.json`.

- `scripts/check-archive-entitlements.sh --source` validates the checked-in
  `.entitlements` files against the manifest and runs in CI, so source drift
  (e.g. an unexpected App Group on the sandbox-only ThumbnailExtension) is caught
  without a signed archive.
- `scripts/check-archive-entitlements.sh --archive <path>` validates a signed
  `.xcarchive` before App Store submission (App Group, user-selected file access,
  the app's keychain access group, absence of `get-task-allow`, and the embedded
  extension inventory). See `docs/SIGNING_REFERENCE.md` and `RELEASING.md`.
