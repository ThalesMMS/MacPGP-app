#!/usr/bin/env bash
# Requires Bash 4+ for associative arrays used by the module tests.
# test-manual-testing-guide-modules.sh
#
# Unit tests for the helper modules used by test-manual-testing-guide.sh:
#   scripts/manual-testing-guide/assertions.sh
#   scripts/manual-testing-guide/tracking-table.sh
#   scripts/manual-testing-guide/content-checks.sh
#   scripts/manual-testing-guide/structure-checks.sh
#
# Each module is sourced once; individual functions are exercised with
# controlled fixture files and state. The test meta-framework uses
# T_PASS/T_FAIL/T_FAILURES to track results independently from the module
# globals PASS/FAIL/FAILURES that are reset and inspected per test.
#
# Usage:
#   bash scripts/test-manual-testing-guide-modules.sh
#
# Exit code 0 when all tests pass; 1 otherwise.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "scripts/test-manual-testing-guide-modules.sh requires Bash 4+." >&2
    exit 2
fi

set -uo pipefail

# ---------------------------------------------------------------------------
# Test meta-framework (uses T_* variables so they don't clash with the
# PASS/FAIL/FAILURES globals that the modules under test manipulate).
# ---------------------------------------------------------------------------

T_PASS=0
T_FAIL=0
T_FAILURES=()

t_pass() {
    T_PASS=$((T_PASS + 1))
    echo "  PASS  $1"
}

t_fail() {
    T_FAIL=$((T_FAIL + 1))
    T_FAILURES+=("$1")
    echo "  FAIL  $1"
}

t_assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        t_pass "$description"
    else
        t_fail "$description (expected=$(printf '%q' "$expected"), got=$(printf '%q' "$actual"))"
    fi
}

t_assert_zero() {
    local description="$1"
    local code="$2"
    if [[ "$code" -eq 0 ]]; then
        t_pass "$description"
    else
        t_fail "$description (expected exit 0, got $code)"
    fi
}

t_assert_nonzero() {
    local description="$1"
    local code="$2"
    if [[ "$code" -ne 0 ]]; then
        t_pass "$description"
    else
        t_fail "$description (expected non-zero exit, got 0)"
    fi
}

# ---------------------------------------------------------------------------
# Source modules under test
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/manual-testing-guide/assertions.sh"
source "$SCRIPT_DIR/manual-testing-guide/tracking-table.sh"
source "$SCRIPT_DIR/manual-testing-guide/content-checks.sh"
source "$SCRIPT_DIR/manual-testing-guide/structure-checks.sh"

# ---------------------------------------------------------------------------
# Temporary work directory (cleaned up on exit)
# ---------------------------------------------------------------------------

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Helper: reset the module-level globals before each module-under-test call
# ---------------------------------------------------------------------------

reset_module_state() {
    PASS=0
    FAIL=0
    FAILURES=()
    GUIDE=""
    unset ASSERT_GUIDE_CONTENT 2>/dev/null || true
    unset FAIL_FAST 2>/dev/null || true
    TEST_BLOCK_COUNT=0
    STEPS_COUNT=0
    EXPECTED_COUNT=0
}

# Helper: capture stdout of a command to a temp file while staying in the
# current shell (avoids subshell which would lose global-variable changes).
CAPTURE_FILE="$TMPDIR_ROOT/capture.txt"
captured_output() { cat "$CAPTURE_FILE"; }

# ---------------------------------------------------------------------------
# === assertions.sh: pgp_begin_marker ===
# ---------------------------------------------------------------------------

echo "=== pgp_begin_marker ==="

for label in "MESSAGE" "SIGNED MESSAGE" "PUBLIC KEY BLOCK" "PRIVATE KEY BLOCK" "SIGNATURE"; do
    expected="-----BEGIN PGP ${label}-----"
    actual=$(pgp_begin_marker "$label")
    t_assert_eq "pgp_begin_marker('$label') produces correct format" "$expected" "$actual"
done

# Verify exactly five dashes on each side (not four, not six)
actual=$(pgp_begin_marker "TEST")
t_assert_eq "pgp_begin_marker uses exactly five leading dashes" "-----BEGIN PGP TEST-----" "$actual"

# Arbitrary label passthrough
t_assert_eq "pgp_begin_marker passes arbitrary label verbatim" \
    "-----BEGIN PGP MY CUSTOM LABEL-----" \
    "$(pgp_begin_marker "MY CUSTOM LABEL")"

# ---------------------------------------------------------------------------
# === assertions.sh: should_fail_fast ===
# ---------------------------------------------------------------------------

echo ""
echo "=== should_fail_fast ==="

for truthy in 1 true TRUE yes YES on ON; do
    rc=0; FAIL_FAST="$truthy" should_fail_fast || rc=$?
    t_assert_zero "should_fail_fast returns 0 for FAIL_FAST=$truthy" "$rc"
done

