#!/usr/bin/env bash
# test-manual-testing-guide.sh
#
# Validates the structural integrity and content consistency of
# docs/MANUAL-TESTING-GUIDE.md.
#
# Usage:
#   bash scripts/test-manual-testing-guide.sh [path/to/MANUAL-TESTING-GUIDE.md]
#
# Exit code 0 when all assertions pass; non-zero on the first failure or
# after collecting all failures depending on the FAIL_FAST variable.

set -uo pipefail

GUIDE="${1:-docs/MANUAL-TESTING-GUIDE.md}"
PASS=0
FAIL=0
FAILURES=()

pgp_begin_marker() {
    printf -- '%s%s %s%s' '-----' 'BEGIN PGP' "$1" '-----'
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
    PASS=$((PASS + 1))
    echo "  PASS  $1"
}

should_fail_fast() {
    case "${FAIL_FAST:-false}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    echo "  FAIL  $1"
    if should_fail_fast; then
        exit 1
    fi
}

assert_contains() {
    local description="$1"
    local pattern="$2"
    if grep -qF -- "$pattern" "$GUIDE"; then
        pass "$description"
    else
        fail "$description (pattern not found: $pattern)"
    fi
}

assert_contains_re() {
    local description="$1"
    local pattern="$2"
    if grep -qE -- "$pattern" "$GUIDE"; then
        pass "$description"
    else
        fail "$description (regex not found: $pattern)"
    fi
}

assert_not_contains() {
    local description="$1"
    local pattern="$2"
    if grep -qF -- "$pattern" "$GUIDE"; then
        fail "$description (unexpected pattern found: $pattern)"
    else
        pass "$description"
    fi
}

assert_count_gte() {
    local description="$1"
    local pattern="$2"
    local min="$3"
    local count
    count=$(grep -cF -- "$pattern" "$GUIDE" 2>/dev/null || true)
    if [[ "$count" -ge "$min" ]]; then
        pass "$description (found $count, required >= $min)"
    else
        fail "$description (found $count, required >= $min for pattern: $pattern)"
    fi
}

assert_current_test_block_structure() {
    local header="$1"
    local steps_count="$2"
    local expected_count="$3"

    [[ -z "$header" ]] && return

    TEST_BLOCK_COUNT=$((TEST_BLOCK_COUNT + 1))
    STEPS_COUNT=$((STEPS_COUNT + steps_count))
    EXPECTED_COUNT=$((EXPECTED_COUNT + expected_count))

    if [[ "$steps_count" -ge 1 && "$expected_count" -ge 1 && "$steps_count" -eq "$expected_count" ]]; then
        pass "Test block has paired Steps/Expected sections: $header"
    else
        fail "Test block has unpaired Steps/Expected sections: $header (Steps=$steps_count, Expected=$expected_count)"
    fi
}

tracking_feature_area() {
    case "$1" in
        IS-FRESH) echo "Fresh install verification" ;;
        IS-UPGRADE) echo "Upgrade install verification" ;;
        KS-EMPTY) echo "Keyring state: empty" ;;
        KS-POPULATED) echo "Keyring state: populated" ;;
        CORE-KEY) echo "Key management" ;;
        CORE-ENCDEC) echo "Encryption and decryption" ;;
        CORE-SIGNVERIFY) echo "Sign and verify screens" ;;
        CORE-KEYSERVER) echo "Keyserver operations" ;;
        CORE-SETTINGS) echo "Settings and preferences" ;;
        CORE-SVC-DEC) echo "Services: decrypt" ;;
        CORE-SVC-SIGN) echo "Services: sign" ;;
        CORE-BACKUP) echo "Backup and restore" ;;
        EXT-FINDER) echo "FinderSyncExtension" ;;
        EXT-QL) echo "QuickLookExtension" ;;
        EXT-THUMB) echo "ThumbnailExtension" ;;
        EXT-SHARE) echo "ShareExtension exclusion" ;;
        EXT-CROSS) echo "Cross-extension data flow" ;;
        CROSS-E2E) echo "Full encrypt/decrypt/sign workflow" ;;
        CROSS-BACKUP) echo "Backup/restore integration" ;;
        CROSS-KNOWN) echo "Known issue verification" ;;
        CROSS-SVC) echo "Cross-app Services and shortcuts" ;;
        QA-BUGS) echo "Bugs found and sign-off" ;;
        *) return 1 ;;
    esac
}

