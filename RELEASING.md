# Releasing MacPGP

MacPGP already has a substantial local feature set, but it does not publish GitHub releases yet.
This document keeps the first public release honest: ship a prerelease if any gate below is still incomplete, and cut a stable `v1.0.0` only after the full checklist is done.

## Versioning strategy

- Use Semantic Versioning for Git tags (`vMAJOR.MINOR.PATCH`).
- Keep the app's `MARKETING_VERSION` aligned with the intended release line.
- Use `CURRENT_PROJECT_VERSION` as the build number and increment it for each shipped build.
- Prefer prerelease tags such as `v1.0.0-rc.1` if signing, notarization, or final validation is still pending.

## Release checklist

- [ ] `CHANGELOG.md` updated for the release
- [ ] Draft release notes reviewed in GitHub
- [ ] `xcodebuild build -project MacPGP/MacPGP.xcodeproj -scheme MacPGP -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [ ] Manual smoke test completed for key generation/import, encrypt/decrypt, sign/verify, and key export
- [ ] Finder Sync, Quick Look, Thumbnail, and Share extensions verified on a clean local install
- [ ] Distribution artifact decided and documented (for example: signed `.app`, `.zip`, or `.dmg`)
- [ ] macOS signing/notarization status confirmed in the release notes
- [ ] Installation and extension-enablement steps in `README.md` verified against the shipped artifact

## First stable release gate

Cut the first stable `v1.0.0` only when all checklist items above are complete.
If any item is still open, publish a prerelease instead and call out the remaining gaps in the release notes.