for falsy in 0 false FALSE no NO off OFF "" random; do
    rc=0; FAIL_FAST="$falsy" should_fail_fast || rc=$?
    t_assert_nonzero "should_fail_fast returns 1 for FAIL_FAST=$falsy" "$rc"
done

# Unset FAIL_FAST: defaults to false
rc=0; (unset FAIL_FAST; should_fail_fast) || rc=$?
t_assert_nonzero "should_fail_fast returns 1 when FAIL_FAST is unset (default false)" "$rc"

# ---------------------------------------------------------------------------
# === assertions.sh: pass ===
# ---------------------------------------------------------------------------

echo ""
echo "=== pass ==="

reset_module_state
pass "my description" > "$CAPTURE_FILE"
t_assert_eq "pass increments PASS from 0 to 1" "1" "$PASS"
t_assert_eq "pass echoes formatted PASS line" "  PASS  my description" "$(captured_output)"
t_assert_eq "pass does not increment FAIL" "0" "$FAIL"

reset_module_state
PASS=5
pass "another" > "$CAPTURE_FILE"
t_assert_eq "pass increments PASS from 5 to 6" "6" "$PASS"

reset_module_state
pass "desc with spaces and symbols: [x]" > /dev/null
t_assert_eq "pass preserves description with special characters in counter" "1" "$PASS"

# ---------------------------------------------------------------------------
# === assertions.sh: fail ===
# ---------------------------------------------------------------------------

echo ""
echo "=== fail ==="

reset_module_state
FAIL_FAST=false fail "something broke" > "$CAPTURE_FILE"
t_assert_eq "fail increments FAIL from 0 to 1" "1" "$FAIL"
t_assert_eq "fail echoes formatted FAIL line" "  FAIL  something broke" "$(captured_output)"
t_assert_eq "fail appends message to FAILURES array" "something broke" "${FAILURES[0]}"
t_assert_eq "fail does not increment PASS" "0" "$PASS"

reset_module_state
FAIL=3
FAILURES=("existing")
FAIL_FAST=false fail "second failure" > /dev/null
t_assert_eq "fail increments FAIL from 3 to 4" "4" "$FAIL"
t_assert_eq "fail appends new entry at correct index in FAILURES" "second failure" "${FAILURES[1]}"

# fail exits with status 1 when FAIL_FAST is truthy
rc=0
( PASS=0 FAIL=0 FAILURES=(); FAIL_FAST=true; source "$SCRIPT_DIR/manual-testing-guide/assertions.sh"; fail "fast exit" ) 2>/dev/null || rc=$?
t_assert_eq "fail exits with status 1 when FAIL_FAST=true" "1" "$rc"

# fail does NOT exit when FAIL_FAST is falsy
rc=0
( PASS=0 FAIL=0 FAILURES=(); FAIL_FAST=false; source "$SCRIPT_DIR/manual-testing-guide/assertions.sh"; fail "no exit" ) 2>/dev/null || rc=$?
t_assert_eq "fail does not cause non-zero exit when FAIL_FAST=false" "0" "$rc"

# ---------------------------------------------------------------------------
# === assertions.sh: _grep_guide ===
# ---------------------------------------------------------------------------

echo ""
echo "=== _grep_guide ==="

FIXTURE_GUIDE="$TMPDIR_ROOT/fixture.md"
printf 'hello world\nfoo bar\n' > "$FIXTURE_GUIDE"

# Without ASSERT_GUIDE_CONTENT: reads from $GUIDE
reset_module_state
GUIDE="$FIXTURE_GUIDE"
rc=0; _grep_guide -qF "hello" || rc=$?
t_assert_zero "_grep_guide finds pattern in GUIDE file when ASSERT_GUIDE_CONTENT unset" "$rc"

rc=0; _grep_guide -qF "NOTPRESENT" && rc=0 || rc=$?
t_assert_nonzero "_grep_guide returns non-zero for absent pattern in GUIDE file" "$rc"

# With ASSERT_GUIDE_CONTENT set: reads from that variable instead of GUIDE
reset_module_state
GUIDE="$FIXTURE_GUIDE"
ASSERT_GUIDE_CONTENT="override content only"

rc=0; _grep_guide -qF "override content only" || rc=$?
t_assert_zero "_grep_guide finds pattern in ASSERT_GUIDE_CONTENT when that var is set" "$rc"

rc=0; _grep_guide -qF "hello" && rc=0 || rc=$?
t_assert_nonzero "_grep_guide does not search GUIDE file when ASSERT_GUIDE_CONTENT is set" "$rc"

# ASSERT_GUIDE_CONTENT set to empty string still overrides (variable is set but empty)
reset_module_state
GUIDE="$FIXTURE_GUIDE"
ASSERT_GUIDE_CONTENT=""
rc=0; _grep_guide -qF "hello" && rc=0 || rc=$?
t_assert_nonzero "_grep_guide respects empty ASSERT_GUIDE_CONTENT (no match from empty string)" "$rc"
unset ASSERT_GUIDE_CONTENT

# ---------------------------------------------------------------------------
# === assertions.sh: assert_contains ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_contains ==="