assert_tracking_row() {
    local id="$1"
    local install_state="$2"
    local keyring_state="$3"
    local feature_area

    if ! feature_area=$(tracking_feature_area "$id"); then
        fail "Unknown tracking ID in validator: $id"
        return
    fi

    assert_contains \
        "Tracking table contains state row: $id / $install_state / $keyring_state" \
        "| $id | $feature_area | $install_state | $keyring_state |"
}

# ---------------------------------------------------------------------------
# Guard: file must exist and be readable
# ---------------------------------------------------------------------------

echo "Testing: $GUIDE"
echo ""

if [[ ! -f "$GUIDE" || ! -r "$GUIDE" ]]; then
    echo "FATAL: Guide file not found or not readable: $GUIDE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Section 1: Document metadata
# ---------------------------------------------------------------------------

echo "=== Document Metadata ==="

assert_contains \
    "Document title is MacPGP Release QA Matrix" \
    "# MacPGP Release QA Matrix"

assert_contains \
    "Release target line present" \
    "Release target: MacPGP v1.0 App Store build"

assert_contains \
    "Document version line present" \
    "Document version:"

assert_contains_re \
    "Last updated line present with YYYY-MM-DD date" \
    "^Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$"

assert_contains \
    "Scope reference line present" \
    "Scope reference:"

assert_contains \
    "Scope reference points to V1_SCOPE.md" \
    "docs/V1_SCOPE.md"

# ---------------------------------------------------------------------------
# Section 2: QA Sign-Off section
# ---------------------------------------------------------------------------

echo ""
echo "=== QA Sign-Off ==="

assert_contains \
    "QA Sign-Off section exists" \
    "## QA Sign-Off"

assert_contains \
    "QA lead reviewed scope checkbox" \
    "QA lead reviewed the release scope before testing"

assert_contains \
    "QA lead confirmed install states checkbox" \
    "QA lead confirmed all required install states were tested"

assert_contains \
    "QA lead confirmed keyring states checkbox" \
    "QA lead confirmed all required keyring states were tested"

assert_contains \
    "QA lead confirmed critical findings linked checkbox" \
    "QA lead confirmed critical findings are linked as GitHub issues"

assert_contains \
    "QA lead approved run checkbox" \
    "QA lead approved this run for release consideration"

assert_contains \
    "QA lead field present" \
    "QA lead:"

assert_contains \
    "Date field present in QA Sign-Off" \
    "Date:"

assert_contains \
    "Release build/archive field present" \
    "Release build/archive:"

# ---------------------------------------------------------------------------
# Section 3: Test Execution Tracking table
# ---------------------------------------------------------------------------

echo ""
echo "=== Test Execution Tracking Table ==="

assert_contains \
    "Test Execution Tracking section exists" \
    "## Test Execution Tracking"

assert_contains \
    "Tracking table header row present" \
    "| Test ID | Feature Area | Install State | Keyring State | Result | Tester | Date | Linked Issues |"

assert_not_contains \
    "Tracking table does not use obsolete slash-separated result label" \
    "Pass""/Fail"

# Verify every required test ID row is in the tracking table
TRACKING_IDS=(
    "IS-FRESH"
    "IS-UPGRADE"
    "KS-EMPTY"
    "KS-POPULATED"
    "CORE-KEY"
    "CORE-ENCDEC"
    "CORE-SIGNVERIFY"
    "CORE-KEYSERVER"
    "CORE-SETTINGS"
    "CORE-SVC-DEC"
    "CORE-SVC-SIGN"
    "CORE-BACKUP"
    "EXT-FINDER"
    "EXT-QL"
    "EXT-THUMB"
    "EXT-SHARE"
    "EXT-CROSS"
    "CROSS-E2E"
    "CROSS-BACKUP"
    "CROSS-KNOWN"
    "CROSS-SVC"
    "QA-BUGS"
)

