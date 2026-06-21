#!/usr/bin/env bash
# Enforces localization key parity across all supported locales (issue #131).
#
# Fails when any locale is missing keys present in the base (English) locale, has
# keys the base locale does not, contains duplicate keys, or has malformed
# `.strings` syntax.
#
# Usage:
#   scripts/check-localization-parity.sh [resources-dir] [base-locale]

set -uo pipefail

resources="${1:-MacPGP/MacPGP/Resources}"
base_locale="${2:-en}"
strings_name="Localizable.strings"

fail=0
err() { echo "::error::$*" >&2; fail=1; }

base_file="$resources/$base_locale.lproj/$strings_name"
if [[ ! -f "$base_file" ]]; then
  echo "::error::Base strings file not found: $base_file" >&2
  exit 1
fi

# Sorted, unique keys of a .strings file (parsed as JSON via plutil so comments
# and escaping are handled correctly).
keys_of() {
  plutil -convert json -o - "$1" 2>/dev/null \
    | python3 -c "import sys, json; print('\n'.join(sorted(json.load(sys.stdin).keys())))"
}

# Duplicate keys via a raw scan (plutil/JSON would silently de-duplicate).
duplicates_of() {
  grep -oE '^[[:space:]]*"([^"\\]|\\.)*"[[:space:]]*=' "$1" \
    | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*=$//' \
    | sort | uniq -d
}

base_keys="$(keys_of "$base_file")"
if [[ -z "$base_keys" ]]; then
  echo "::error::No keys parsed from base file $base_file" >&2
  exit 1
fi
base_count="$(printf '%s\n' "$base_keys" | grep -c .)"
echo "Base locale '$base_locale' defines $base_count keys."

for lproj in "$resources"/*.lproj; do
  [[ -d "$lproj" ]] || continue
  loc="$(basename "$lproj" .lproj)"
  file="$lproj/$strings_name"

  if [[ ! -f "$file" ]]; then
    err "Locale '$loc' is missing $strings_name"
    continue
  fi

  if ! plutil -lint "$file" >/dev/null 2>&1; then
    err "Malformed .strings syntax: $file"
    continue
  fi

  dups="$(duplicates_of "$file")"
  if [[ -n "$dups" ]]; then
    err "Duplicate keys in $file:"
    printf '%s\n' "$dups" | sed 's/^/    - /' >&2
  fi

  [[ "$loc" == "$base_locale" ]] && continue

  loc_keys="$(keys_of "$file")"
  missing="$(comm -23 <(printf '%s\n' "$base_keys") <(printf '%s\n' "$loc_keys"))"
  extra="$(comm -13 <(printf '%s\n' "$base_keys") <(printf '%s\n' "$loc_keys"))"

  if [[ -n "$missing" ]]; then
    err "Locale '$loc' is missing keys present in '$base_locale':"
    printf '%s\n' "$missing" | sed 's/^/    - /' >&2
  fi
  if [[ -n "$extra" ]]; then
    err "Locale '$loc' has keys not present in '$base_locale':"
    printf '%s\n' "$extra" | sed 's/^/    - /' >&2
  fi

  if [[ -z "$missing" && -z "$extra" && -z "$dups" ]]; then
    echo "Locale '$loc': OK ($(printf '%s\n' "$loc_keys" | grep -c .) keys)."
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "Localization parity check FAILED." >&2
  exit 1
fi

echo "Localization parity check passed: every locale matches the '$base_locale' key set, with no duplicates and valid syntax."