printf '# My Document\nfoo bar baz\n' > "$FIXTURE_GUIDE"

# Pass path
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains "title check" "# My Document" > /dev/null
t_assert_eq "assert_contains passes when fixed-string pattern is found" "1" "$PASS"
t_assert_eq "assert_contains does not record a failure when pattern found" "0" "$FAIL"

# Fail path
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains "missing check" "NOT_PRESENT_PATTERN" > /dev/null
t_assert_eq "assert_contains fails when fixed-string pattern is not found" "1" "$FAIL"
t_assert_eq "assert_contains does not record a pass when pattern missing" "0" "$PASS"
[[ "${FAILURES[0]}" == *"missing check"* ]] \
    && t_pass "assert_contains failure message contains description" \
    || t_fail "assert_contains failure message does not contain description"
[[ "${FAILURES[0]}" == *"NOT_PRESENT_PATTERN"* ]] \
    && t_pass "assert_contains failure message contains pattern" \
    || t_fail "assert_contains failure message does not contain pattern"

# Fixed-string: regex metacharacters treated literally
printf 'line with (parens) and [brackets] here\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains "literal parens" "(parens)" > /dev/null
t_assert_eq "assert_contains treats regex metacharacters as literal characters" "1" "$PASS"

# Fixed-string: dot is literal, not wildcard
printf 'a.b\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains "literal dot" "a.b" > /dev/null
t_assert_eq "assert_contains matches literal dot in pattern" "1" "$PASS"

# ASSERT_GUIDE_CONTENT path: uses variable when set
reset_module_state
GUIDE="$FIXTURE_GUIDE"   # file has "a.b"
ASSERT_GUIDE_CONTENT="completely different content"
assert_contains "content var match" "completely different" > /dev/null
t_assert_eq "assert_contains uses ASSERT_GUIDE_CONTENT when set" "1" "$PASS"
unset ASSERT_GUIDE_CONTENT

# ---------------------------------------------------------------------------
# === assertions.sh: assert_contains_re ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_contains_re ==="

printf 'Last updated: 2024-03-15\nsome other line\n' > "$FIXTURE_GUIDE"

# Pass path
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains_re "date format check" '^Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$' > /dev/null
t_assert_eq "assert_contains_re passes when ERE pattern matches" "1" "$PASS"
t_assert_eq "assert_contains_re does not fail when pattern matches" "0" "$FAIL"

# Fail path
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains_re "no digit sequence" '^[0-9]{10}$' > /dev/null
t_assert_eq "assert_contains_re fails when ERE pattern does not match" "1" "$FAIL"
t_assert_eq "assert_contains_re does not pass when pattern missing" "0" "$PASS"
[[ "${FAILURES[0]}" == *"regex not found"* ]] \
    && t_pass "assert_contains_re failure message includes 'regex not found'" \
    || t_fail "assert_contains_re failure message missing 'regex not found'"
[[ "${FAILURES[0]}" == *'^[0-9]{10}$'* ]] \
    && t_pass "assert_contains_re failure message includes the pattern" \
    || t_fail "assert_contains_re failure message missing the pattern"

# ERE features: alternation
printf 'apple or banana\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains_re "alternation matching first branch" 'apple|cherry' > /dev/null
t_assert_eq "assert_contains_re supports ERE alternation (first branch matches)" "1" "$PASS"

# ERE features: anchors
printf 'start of line\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_contains_re "anchor match" '^start of' > /dev/null
t_assert_eq "assert_contains_re supports ^ anchor" "1" "$PASS"

# ---------------------------------------------------------------------------
# === assertions.sh: assert_not_contains ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_not_contains ==="

printf 'safe content\nno forbidden text\n' > "$FIXTURE_GUIDE"

# Pass path: pattern absent
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_not_contains "absent check" "FORBIDDEN" > /dev/null
t_assert_eq "assert_not_contains passes when pattern is absent" "1" "$PASS"
t_assert_eq "assert_not_contains does not fail when pattern absent" "0" "$FAIL"

# Fail path: pattern present
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_not_contains "present check" "safe content" > /dev/null
t_assert_eq "assert_not_contains fails when pattern is present" "1" "$FAIL"
t_assert_eq "assert_not_contains does not pass when pattern present" "0" "$PASS"
[[ "${FAILURES[0]}" == *"unexpected pattern found"* ]] \
    && t_pass "assert_not_contains failure message includes 'unexpected pattern found'" \
    || t_fail "assert_not_contains failure message missing 'unexpected pattern found'"

# Fixed-string: dot matches literal dot only
printf 'a.b\naxb\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_not_contains "literal dot present" "a.b" > /dev/null
t_assert_eq "assert_not_contains treats dot as literal (file has 'a.b', so fails)" "1" "$FAIL"

# "axb" matches regex a.b but NOT fixed string a.b: assert_not_contains should pass
printf 'axb\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_not_contains "dot not matched by 'axb'" "a.b" > /dev/null
t_assert_eq "assert_not_contains treats dot as literal (file has 'axb', not 'a.b', so passes)" "1" "$PASS"