for id in "${TRACKING_IDS[@]}"; do
    assert_contains \
        "Tracking table contains Test ID: $id" \
        "| $id |"
done

assert_tracking_row "IS-FRESH" "Fresh" "Empty"
assert_tracking_row "IS-UPGRADE" "Upgrade" "Populated"
assert_tracking_row "KS-EMPTY" "Fresh" "Empty"
assert_tracking_row "KS-EMPTY" "Upgrade" "Empty"
assert_tracking_row "KS-POPULATED" "Fresh" "Populated"
assert_tracking_row "KS-POPULATED" "Upgrade" "Populated"

for id in CORE-KEY CORE-ENCDEC CORE-SIGNVERIFY CORE-SETTINGS CORE-SVC-DEC CORE-SVC-SIGN EXT-FINDER EXT-QL EXT-THUMB EXT-CROSS CROSS-KNOWN; do
    for install_state in Fresh Upgrade; do
        for keyring_state in Empty Populated; do
            assert_tracking_row "$id" "$install_state" "$keyring_state"
        done
    done
done

for id in CORE-KEYSERVER CORE-BACKUP CROSS-E2E CROSS-SVC; do
    for install_state in Fresh Upgrade; do
        assert_tracking_row "$id" "$install_state" "Populated"
    done
done

for install_state in Fresh Upgrade; do
    for keyring_state in Populated Restored; do
        assert_tracking_row "CROSS-BACKUP" "$install_state" "$keyring_state"
    done
done

assert_tracking_row "EXT-SHARE" "Release candidate" "N/A"

for keyring_state in Empty Populated Restored; do
    assert_tracking_row "QA-BUGS" "Release candidate" "$keyring_state"
done

AGGREGATE_STATE_LABELS=(
    "Fresh and Upgrade"
    "Empty and Populated"
    "Fresh/Upgrade"
    "Empty/Populated"
    "Fresh & Upgrade"
    "Empty & Populated"
    "Fresh + Upgrade"
    "Empty + Populated"
    "Any required"
    "All tested states"
    "Relevant state"
    "Populated and Restored"
)

for label in "${AGGREGATE_STATE_LABELS[@]}"; do
    assert_not_contains \
        "Tracking table rejects aggregate state label: $label" \
        "| $label |"
done

# ---------------------------------------------------------------------------
# Section 4: Legend section
# ---------------------------------------------------------------------------

echo ""
echo "=== Legend and Bug Linking ==="

assert_contains \
    "Legend section exists" \
    "## Legend and Bug Linking"

assert_contains \
    "Legend defines Pass status" \
    "Pass: mark"

assert_contains \
    "Legend defines Fail status" \
    "Fail: mark"

assert_contains \
    "Legend defines Blocked status" \
    "Blocked: mark"

assert_contains \
    "Legend defines Not run status" \
    "Not run: mark"

assert_contains \
    "Legend defines Linked Issues format" \
    "Linked Issues:"

assert_contains \
    "Legend defines Retests behavior" \
    "Retests:"

# ---------------------------------------------------------------------------
# Section 5: Required part headers
# ---------------------------------------------------------------------------

echo ""
echo "=== Document Part Headers ==="

assert_contains \
    "Part 1: Prerequisites header exists" \
    "## Part 1: Prerequisites"

assert_contains \
    "Part 2: Install State Tests header exists" \
    "## Part 2: Install State Tests"

assert_contains \
    "Part 3: Core App Features header exists" \
    "## Part 3: Core App Features"

assert_contains \
    "Part 4: Extensions header exists" \
    "## Part 4: Extensions"

assert_contains \
    "Part 5: Cross-Cutting Scenarios header exists" \
    "## Part 5: Cross-Cutting Scenarios"

