#!/usr/bin/env bash
# Source audit that flags hard-coded user-facing English string literals in
# release-visible SwiftUI views (issues #131, #148).
#
# It flags literals passed to common user-facing APIs (Text, Label, Button,
# Toggle, Picker, Section, navigationTitle, help, ContentUnavailableView) that are
# NOT routed through String(localized:)/LocalizedStringKey/NSLocalizedString.
#
# Dotted localization keys (e.g. Text("quicklook.open_in_app")) are treated as
# keys, not English copy, so normal key usage is not flagged (issue #148).
#
# Intentional verbatim/technical strings and the not-yet-localized backlog are
# tracked in scripts/localization-allowlist.txt. Each entry is THREE tab-separated
# columns: 'relative/path.swift<TAB>literal<TAB>category', where category is one of
#   verbatim   - protocol / file-format / technical, must NOT be localized
#   userdata   - interpolated user/key data, not standalone copy
#   debug      - debug/preview/log-only, not shipped to end users
#   backlog    - release-visible English pending human translation (issue #148)
# A release-visible sentence should ultimately be category 'backlog' and then
# converted + removed, leaving only verbatim/userdata/debug exceptions.
#
# By default CI scans the Main App (Core/Features/Navigation/Shared) plus every
# shipped extension source tree, so no shipped bundle is unscanned (issue #148).
#
# Usage:
#   scripts/check-hardcoded-strings.sh [allowlist] [dir ...]

set -uo pipefail

allowlist="${1:-scripts/localization-allowlist.txt}"
shift || true
dirs=("$@")
if [[ ${#dirs[@]} -eq 0 ]]; then
  dirs=(
    "MacPGP/MacPGP/Core"
    "MacPGP/MacPGP/Features"
    "MacPGP/MacPGP/Navigation"
    "MacPGP/MacPGP/Shared"
    "MacPGP/FinderSyncExtension"
    "MacPGP/QuickLookExtension"
    "MacPGP/ThumbnailExtension"
    "MacPGP/ShareExtension"
  )
fi

python3 - "$allowlist" "${dirs[@]}" <<'PY'
import os, re, sys

allowlist_path = sys.argv[1]
roots = sys.argv[2:]

VALID_CATEGORIES = {"verbatim", "userdata", "debug", "backlog"}

allow = set()
allowlist_errors = []
if os.path.isfile(allowlist_path):
    with open(allowlist_path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            # Require path<TAB>literal<TAB>category so every entry carries a
            # machine-readable category (issue #148).
            if len(parts) < 3 or not parts[0] or parts[2] not in VALID_CATEGORIES:
                allowlist_errors.append((lineno, line))
                continue
            # Match on path+literal; the category is metadata for humans/tooling.
            allow.add(parts[0] + "\t" + parts[1])

# User-facing APIs whose first string-literal argument is shown to the user.
patterns = [
    re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bLabel\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bButton\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bToggle\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bPicker\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bSection\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.help\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bContentUnavailableView\(\s*"((?:[^"\\]|\\.)*)"'),
]

# Lines already routed through a localization API are fine.
localized_markers = ("String(localized:", "LocalizedStringKey", "NSLocalizedString", "verbatim:")

# A lowercase identifier whose tokens are joined by '.' or '_' is a localization
# key, not English copy, e.g. Text("quicklook.open_in_app") or
# Text("quicklook_open_in_app_to_decrypt"). English UI copy uses spaces, capitals,
# and punctuation and never matches this, so the exemption cannot hide real copy
# (issue #148). A single bare word like "or"/"OK" is NOT exempted.
dotted_key = re.compile(r'[a-z][a-z0-9]*(?:[._][a-z0-9]+)+\Z')

hits = []
for root in roots:
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path)
            with open(path, encoding="utf-8") as fh:
                for lineno, line in enumerate(fh, 1):
                    if any(marker in line for marker in localized_markers):
                        continue
                    for pat in patterns:
                        for literal in pat.findall(line):
                            if not literal.strip():
                                continue
                            # Ignore purely technical tokens (no letters).
                            if not re.search(r'[A-Za-z]', literal):
                                continue
                            # Ignore dotted localization keys (precision, issue #148).
                            if dotted_key.match(literal):
                                continue
                            key = "%s\t%s" % (rel, literal)
                            if key in allow:
                                continue
                            hits.append((rel, lineno, literal))

status = 0

if allowlist_errors:
    print("::error::%d malformed allowlist entr(y/ies) in %s (need 'path<TAB>literal<TAB>category', category in %s):"
          % (len(allowlist_errors), allowlist_path, sorted(VALID_CATEGORIES)), file=sys.stderr)
    for lineno, line in allowlist_errors:
        print("    %s:%d: %r" % (allowlist_path, lineno, line), file=sys.stderr)
    status = 1

if hits:
    print("::error::Found %d unapproved hard-coded user-facing string(s):" % len(hits), file=sys.stderr)
    for rel, lineno, literal in hits:
        print("    %s:%d: \"%s\"" % (rel, lineno, literal), file=sys.stderr)
    print("Localize them via String(localized:), or add a categorized entry to %s as 'path<TAB>literal<TAB>category'." % allowlist_path, file=sys.stderr)
    status = 1

if status:
    sys.exit(status)

print("Hard-coded string audit passed: no unapproved user-facing literals in %s." % ", ".join(roots))
PY