# ---------------------------------------------------------------------------
# === assertions.sh: assert_count_gte ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_count_gte ==="

printf -- '- [ ] item one\n- [ ] item two\n- [ ] item three\n' > "$FIXTURE_GUIDE"

reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_count_gte "at least 2 unchecked" "- [ ]" 2 > /dev/null
t_assert_eq "assert_count_gte passes when count (3) exceeds minimum (2)" "1" "$PASS"

reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_count_gte "exactly meets minimum" "- [ ]" 3 > /dev/null
t_assert_eq "assert_count_gte passes when count (3) equals minimum (3)" "1" "$PASS"

reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_count_gte "below minimum" "- [ ]" 4 > /dev/null
t_assert_eq "assert_count_gte fails when count (3) is below minimum (4)" "1" "$FAIL"
[[ "${FAILURES[0]}" == *"found 3"* ]] \
    && t_pass "assert_count_gte failure message shows actual count" \
    || t_fail "assert_count_gte failure message missing actual count"
[[ "${FAILURES[0]}" == *"required >= 4"* ]] \
    && t_pass "assert_count_gte failure message shows required minimum" \
    || t_fail "assert_count_gte failure message missing required minimum"
[[ "${FAILURES[0]}" == *"- [ ]"* ]] \
    && t_pass "assert_count_gte failure message includes the pattern" \
    || t_fail "assert_count_gte failure message missing the pattern"

# assert_count_gte honors ASSERT_GUIDE_CONTENT when set.
printf 'no matches here\n' > "$FIXTURE_GUIDE"
reset_module_state
GUIDE="$FIXTURE_GUIDE"
ASSERT_GUIDE_CONTENT="- [ ] from content var"   # 1 match here; file has 0
assert_count_gte "count from content var" "- [ ]" 1 > /dev/null
t_assert_eq "assert_count_gte uses ASSERT_GUIDE_CONTENT when set" "1" "$PASS"
t_assert_eq "assert_count_gte has no failures when scoped content satisfies minimum" "0" "$FAIL"
unset ASSERT_GUIDE_CONTENT

# Zero minimum edge case: always passes when count >= 0
reset_module_state
GUIDE="$FIXTURE_GUIDE"
assert_count_gte "zero minimum" "completely absent pattern" 0 > /dev/null
t_assert_eq "assert_count_gte passes when minimum is 0 (count is always >= 0)" "1" "$PASS"

# ---------------------------------------------------------------------------
# === tracking-table.sh: tracking_feature_area ===
# ---------------------------------------------------------------------------

echo ""
echo "=== tracking_feature_area ==="

declare -A EXPECTED_AREAS=(
    ["IS-FRESH"]="Fresh install verification"
    ["IS-UPGRADE"]="Upgrade install verification"
    ["KS-EMPTY"]="Keyring state: empty"
    ["KS-POPULATED"]="Keyring state: populated"
    ["CORE-KEY"]="Key management"
    ["CORE-ENCDEC"]="Encryption and decryption"
    ["CORE-SIGNVERIFY"]="Sign and verify screens"
    ["CORE-KEYSERVER"]="Keyserver operations"
    ["CORE-SETTINGS"]="Settings and preferences"
    ["CORE-SVC-DEC"]="Services: decrypt"
    ["CORE-SVC-SIGN"]="Services: sign"
    ["CORE-BACKUP"]="Backup and restore"
    ["EXT-FINDER"]="FinderSyncExtension"
    ["EXT-QL"]="QuickLookExtension"
    ["EXT-THUMB"]="ThumbnailExtension"
    ["EXT-SHARE"]="ShareExtension exclusion"
    ["EXT-CROSS"]="Cross-extension data flow"
    ["CROSS-E2E"]="Full encrypt/decrypt/sign workflow"
    ["CROSS-BACKUP"]="Backup/restore integration"
    ["CROSS-KNOWN"]="Known issue verification"
    ["CROSS-SVC"]="Cross-app Services and shortcuts"
    ["QA-BUGS"]="Bugs found and sign-off"
)

for id in "${!EXPECTED_AREAS[@]}"; do
    actual=$(tracking_feature_area "$id")
    t_assert_eq "tracking_feature_area maps $id correctly" "${EXPECTED_AREAS[$id]}" "$actual"
done

t_assert_eq "tracking_feature_area maps all 22 known IDs" "22" "${#EXPECTED_AREAS[@]}"

# Unknown ID: returns non-zero and produces no output
rc=0; out=$(tracking_feature_area "UNKNOWN-ID") || rc=$?
t_assert_nonzero "tracking_feature_area returns non-zero for unknown ID" "$rc"
t_assert_eq "tracking_feature_area produces no output for unknown ID" "" "$out"

# Case sensitivity
rc=0; tracking_feature_area "is-fresh" || rc=$?
t_assert_nonzero "tracking_feature_area is case-sensitive (lowercase fails)" "$rc"