# ---------------------------------------------------------------------------
# Section 6: Prerequisites subsections
# ---------------------------------------------------------------------------

echo ""
echo "=== Prerequisites Subsections ==="

assert_contains \
    "Section 1.1 Environment exists" \
    "### 1.1 Environment"

assert_contains \
    "Section 1.2 Build Instructions exists" \
    "### 1.2 Build Instructions"

assert_contains \
    "Section 1.3 Services Setup exists" \
    "### 1.3 Services Setup"

assert_contains \
    "Section 1.4 State Setup Checklist exists" \
    "### 1.4 State Setup Checklist"

assert_contains \
    "Section 1.5 Keyring Reset Procedure exists" \
    "### 1.5 Keyring Reset Procedure"

assert_contains \
    "Section 1.6 Empty Keyring Definition exists" \
    "### 1.6 Empty Keyring Definition"

assert_contains \
    "Section 1.7 Populated Keyring Definition exists" \
    "### 1.7 Populated Keyring Definition"

# ---------------------------------------------------------------------------
# Section 7: Critical technical constants
# ---------------------------------------------------------------------------

echo ""
echo "=== Technical Constants ==="

assert_contains \
    "App Group identifier is correct" \
    "group.com.macpgp.shared"

assert_contains \
    "Primary keyring path is correct" \
    "~/Library/Application Support/MacPGP/Keyring/"

assert_contains \
    "Extension-visible keyring projection path is correct" \
    "~/Library/Group Containers/group.com.macpgp.shared/keys.pgp"

assert_contains \
    "Reset keyring launch argument documented" \
    "--reset-keyring"

assert_contains \
    "Destructive reset warning documented" \
    "Destructive reset warning:"

assert_contains \
    "Release app bundle variable documented" \
    'APP_BUNDLE="${APP_BUNDLE:-./build/Release/MacPGP.app}"'

assert_contains \
    "Services flush command documented" \
    "/System/Library/CoreServices/pbs -flush"

assert_contains \
    "PGP MESSAGE example marker documented for encryption output" \
    "BEGIN PGP MESSAGE (example marker)"

assert_contains \
    "PGP SIGNED MESSAGE example marker documented for sign output" \
    "BEGIN PGP SIGNED MESSAGE (example marker)"

assert_contains \
    "PGP PUBLIC KEY BLOCK example marker documented" \
    "BEGIN PGP PUBLIC KEY BLOCK (example marker)"

assert_contains \
    "PGP PRIVATE KEY BLOCK example marker documented" \
    "BEGIN PGP PRIVATE KEY BLOCK (example marker)"

assert_contains \
    "PGP SIGNATURE example marker documented" \
    "BEGIN PGP SIGNATURE (example marker)"

assert_not_contains \
    "Guide does not contain exact PGP MESSAGE delimiter" \
    "$(pgp_begin_marker "MESSAGE")"

assert_not_contains \
    "Guide does not contain exact PGP SIGNED MESSAGE delimiter" \
    "$(pgp_begin_marker "SIGNED MESSAGE")"

assert_not_contains \
    "Guide does not contain exact PGP SIGNATURE delimiter" \
    "$(pgp_begin_marker "SIGNATURE")"

assert_not_contains \
    "Guide does not contain exact PGP PUBLIC KEY BLOCK delimiter" \
    "$(pgp_begin_marker "PUBLIC KEY BLOCK")"

assert_not_contains \
    "Guide does not contain exact PGP PRIVATE KEY BLOCK delimiter" \
    "$(pgp_begin_marker "PRIVATE KEY BLOCK")"

assert_not_contains \
    "Guide does not hard-code Debug app bundle path" \
    "./build/""Debug/MacPGP.app"

assert_contains \
    "Encrypted backup file header format documented" \
    "MACPGP-ENC-V1"

# ---------------------------------------------------------------------------
# Section 8: Install State test sections present
# ---------------------------------------------------------------------------

echo ""
echo "=== Install State Test Sections ==="

