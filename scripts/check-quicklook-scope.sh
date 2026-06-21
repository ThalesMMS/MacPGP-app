#!/usr/bin/env bash
# Enforces the Quick Look "metadata-only" scope decision (issue #136) and keeps
# scope documentation in agreement with the shipped Quick Look surface.
#
# The shared App Group projection (`keys.pgp`) is intentionally public-key-only,
# so the Quick Look process holds no secret-key material and must never decrypt
# in-preview. This check fails if either side drifts:
#
#   A. CODE — the QuickLookExtension regains a decryption path (a decrypt symbol,
#      passphrase prompt, shared-keyring load, or "Decrypt Preview" control), or
#      drops the "open in MacPGP to decrypt" copy that tells users where to go.
#   B. DOCS — a release-visible or scope document makes a positive claim that
#      Quick Look decrypts in-preview (negative / metadata-only statements are
#      allowed; a reintroduced positive claim is not).
#
# Run locally or in CI:
#   bash scripts/check-quicklook-scope.sh

set -uo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { printf '  - %s\n' "$1"; }

ql_dir="MacPGP/QuickLookExtension"
ql_swift_glob="$ql_dir"/*.swift

# ---------------------------------------------------------------------------
# A. Code invariant: QuickLookExtension is metadata-only.
# ---------------------------------------------------------------------------
# Decryption-path symbols that must NOT appear in the Quick Look extension.
# These are identifiers/UI strings (not prose), so the metadata-only view's
# explanatory comments ("cannot decrypt in-preview") do not match.
code_forbidden='PreviewDecrypter|SharedKeyringLoader|handleDecryption|showPassphrasePrompt|decryptedData|decryptionTask|RNP\.decrypt|tryDecrypt|"Decrypt Preview"|PassphrasePrompt'

code_hits="$(grep -rnE "$code_forbidden" $ql_swift_glob 2>/dev/null || true)"
if [[ -n "$code_hits" ]]; then
  echo "Quick Look scope check FAILED: decryption path found in $ql_dir"
  while IFS= read -r line; do note "$line"; done <<< "$code_hits"
  echo "  Quick Look is metadata-only (issue #136). Remove the decryption path,"
  echo "  or, if in-preview decryption is being reintroduced deliberately, update"
  echo "  the scope docs and this check together."
  fail=1
fi

# The user-facing "open in MacPGP to decrypt" copy must be referenced by the
# view and defined in the base localization, so the metadata-only surface keeps
# telling users where decryption happens.
note_key="quicklook_open_in_app_to_decrypt"
if ! grep -rqF "$note_key" $ql_swift_glob 2>/dev/null; then
  echo "Quick Look scope check FAILED: the metadata-only view no longer references"
  echo "  \"$note_key\" (the 'open in MacPGP to decrypt' copy)."
  fail=1
fi
strings_file="$ql_dir/Resources/en.lproj/Localizable.strings"
if [[ -f "$strings_file" ]] && ! grep -qF "\"$note_key\"" "$strings_file"; then
  echo "Quick Look scope check FAILED: \"$note_key\" is missing from $strings_file."
  fail=1
fi

# ---------------------------------------------------------------------------
# B. Documentation invariant: no positive Quick Look in-preview decryption claim.
# ---------------------------------------------------------------------------
# Scan release-visible and scope documents for *positive* statements that Quick
# Look decrypts in-preview. The patterns are deliberately specific so they catch
# the original claims (and obvious regressions) without firing on metadata-only
# / negative wording ("Quick Look does not decrypt", 'no "Decrypt Preview"'),
# keyword lists, or references to this script.
doc_targets=(
  "docs/V1_SCOPE.md"
  "docs/SHARED_STORAGE.md"
  "docs/APP_STORE_LISTING.md"
  "docs/RELEASE_TEST_MATRIX.md"
  "docs/MANUAL-TESTING-GUIDE.md"
  "docs/E2E-Testing-Finder-ContextMenu-Decrypt.md"
  "README.md"
  "CHANGELOG.md"
  "MacPGP/ENTITLEMENTS.md"
)
# website HTML, if present.
while IFS= read -r html; do
  [[ -n "$html" ]] && doc_targets+=("$html")
done < <(ls website/*.html 2>/dev/null || true)

# Positive in-preview-decryption claims. Each alternative is an unambiguous
# assertion that Quick Look decrypts; negative/metadata-only phrasings do not
# match because they lack these exact verb constructions.
positive_claims='(supports?|enables?|allows?|offers?|including|and|with) +in-preview decryption|in-preview decryption when|for in-preview decryption|read[a-z ]*keys\.pgp[a-z ]*for in-preview|decrypts? and preview|decrypt and preview|quick ?look decrypts|quick ?look can (still )?decrypt|quick ?look (may|will|could)[a-z ]*decrypt|(click|use|attempt|press|tap) +"?decrypt preview|"decrypt preview"( button)? (appears|is shown|is available|is visible)|decrypt preview with|"decrypt preview" and enter'

for f in "${doc_targets[@]}"; do
  [[ -f "$f" ]] || continue
  suspects="$(grep -inE "$positive_claims" "$f" 2>/dev/null || true)"
  if [[ -n "$suspects" ]]; then
    echo "Quick Look scope check FAILED: in-preview decryption claim in $f"
    while IFS= read -r line; do note "$line"; done <<< "$suspects"
    echo "  Quick Look is metadata-only (issue #136). Reword as a metadata-only /"
    echo "  'open in MacPGP to decrypt' statement, or update the scope decision and"
    echo "  this check together."
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "Quick Look scope check passed: extension is metadata-only and docs agree (issue #136)."
