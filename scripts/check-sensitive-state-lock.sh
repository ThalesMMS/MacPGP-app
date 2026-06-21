#!/usr/bin/env bash
# Source audit that fails when a type holding a transient passphrase field has no
# explicit lock policy (issue #143).
#
# Any file that declares a STORED `passphrase`-bearing String property must
# either:
#   - clear it on lock (contains `handleLock`, `.macPGPDidLock`, or an
#     `onDisappear` clear for separate-process extension views), or
#   - be listed, with a reason, in scripts/sensitive-state-lock-allowlist.txt
#     (for transient values that are not retained credential UI state).
#
# Computed properties (e.g. `var passphrasePromptMessage: String { ... }`) and
# non-String fields (Bool flags, key references) are ignored.
#
# Usage:
#   scripts/check-sensitive-state-lock.sh [allowlist] [dir ...]

set -uo pipefail

allowlist="${1:-scripts/sensitive-state-lock-allowlist.txt}"
shift || true
dirs=("$@")
if [[ ${#dirs[@]} -eq 0 ]]; then
  dirs=(
    "MacPGP/MacPGP"
    "MacPGP/Shared"
    "MacPGP/ShareExtension"
    "MacPGP/QuickLookExtension"
    "MacPGP/FinderSyncExtension"
    "MacPGP/ThumbnailExtension"
  )
fi

python3 - "$allowlist" "${dirs[@]}" <<'PY'
import os, re, sys

allowlist_path = sys.argv[1]
roots = sys.argv[2:]

allow = set()
if os.path.isfile(allowlist_path):
    with open(allowlist_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # "path # reason" -> path
            allow.add(line.split("#", 1)[0].strip())

# A STORED passphrase String property: `var ...passphrase... : String` or
# `var ...passphrase... = ""`. Excludes computed properties (trailing `{`).
prop = re.compile(r'\bvar\s+\w*[Pp]assphrase\w*\s*(:\s*String\b|=\s*")')
# Markers that constitute an explicit lock/dismiss policy.
markers = ("handleLock", ".macPGPDidLock", "macPGPDidLock", "onDisappear")

offenders = []
unused_allow = set(allow)

for root in roots:
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8") as fh:
                    text = fh.read()
            except OSError:
                continue

            has_prop = False
            for line in text.splitlines():
                if "{" in line:  # computed property / closure, not a stored field
                    continue
                if prop.search(line):
                    has_prop = True
                    break
            if not has_prop:
                continue

            rel = path
            if rel in allow:
                unused_allow.discard(rel)
                continue

            if any(m in text for m in markers):
                continue

            offenders.append(rel)

status = 0
if offenders:
    status = 1
    print("Passphrase-bearing types without an explicit lock policy:")
    for o in sorted(offenders):
        print(f"  {o}")
    print("Add handleLock()/.macPGPDidLock handling, or allowlist with a reason in")
    print(f"  {allowlist_path}")

if unused_allow:
    status = 1
    print("Stale sensitive-state allowlist entries (no longer match):")
    for o in sorted(unused_allow):
        print(f"  {o}")

if status == 0:
    print("Sensitive-state lock audit passed.")

sys.exit(status)
PY