assert_contains \
    "IS-FRESH section header present" \
    "### IS-FRESH: Fresh Install"

assert_contains \
    "IS-UPGRADE section header present" \
    "### IS-UPGRADE: Upgrade Install"

# ---------------------------------------------------------------------------
# Section 9: Core feature test sections present
# ---------------------------------------------------------------------------

echo ""
echo "=== Core Feature Test Sections ==="

assert_contains \
    "CORE-KEY section header present" \
    "### CORE-KEY: Key Management"

assert_contains \
    "CORE-ENCDEC section header present" \
    "### CORE-ENCDEC: Encryption and Decryption"

assert_contains \
    "CORE-SIGNVERIFY section header present" \
    "### CORE-SIGNVERIFY: Sign and Verify Screens"

assert_contains \
    "CORE-KEYSERVER section header present" \
    "### CORE-KEYSERVER: Keyserver Operations"

assert_contains \
    "CORE-SETTINGS section header present" \
    "### CORE-SETTINGS: Settings and Preferences"

assert_contains \
    "General settings localization check covers main-window strings" \
    "Primary main-window strings display in the selected language after relaunch."

assert_contains \
    "General settings localization check covers menu text" \
    "Menu item text displays in the selected language after relaunch."

assert_contains \
    "General settings localization check covers Services labels" \
    "Services menu labels display in the selected language"

assert_contains \
    "General settings localization check covers extension-facing strings" \
    "Extension-facing strings display in the selected language"

assert_contains \
    "CORE-SVC-DEC section header present" \
    "### CORE-SVC-DEC: Decrypt Services"

assert_contains \
    "CORE-SVC-SIGN section header present" \
    "### CORE-SVC-SIGN: Sign Services"

assert_contains \
    "CORE-BACKUP section header present" \
    "### CORE-BACKUP: Key Backup and Recovery"

# ---------------------------------------------------------------------------
# Section 10: Extension test sections present
# ---------------------------------------------------------------------------

echo ""
echo "=== Extension Test Sections ==="

assert_contains \
    "EXT-FINDER section header present" \
    "### EXT-FINDER: FinderSyncExtension"

assert_contains \
    "EXT-QL section header present" \
    "### EXT-QL: QuickLookExtension"

assert_contains \
    "EXT-THUMB section header present" \
    "### EXT-THUMB: ThumbnailExtension"

assert_contains \
    "EXT-SHARE section header present" \
    "### EXT-SHARE: ShareExtension Exclusion"

assert_contains \
    "EXT-CROSS section header present" \
    "### EXT-CROSS: Cross-Extension Integration"

# ---------------------------------------------------------------------------
# Section 11: Key individual test case headers
# ---------------------------------------------------------------------------

echo ""
echo "=== Individual Test Case Headers ==="

assert_contains \
    "CORE-KEY-1.1 through 1.3 grouped RSA generation test present" \
    "#### CORE-KEY-1.1 through 1.3: Generate RSA Key (2048, 3072, and 4096 Bits)"

assert_contains \
    "CORE-KEY RSA 2048-bit size documented" \
    "2048 bits"

assert_contains \
    "CORE-KEY RSA 3072-bit size documented" \
    "3072 bits"

assert_contains \
    "CORE-KEY RSA 4096-bit size documented" \
    "4096 bits"

assert_contains \
    "CORE-SVC-DEC-1.1 Basic Decryption present" \
    "#### CORE-SVC-DEC-1.1: Basic Decryption"

assert_contains \
    "CORE-SVC-DEC-1.2 Wrong Passphrase present" \
    "#### CORE-SVC-DEC-1.2: Wrong Passphrase"

assert_contains \
    "CORE-SVC-DEC-1.3 Invalid PGP Message present" \
    "#### CORE-SVC-DEC-1.3: Invalid PGP Message"

assert_contains \
    "CORE-SVC-DEC-1.4 No Secret Keys present" \
    "#### CORE-SVC-DEC-1.4: No Secret Keys"

