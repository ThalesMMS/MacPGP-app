import Foundation

/// Adopted by view models that hold transient passphrase or other sensitive
/// credential UI state, so **Lock MacPGP** (and system sleep / session-lock
/// events, via `SessionLockController`) can invalidate every active workflow —
/// not only the primary Encrypt/Decrypt/Sign screens.
///
/// `handleLock()` must:
/// - clear passphrase and other transient secret fields;
/// - dismiss or reset any active credential prompt;
/// - invalidate the in-flight request/run **generation** so a stale async
///   completion cannot repopulate a field after the lock;
/// - cancel pending work where it is safe to do so.
///
/// It must **not** delete persisted Keychain items or secret key material:
///
/// | State | Lifetime | Cleared by lock? |
/// | --- | --- | --- |
/// | Transient UI/cache state (passphrase fields, `PassphraseCache`) | in-memory | yes |
/// | Persisted Keychain items | until explicitly deleted | no |
/// | Secret key material in the keyring | until explicitly deleted | no |
///
/// As documented for `PassphraseCache`, clearing Swift strings removes
/// application-held references but cannot guarantee physical memory zeroization;
/// this contract does not overclaim secure erasure.
@MainActor
protocol SensitiveSessionState: AnyObject {
    func handleLock()
}