rc=0; tracking_feature_area "core-key" || rc=$?
t_assert_nonzero "tracking_feature_area is case-sensitive (core-key fails)" "$rc"

# Partial match must not succeed
rc=0; tracking_feature_area "CORE" || rc=$?
t_assert_nonzero "tracking_feature_area rejects partial ID (prefix 'CORE')" "$rc"

rc=0; tracking_feature_area "IS" || rc=$?
t_assert_nonzero "tracking_feature_area rejects partial ID (prefix 'IS')" "$rc"

# Empty string
rc=0; tracking_feature_area "" || rc=$?
t_assert_nonzero "tracking_feature_area returns non-zero for empty string" "$rc"

# ---------------------------------------------------------------------------
# === content-checks.sh ===
# ---------------------------------------------------------------------------

echo ""
echo "=== content-checks.sh ==="

GOOD_CONTENT_GUIDE="$TMPDIR_ROOT/good_content_guide.md"
cat > "$GOOD_CONTENT_GUIDE" << 'EOF'
# MacPGP Release QA Matrix
Release target: MacPGP v1.0 App Store build
Document version:
Last updated: 2026-04-25
Scope reference:
docs/V1_SCOPE.md

## QA Sign-Off
QA lead reviewed the release scope before testing
QA lead confirmed all required install states were tested
QA lead confirmed all required keyring states were tested
QA lead confirmed critical findings are linked as GitHub issues
QA lead approved this run for release consideration
QA lead:
Date:
Release build/archive:

## Legend and Bug Linking
Pass: mark
Fail: mark
Blocked: mark
Not run: mark
Linked Issues:
Retests:

## Part 1: Prerequisites
### 1.1 Environment
### 1.2 Build Instructions
### 1.3 Services Setup
### 1.4 State Setup Checklist
### 1.5 Keyring Reset Procedure
### 1.6 Empty Keyring Definition
### 1.7 Populated Keyring Definition
group.com.macpgp.shared
~/Library/Application Support/MacPGP/Keyring/
~/Library/Group Containers/group.com.macpgp.shared/keys.pgp
--reset-keyring
Destructive reset warning:
APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"
/System/Library/CoreServices/pbs -flush
BEGIN PGP MESSAGE (example marker)
BEGIN PGP SIGNED MESSAGE (example marker)
BEGIN PGP PUBLIC KEY BLOCK (example marker)
BEGIN PGP PRIVATE KEY BLOCK (example marker)
BEGIN PGP SIGNATURE (example marker)
MACPGP-ENC-V1

## Part 2: Install State Tests
### IS-FRESH: Fresh Install
### IS-UPGRADE: Upgrade Install

## Part 3: Core App Features
### CORE-KEY: Key Management
### CORE-ENCDEC: Encryption and Decryption
### CORE-SIGNVERIFY: Sign and Verify Screens
### CORE-KEYSERVER: Keyserver Operations
### CORE-SETTINGS: Settings and Preferences
Primary main-window strings display in the selected language after relaunch.
Menu item text displays in the selected language after relaunch.
Services menu labels display in the selected language
Extension-facing strings display in the selected language
### CORE-SVC-DEC: Decrypt Services
### CORE-SVC-SIGN: Sign Services
### CORE-BACKUP: Key Backup and Recovery
#### CORE-KEY-1.1 through 1.3: Generate RSA Key (2048, 3072, and 4096 Bits)
2048 bits
3072 bits
4096 bits
#### CORE-SVC-DEC-1.1: Basic Decryption
#### CORE-SVC-DEC-1.2: Wrong Passphrase
#### CORE-SVC-DEC-1.3: Invalid PGP Message
#### CORE-SVC-DEC-1.4: No Secret Keys
#### CORE-SVC-DEC-1.5: No Text Selected
#### CORE-SVC-DEC-1.6: Cancel Operation
#### CORE-SVC-SIGN-1.1: Basic Signing
#### CORE-SVC-SIGN-1.2: Wrong Passphrase
#### CORE-SVC-SIGN-1.3: No Secret Keys
#### CORE-SVC-SIGN-1.4: No Text Selected
#### CORE-SVC-SIGN-1.5: Cancel Operation
#### CORE-BACKUP-5.1: Create Unencrypted Backup
#### CORE-BACKUP-5.2: Create Encrypted Backup
#### CORE-BACKUP-6.1: Restore Unencrypted Backup
#### CORE-BACKUP-6.2: Restore Encrypted Backup
#### CORE-BACKUP-7.1: Generate Paper Backup
#### CORE-BACKUP-7.2: Paper Backup for Large Key
#### CORE-BACKUP-8.1: Backup Reminder Settings
#### CORE-BACKUP-8.2: Backup Reminder Logic
#### CORE-BACKUP-9.2: Invalid Backup File Handling
#### CORE-BACKUP-9.3: Corrupted Encrypted Backup
Decryption failed
No secret keys available
No text selected
Invalid PGP message
Signing failed
Invalid backup file format