assert_contains \
    "CORE-SVC-DEC-1.5 No Text Selected present" \
    "#### CORE-SVC-DEC-1.5: No Text Selected"

assert_contains \
    "CORE-SVC-DEC-1.6 Cancel Operation present" \
    "#### CORE-SVC-DEC-1.6: Cancel Operation"

assert_contains \
    "CORE-SVC-SIGN-1.1 Basic Signing present" \
    "#### CORE-SVC-SIGN-1.1: Basic Signing"

assert_contains \
    "CORE-SVC-SIGN-1.2 Wrong Passphrase present" \
    "#### CORE-SVC-SIGN-1.2: Wrong Passphrase"

assert_contains \
    "CORE-SVC-SIGN-1.3 No Secret Keys present" \
    "#### CORE-SVC-SIGN-1.3: No Secret Keys"

assert_contains \
    "CORE-SVC-SIGN-1.4 No Text Selected present" \
    "#### CORE-SVC-SIGN-1.4: No Text Selected"

assert_contains \
    "CORE-SVC-SIGN-1.5 Cancel Operation present" \
    "#### CORE-SVC-SIGN-1.5: Cancel Operation"

assert_contains \
    "CORE-BACKUP-5.1 Create Unencrypted Backup present" \
    "#### CORE-BACKUP-5.1: Create Unencrypted Backup"

assert_contains \
    "CORE-BACKUP-5.2 Create Encrypted Backup present" \
    "#### CORE-BACKUP-5.2: Create Encrypted Backup"

assert_contains \
    "CORE-BACKUP-6.1 Restore Unencrypted Backup present" \
    "#### CORE-BACKUP-6.1: Restore Unencrypted Backup"

assert_contains \
    "CORE-BACKUP-6.2 Restore Encrypted Backup present" \
    "#### CORE-BACKUP-6.2: Restore Encrypted Backup"

assert_contains \
    "CORE-BACKUP-7.1 Generate Paper Backup present" \
    "#### CORE-BACKUP-7.1: Generate Paper Backup"

assert_contains \
    "CORE-BACKUP-7.2 Paper Backup for Large Key present" \
    "#### CORE-BACKUP-7.2: Paper Backup for Large Key"

assert_contains \
    "CORE-BACKUP-8.1 Backup Reminder Settings present" \
    "#### CORE-BACKUP-8.1: Backup Reminder Settings"

assert_contains \
    "CORE-BACKUP-8.2 Backup Reminder Logic present" \
    "#### CORE-BACKUP-8.2: Backup Reminder Logic"

assert_contains \
    "CORE-BACKUP-9.2 Invalid Backup File Handling present" \
    "#### CORE-BACKUP-9.2: Invalid Backup File Handling"

assert_contains \
    "CORE-BACKUP-9.3 Corrupted Encrypted Backup present" \
    "#### CORE-BACKUP-9.3: Corrupted Encrypted Backup"

assert_contains \
    "EXT-SHARE-1.1 Release Bundle Does Not Embed ShareExtension present" \
    "#### EXT-SHARE-1.1: Release Bundle Does Not Embed ShareExtension"

assert_contains \
    "EXT-SHARE-1.2 Release Guardrail Script present" \
    "#### EXT-SHARE-1.2: Release Guardrail Script"

assert_contains \
    "CROSS-E2E-1.1 Full Two-Key Round Trip present" \
    "### CROSS-E2E-1.1: Full Two-Key Round Trip"

assert_contains \
    "CROSS-BACKUP-1.1 Backup Delete Restore Revalidate present" \
    "### CROSS-BACKUP-1.1: Backup, Delete, Restore, and Revalidate"

assert_contains \
    "CROSS-KNOWN-1.2 Existing Issue Verification Checklist present" \
    "### CROSS-KNOWN-1.2: Existing Issue Verification Checklist"

# ---------------------------------------------------------------------------
# Section 12: Expected error message strings referenced in test cases
# ---------------------------------------------------------------------------

