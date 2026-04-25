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
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/manual-testing-guide/assertions.sh"
source "$SCRIPT_DIR/manual-testing-guide/tracking-table.sh"
source "$SCRIPT_DIR/manual-testing-guide/content-checks.sh"
source "$SCRIPT_DIR/manual-testing-guide/structure-checks.sh"

# ---------------------------------------------------------------------------
# Guard: file must exist and be readable
# ---------------------------------------------------------------------------

echo "Testing: $GUIDE"
echo ""

if [[ ! -f "$GUIDE" || ! -r "$GUIDE" ]]; then
    echo "FATAL: Guide file not found or not readable: $GUIDE"
    exit 1
fi

run_document_metadata_checks
run_qa_signoff_checks
run_tracking_table_checks
run_content_checks_before_structure
run_structure_checks
run_content_checks_after_structure

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