## Part 4: Extensions
### EXT-FINDER: FinderSyncExtension
FinderSyncExtension.appex
### EXT-QL: QuickLookExtension
QuickLookExtension.appex
### EXT-THUMB: ThumbnailExtension
ThumbnailExtension.appex
### EXT-SHARE: ShareExtension Exclusion
ShareExtension.appex must not be present in release bundle
scripts/check-no-shareextension-in-release.sh
#49
#### EXT-SHARE-1.1: Release Bundle Does Not Embed ShareExtension
#### EXT-SHARE-1.2: Release Guardrail Script
### EXT-CROSS: Cross-Extension Integration

## Part 5: Cross-Cutting Scenarios
### CROSS-E2E-1.1: Full Two-Key Round Trip
### CROSS-BACKUP-1.1: Backup, Delete, Restore, and Revalidate
### CROSS-KNOWN-1.2: Existing Issue Verification Checklist
| `#4` | fixture |
| `#5` | fixture |
| `#9` | fixture |
| `#10` | fixture |
| `#16` | fixture |
| `#43` | fixture |
| `#48` | fixture |
| `#49` | fixture |
## Bug Tracking and Sign-Off
### Bugs Found
| Issue Number | Test ID | Description | Severity | Linked GitHub Issue |
### Known Issues Verification
| Known Issue Ref | Test ID | Expected Current Behavior or Workaround | Result | Follow-Up |
### Filing New Bugs
**Summary**
**Current repo evidence**
**What needs to happen**
**Acceptance criteria**
### Final Release QA Sign-Off
All critical paths pass.
ShareExtension exclusion verified.
QA lead approval recorded with date.

#### Decrypt Service
#### Sign Service
#### System Integration
For Services troubleshooting, see Section 1.3 (Services Setup).
Bug filing rules:
Empty Keyring and Populated Keyring states tested.
EOF

BROKEN_CONTENT_GUIDE="$TMPDIR_ROOT/broken_content_guide.md"
printf 'Broken guide fixture\n' > "$BROKEN_CONTENT_GUIDE"

reset_module_state
GUIDE="$GOOD_CONTENT_GUIDE"
run_document_metadata_checks > /dev/null
t_assert_eq "run_document_metadata_checks passes deterministic good fixture" "6" "$PASS"
t_assert_eq "run_document_metadata_checks has no good-fixture failures" "0" "$FAIL"

reset_module_state
GUIDE="$GOOD_CONTENT_GUIDE"
run_qa_signoff_checks > /dev/null
t_assert_eq "run_qa_signoff_checks passes deterministic good fixture" "9" "$PASS"
t_assert_eq "run_qa_signoff_checks has no good-fixture failures" "0" "$FAIL"

reset_module_state
GUIDE="$GOOD_CONTENT_GUIDE"
run_content_checks_before_structure > /dev/null
t_assert_eq "run_content_checks_before_structure passes deterministic good fixture" "121" "$PASS"
t_assert_eq "run_content_checks_before_structure has no good-fixture failures" "0" "$FAIL"

reset_module_state
GUIDE="$GOOD_CONTENT_GUIDE"
run_content_checks_after_structure > /dev/null
t_assert_eq "run_content_checks_after_structure passes deterministic good fixture" "6" "$PASS"
t_assert_eq "run_content_checks_after_structure has no good-fixture failures" "0" "$FAIL"

reset_module_state
GUIDE="$BROKEN_CONTENT_GUIDE"
run_document_metadata_checks > /dev/null
t_assert_eq "run_document_metadata_checks has no broken-fixture passes" "0" "$PASS"
t_assert_eq "run_document_metadata_checks reports deterministic broken-fixture failures" "6" "$FAIL"
[[ "${FAILURES[0]}" == *"Document title is MacPGP Release QA Matrix"* ]] \
    && t_pass "run_document_metadata_checks records expected broken-fixture failure" \
    || t_fail "run_document_metadata_checks missing expected broken-fixture failure"

reset_module_state
GUIDE="$BROKEN_CONTENT_GUIDE"
run_qa_signoff_checks > /dev/null
t_assert_eq "run_qa_signoff_checks has no broken-fixture passes" "0" "$PASS"
t_assert_eq "run_qa_signoff_checks reports deterministic broken-fixture failures" "9" "$FAIL"
[[ "${FAILURES[0]}" == *"QA Sign-Off section exists"* ]] \
    && t_pass "run_qa_signoff_checks records expected broken-fixture failure" \
    || t_fail "run_qa_signoff_checks missing expected broken-fixture failure"

reset_module_state
GUIDE="$BROKEN_CONTENT_GUIDE"
run_content_checks_before_structure > /dev/null
t_assert_eq "run_content_checks_before_structure reports deterministic broken-fixture passes" "6" "$PASS"
t_assert_eq "run_content_checks_before_structure reports deterministic broken-fixture failures" "115" "$FAIL"
[[ "${FAILURES[0]}" == *"Legend section exists"* ]] \
    && t_pass "run_content_checks_before_structure records expected broken-fixture failure" \
    || t_fail "run_content_checks_before_structure missing expected broken-fixture failure"