echo ""
echo "=== Expected Error Messages ==="

assert_contains \
    "Decryption failed error message documented" \
    "Decryption failed"

assert_contains \
    "No secret keys available error message documented" \
    "No secret keys available"

assert_contains \
    "No text selected error message documented" \
    "No text selected"

assert_contains \
    "Invalid PGP message error message documented" \
    "Invalid PGP message"

assert_contains \
    "Signing failed error message documented" \
    "Signing failed"

assert_contains \
    "Invalid backup file format error message documented" \
    "Invalid backup file format"

# ---------------------------------------------------------------------------
# Section 13: ShareExtension exclusion requirements
# ---------------------------------------------------------------------------

echo ""
echo "=== ShareExtension Exclusion Requirements ==="

assert_contains \
    "FinderSyncExtension.appex expected present in bundle" \
    "FinderSyncExtension.appex"

assert_contains \
    "QuickLookExtension.appex expected present in bundle" \
    "QuickLookExtension.appex"

assert_contains \
    "ThumbnailExtension.appex expected present in bundle" \
    "ThumbnailExtension.appex"

assert_contains \
    "ShareExtension.appex must not be present in release bundle" \
    "ShareExtension.appex must not be present in release bundle"

assert_contains \
    "Guardrail script reference present" \
    "scripts/check-no-shareextension-in-release.sh"

assert_contains \
    "ShareExtension exclusion v1.0 scope issue #49 referenced" \
    "#49"

# ---------------------------------------------------------------------------
# Section 14: Known issue references in CROSS-KNOWN-1.2 table
# ---------------------------------------------------------------------------

echo ""
echo "=== Known Issue References ==="

KNOWN_ISSUES=("#4" "#5" "#9" "#10" "#16" "#43" "#48" "#49" "#50")
for issue in "${KNOWN_ISSUES[@]}"; do
    assert_contains \
        "Known issue $issue is referenced in the guide" \
        "$issue"
done

# ---------------------------------------------------------------------------
# Section 15: Bug Tracking and Sign-Off sections
# ---------------------------------------------------------------------------

echo ""
echo "=== Bug Tracking and Sign-Off ==="

assert_contains \
    "Bug Tracking and Sign-Off section exists" \
    "## Bug Tracking and Sign-Off"

assert_contains \
    "Bugs Found subsection exists" \
    "### Bugs Found"

assert_contains \
    "Bugs Found table header present" \
    "| Issue Number | Test ID | Description | Severity | Linked GitHub Issue |"

assert_contains \
    "Known Issues Verification subsection exists" \
    "### Known Issues Verification"

assert_contains \
    "Known Issues Verification table header present" \
    "| Known Issue Ref | Test ID | Expected Current Behavior or Workaround | Result | Follow-Up |"

assert_contains \
    "Filing New Bugs subsection exists" \
    "### Filing New Bugs"

assert_contains \
    "Bug filing template Summary field present" \
    "**Summary**"

assert_contains \
    "Bug filing template Current repo evidence field present" \
    "**Current repo evidence**"

assert_contains \
    "Bug filing template What needs to happen field present" \
    "**What needs to happen**"

assert_contains \
    "Bug filing template Acceptance criteria field present" \
    "**Acceptance criteria**"

assert_contains \
    "Final Release QA Sign-Off section exists" \
    "### Final Release QA Sign-Off"

assert_contains \
    "Final sign-off: All critical paths pass checkbox" \
    "All critical paths pass."

assert_contains \
    "Final sign-off: ShareExtension exclusion verified checkbox" \
    "ShareExtension exclusion verified."

assert_contains \
    "Final sign-off: QA lead approval checkbox" \
    "QA lead approval recorded with date."

# ---------------------------------------------------------------------------
# Section 16: Checklist format integrity
# ---------------------------------------------------------------------------

echo ""
echo "=== Checklist Format Integrity ==="

