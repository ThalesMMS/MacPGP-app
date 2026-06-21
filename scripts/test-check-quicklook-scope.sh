#!/usr/bin/env bash
# Self-test for scripts/check-quicklook-scope.sh (issue #136).
#
# Guards against the consistency check silently degrading into a no-op: it
# extracts the *actual* regexes used by the check and asserts they flag known
# regressions (positive in-preview decryption claims, code decryption symbols)
# while leaving the current metadata-only wording alone. It also runs the real
# check against the repo and expects it to pass.
#
# Run locally: bash scripts/test-check-quicklook-scope.sh

set -uo pipefail
cd "$(dirname "$0")/.."

check="scripts/check-quicklook-scope.sh"
fails=0

if [[ ! -f "$check" ]]; then
  echo "FAIL: $check not found"
  exit 1
fi

# Extract the regexes the check actually uses, so this test can never drift from
# the implementation.
positive_claims="$(sed -n "s/^positive_claims='\(.*\)'$/\1/p" "$check")"
code_forbidden="$(sed -n "s/^code_forbidden='\(.*\)'$/\1/p" "$check")"

if [[ -z "$positive_claims" ]]; then
  echo "FAIL: could not extract positive_claims regex from $check"
  fails=$((fails + 1))
fi
if [[ -z "$code_forbidden" ]]; then
  echo "FAIL: could not extract code_forbidden regex from $check"
  fails=$((fails + 1))
fi

expect_match() {  # <regex> <should_match:yes|no> <sample>
  local regex="$1" want="$2" sample="$3" got="no"
  if printf '%s\n' "$sample" | grep -qiE "$regex"; then got="yes"; fi
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: expected match=$want but got=$got for: $sample"
    fails=$((fails + 1))
  fi
}

# --- Doc claims: positive in-preview decryption assertions MUST match. ---
for s in \
  'Supports in-preview decryption where the app has the required keys.' \
  'including metadata and in-preview decryption when the required keys are available' \
  'The app group lets Quick Look read keys.pgp for in-preview decryption.' \
  'Quick Look decrypts the file with the generated key.' \
  'Quick Look can still decrypt the same file when keys are present.' \
  'Optionally decrypt and preview the content after entering a passphrase.' \
  'Click "Decrypt Preview" and enter the passphrase.'; do
  expect_match "$positive_claims" yes "$s"
done

# --- Current metadata-only / negative wording MUST NOT match. ---
for s in \
  'Quick Look does not decrypt in-preview.' \
  'No "Decrypt Preview" button, passphrase prompt, or decrypted content is shown.' \
  'openpgp,encryption,decryption,signing,quick look,thumbnails' \
  'Decryption never happens inside the Quick Look preview.' \
  'No In-Preview Decryption With Populated Shared Keyring' \
  'it does not decrypt in-preview, and it does not need user-selected file access.' \
  'Added scripts/check-quicklook-scope.sh to keep scope docs and decryption copy in sync.'; do
  expect_match "$positive_claims" no "$s"
done

# --- Code symbols: a reintroduced decryption path MUST match. ---
for s in \
  'let decrypter = PreviewDecrypter()' \
  'SharedKeyringLoader.load()' \
  'private func handleDecryption() {' \
  'Button("Decrypt Preview") { showPassphrasePrompt = true }' \
  'self.decryptedData = try RNP.decrypt(data)'; do
  expect_match "$code_forbidden" yes "$s"
done

# --- Metadata-only view code MUST NOT match the decryption-symbol regex. ---
for s in \
  'Text("quicklook_open_in_app_to_decrypt")' \
  '/// process has no secret-key material and cannot decrypt in-preview without' \
  'let metadata: PGPMetadataExtractor.Metadata'; do
  expect_match "$code_forbidden" no "$s"
done

# --- The real check must pass against the current repo. ---
if bash "$check" >/dev/null 2>&1; then
  echo "ok: live check passes against the repo"
else
  echo "FAIL: live check ($check) does not pass against the current repo"
  fails=$((fails + 1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "Quick Look scope self-test FAILED ($fails assertion(s))."
  exit 1
fi
echo "Quick Look scope self-test passed."