reset_module_state
GUIDE="$BROKEN_CONTENT_GUIDE"
run_content_checks_after_structure > /dev/null
t_assert_eq "run_content_checks_after_structure has no broken-fixture passes" "0" "$PASS"
t_assert_eq "run_content_checks_after_structure reports deterministic broken-fixture failures" "6" "$FAIL"
[[ "${FAILURES[0]}" == *"Decrypt Service verification checklist header present"* ]] \
    && t_pass "run_content_checks_after_structure records expected broken-fixture failure" \
    || t_fail "run_content_checks_after_structure missing expected broken-fixture failure"

# ---------------------------------------------------------------------------
# === tracking-table.sh: assert_tracking_row ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_tracking_row ==="

TRACKING_GUIDE="$TMPDIR_ROOT/tracking_fixture.md"
cat > "$TRACKING_GUIDE" << 'EOF'
## Test Execution Tracking

| Test ID | Feature Area | Install State | Keyring State | Result | Tester | Date | Linked Issues |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IS-FRESH | Fresh install verification | Fresh | Empty | | | | |
| CORE-KEY | Key management | Fresh | Empty | | | | |
| EXT-SHARE | ShareExtension exclusion | Release candidate | N/A | | | | |
| QA-BUGS | Bugs found and sign-off | Release candidate | Empty | | | | |
EOF

# Matching row is found: passes
reset_module_state
GUIDE="$TRACKING_GUIDE"
ASSERT_GUIDE_CONTENT=$(cat "$TRACKING_GUIDE")
assert_tracking_row "IS-FRESH" "Fresh" "Empty" > /dev/null
t_assert_eq "assert_tracking_row passes for IS-FRESH / Fresh / Empty" "1" "$PASS"
t_assert_eq "assert_tracking_row has no failures for IS-FRESH / Fresh / Empty" "0" "$FAIL"
unset ASSERT_GUIDE_CONTENT

# Special EXT-SHARE row with "Release candidate" and "N/A"
reset_module_state
GUIDE="$TRACKING_GUIDE"
ASSERT_GUIDE_CONTENT=$(cat "$TRACKING_GUIDE")
assert_tracking_row "EXT-SHARE" "Release candidate" "N/A" > /dev/null
t_assert_eq "assert_tracking_row passes for EXT-SHARE / Release candidate / N/A" "1" "$PASS"
unset ASSERT_GUIDE_CONTENT

# Row present but different install/keyring state: fails
reset_module_state
GUIDE="$TRACKING_GUIDE"
ASSERT_GUIDE_CONTENT=$(cat "$TRACKING_GUIDE")
assert_tracking_row "IS-FRESH" "Upgrade" "Empty" > /dev/null   # file has "Fresh", not "Upgrade"
t_assert_eq "assert_tracking_row fails when install state does not match" "1" "$FAIL"
unset ASSERT_GUIDE_CONTENT

# Feature area must be derived from tracking ID (wrong area not in file)
reset_module_state
GUIDE="$TRACKING_GUIDE"
ASSERT_GUIDE_CONTENT=$(cat "$TRACKING_GUIDE")
assert_tracking_row "CORE-KEY" "Fresh" "Empty" > /dev/null
t_assert_eq "assert_tracking_row passes with correct feature area derived from ID" "1" "$PASS"
unset ASSERT_GUIDE_CONTENT

# Unknown tracking ID calls fail with "Unknown tracking ID" message
reset_module_state
GUIDE="$TRACKING_GUIDE"
ASSERT_GUIDE_CONTENT=$(cat "$TRACKING_GUIDE")
assert_tracking_row "BOGUS-ID" "Fresh" "Empty" > /dev/null
t_assert_eq "assert_tracking_row calls fail for unknown tracking ID" "1" "$FAIL"
[[ "${FAILURES[0]}" == *"Unknown tracking ID"* ]] \
    && t_pass "assert_tracking_row failure for unknown ID contains 'Unknown tracking ID'" \
    || t_fail "assert_tracking_row failure for unknown ID missing 'Unknown tracking ID'"
[[ "${FAILURES[0]}" == *"BOGUS-ID"* ]] \
    && t_pass "assert_tracking_row failure for unknown ID contains the bogus ID" \
    || t_fail "assert_tracking_row failure for unknown ID missing the bogus ID"
unset ASSERT_GUIDE_CONTENT

# ---------------------------------------------------------------------------
# === structure-checks.sh: assert_current_test_block_structure ===
# ---------------------------------------------------------------------------

echo ""
echo "=== assert_current_test_block_structure ==="

# Empty header: function returns immediately, no side effects
reset_module_state
assert_current_test_block_structure "" 1 1 > /dev/null
t_assert_eq "assert_current_test_block_structure is a no-op when header is empty" "0" "$TEST_BLOCK_COUNT"
t_assert_eq "assert_current_test_block_structure does not call pass/fail on empty header" "0" "$PASS"
t_assert_eq "assert_current_test_block_structure does not call fail on empty header" "0" "$FAIL"