# All checklist items must use unchecked "- [ ]" format since this is a
# template guide; no items should be pre-checked with "- [x]"
CHECKED_COUNT=$(grep -cE '^\- \[[xX]\]' "$GUIDE" 2>/dev/null || true)
if [[ "$CHECKED_COUNT" -eq 0 ]]; then
    pass "No checklist items are pre-checked (all use '- [ ]' unchecked format)"
else
    fail "Found $CHECKED_COUNT pre-checked checklist items ('- [x]') in guide template"
fi

# Document should have a substantial number of unchecked checklist items
assert_count_gte \
    "Guide contains at least 50 unchecked checklist items" \
    "- [ ]" \
    50

# ---------------------------------------------------------------------------
# Section 17: Steps and Expected headers format
# ---------------------------------------------------------------------------

echo ""
echo "=== Test Case Structure ==="

# Every test case block must have matching Steps and Expected sections.
TEST_HEADER_RE='^#{3,4}[[:space:]][^:]*[0-9][^:]*:'
TEST_BLOCK_COUNT=0
STEPS_COUNT=0
EXPECTED_COUNT=0
CURRENT_TEST_HEADER=""
CURRENT_STEPS_COUNT=0
CURRENT_EXPECTED_COUNT=0

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $TEST_HEADER_RE ]]; then
        assert_current_test_block_structure "$CURRENT_TEST_HEADER" "$CURRENT_STEPS_COUNT" "$CURRENT_EXPECTED_COUNT"
        CURRENT_TEST_HEADER="$line"
        CURRENT_STEPS_COUNT=0
        CURRENT_EXPECTED_COUNT=0
        continue
    fi

    if [[ -n "$CURRENT_TEST_HEADER" ]]; then
        case "$line" in
            "**Steps:**")
                CURRENT_STEPS_COUNT=$((CURRENT_STEPS_COUNT + 1))
                ;;
            "**Expected:**")
                CURRENT_EXPECTED_COUNT=$((CURRENT_EXPECTED_COUNT + 1))
                ;;
        esac
    fi
done < "$GUIDE"

assert_current_test_block_structure "$CURRENT_TEST_HEADER" "$CURRENT_STEPS_COUNT" "$CURRENT_EXPECTED_COUNT"

if [[ "$TEST_BLOCK_COUNT" -ge 1 ]]; then
    pass "Guide contains test-case blocks (found $TEST_BLOCK_COUNT)"
else
    fail "Guide contains no test-case blocks"
fi

if [[ "$STEPS_COUNT" -eq "$EXPECTED_COUNT" ]]; then
    pass "Total Steps and Expected section counts match (Steps=$STEPS_COUNT, Expected=$EXPECTED_COUNT)"
else
    fail "Total Steps and Expected section counts differ (Steps=$STEPS_COUNT, Expected=$EXPECTED_COUNT)"
fi

# ---------------------------------------------------------------------------
# Section 18: Services verification checklist completeness
# ---------------------------------------------------------------------------

echo ""
echo "=== Services Verification Checklists ==="

assert_contains \
    "Decrypt Service verification checklist header present" \
    "#### Decrypt Service"

assert_contains \
    "Sign Service verification checklist header present" \
    "#### Sign Service"

assert_contains \
    "System Integration checklist header present" \
    "#### System Integration"

# ---------------------------------------------------------------------------
# Section 19: Services troubleshooting reference
# ---------------------------------------------------------------------------

echo ""
echo "=== Services Troubleshooting Reference ==="

assert_contains \
    "Services troubleshooting points to Services Setup" \
    "For Services troubleshooting, see Section 1.3 (Services Setup)."

# ---------------------------------------------------------------------------
# Section 20: Bug filing rules and final sign-off notes
# ---------------------------------------------------------------------------

echo ""
echo "=== Bug Filing Rules and Final Sign-Off Notes ==="

assert_contains \
    "Bug filing rules section exists" \
    "Bug filing rules:"

assert_contains \
    "Final sign-off requires empty and populated keyring states" \
    "Empty Keyring and Populated Keyring states tested."

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Failed assertions:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "All assertions passed."
exit 0