# Matched pair (steps=1, expected=1): passes
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-1.1: Some Test" 1 1 > /dev/null
t_assert_eq "assert_current_test_block_structure passes for steps=1, expected=1" "1" "$PASS"
t_assert_eq "assert_current_test_block_structure no failure for balanced pair" "0" "$FAIL"
t_assert_eq "assert_current_test_block_structure increments TEST_BLOCK_COUNT to 1" "1" "$TEST_BLOCK_COUNT"
t_assert_eq "assert_current_test_block_structure adds steps to STEPS_COUNT" "1" "$STEPS_COUNT"
t_assert_eq "assert_current_test_block_structure adds expected to EXPECTED_COUNT" "1" "$EXPECTED_COUNT"

# Larger balanced pair (steps=3, expected=3): passes
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-2.1: Another Test" 3 3 > /dev/null
t_assert_eq "assert_current_test_block_structure passes for steps=3, expected=3" "1" "$PASS"
t_assert_eq "assert_current_test_block_structure accumulates STEPS_COUNT to 3" "3" "$STEPS_COUNT"
t_assert_eq "assert_current_test_block_structure accumulates EXPECTED_COUNT to 3" "3" "$EXPECTED_COUNT"

# Mismatched (steps > expected): fails
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-3.1: Bad Test" 2 1 > /dev/null
t_assert_eq "assert_current_test_block_structure fails when steps(2) != expected(1)" "1" "$FAIL"
t_assert_eq "assert_current_test_block_structure does not pass for mismatch" "0" "$PASS"
[[ "${FAILURES[0]}" == *"Steps=2"* ]] \
    && t_pass "assert_current_test_block_structure failure message includes 'Steps=2'" \
    || t_fail "assert_current_test_block_structure failure message missing 'Steps=2'"
[[ "${FAILURES[0]}" == *"Expected=1"* ]] \
    && t_pass "assert_current_test_block_structure failure message includes 'Expected=1'" \
    || t_fail "assert_current_test_block_structure failure message missing 'Expected=1'"
[[ "${FAILURES[0]}" == *"#### CORE-KEY-3.1: Bad Test"* ]] \
    && t_pass "assert_current_test_block_structure failure message includes header text" \
    || t_fail "assert_current_test_block_structure failure message missing header text"

# Mismatched (expected > steps): also fails
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-3.2: Reversed Mismatch" 1 2 > /dev/null
t_assert_eq "assert_current_test_block_structure fails when expected(2) > steps(1)" "1" "$FAIL"

# Zero steps, non-zero expected: fails
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-4.1: No Steps" 0 1 > /dev/null
t_assert_eq "assert_current_test_block_structure fails when steps=0" "1" "$FAIL"

# Non-zero steps, zero expected: fails
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-4.2: No Expected" 1 0 > /dev/null
t_assert_eq "assert_current_test_block_structure fails when expected=0" "1" "$FAIL"

# Both zero: fails (neither meets >= 1 requirement)
reset_module_state
assert_current_test_block_structure "#### CORE-KEY-5.1: Empty Block" 0 0 > /dev/null
t_assert_eq "assert_current_test_block_structure fails when both steps and expected are 0" "1" "$FAIL"

# Global accumulators across multiple sequential calls
reset_module_state
assert_current_test_block_structure "#### A-1.1: First" 1 1 > /dev/null
assert_current_test_block_structure "#### A-1.2: Second" 2 2 > /dev/null
t_assert_eq "assert_current_test_block_structure TEST_BLOCK_COUNT accumulates across two calls" "2" "$TEST_BLOCK_COUNT"
t_assert_eq "assert_current_test_block_structure STEPS_COUNT accumulates (1+2=3)" "3" "$STEPS_COUNT"
t_assert_eq "assert_current_test_block_structure EXPECTED_COUNT accumulates (1+2=3)" "3" "$EXPECTED_COUNT"
t_assert_eq "assert_current_test_block_structure PASS count is 2 for two good blocks" "2" "$PASS"

# Even a failing block still accumulates counts
reset_module_state
assert_current_test_block_structure "#### B-1.1: Good" 1 1 > /dev/null
assert_current_test_block_structure "#### B-1.2: Bad" 2 0 > /dev/null
t_assert_eq "assert_current_test_block_structure accumulates TEST_BLOCK_COUNT even for failing block" "2" "$TEST_BLOCK_COUNT"
t_assert_eq "assert_current_test_block_structure accumulates STEPS_COUNT for failing block (1+2=3)" "3" "$STEPS_COUNT"
t_assert_eq "assert_current_test_block_structure accumulates EXPECTED_COUNT for failing block (1+0=1)" "1" "$EXPECTED_COUNT"

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Results: $T_PASS passed, $T_FAIL failed"
echo "============================================"

if [[ "$T_FAIL" -gt 0 ]]; then
    echo ""
    echo "Failed assertions:"
    for f in "${T_FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "All assertions passed."
exit 0
