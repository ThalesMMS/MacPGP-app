#!/usr/bin/env bash
# Guards the file-size-dependent crypto flows against regressing to whole-file
# in-memory reads (issue #142). These flows must stream between paths via
# RNPKit's path-based APIs (encryptFile / decryptFile / decryptFileTryingKeys /
# signFile / verifyFile) so peak memory stays bounded for large inputs.
#
# The check fails if a guarded source file reintroduces a whole-file read of the
# payload (`SecureScopedFileAccess.readData(from:`, `Data(contentsOf:`,
# `.read(contentsOf:`, `FileHandle(...).readDataToEndOfFile`). Small, bounded
# reads (`readPrefix(from:maxBytes:)`, `fileSize(of:)`) remain allowed.
#
# Run locally or in CI:
#   bash scripts/check-streaming-file-paths.sh

set -uo pipefail
cd "$(dirname "$0")/.."

# Source files whose file-mode crypto paths must stay streaming/path-based.
guarded_files=(
  "MacPGP/MacPGP/Core/Services/EncryptionService.swift"
  "MacPGP/MacPGP/Core/Services/VerificationService.swift"
)

# Whole-file read patterns that defeat streaming. `readPrefix`/`fileSize` are the
# allowed bounded primitives and are intentionally NOT matched here.
forbidden='SecureScopedFileAccess\.readData\(from|[^a-zA-Z]Data\(contentsOf:|\.read\(contentsOf:|readDataToEndOfFile|contentsOfFile:'

fail=0
note() { printf '  - %s\n' "$1"; }

for f in "${guarded_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Streaming-path check FAILED: guarded file missing: $f"
    echo "  (Update scripts/check-streaming-file-paths.sh if it moved.)"
    fail=1
    continue
  fi
  hits="$(grep -nE "$forbidden" "$f" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "Streaming-path check FAILED: whole-file read reintroduced in $f"
    while IFS= read -r line; do note "$line"; done <<< "$hits"
    echo "  These flows must stream between paths (issue #142). Use the RNPKit"
    echo "  path APIs (decryptFile/decryptFileTryingKeys/verifyFile/encryptFile/"
    echo "  signFile) or a bounded read (readPrefix/fileSize) instead of loading"
    echo "  the whole payload into a Data."
    fail=1
  fi
done

# Positive assertion: the streaming/path-based APIs are actually wired in, so the
# check also fails if someone strips the streaming calls entirely.
require_call() {  # <file> <pattern> <human description>
  local f="$1" pat="$2" desc="$3"
  if [[ -f "$f" ]] && ! grep -qE "$pat" "$f"; then
    echo "Streaming-path check FAILED: $f no longer calls $desc."
    echo "  The file-mode path must route through the streaming API (issue #142)."
    fail=1
  fi
}
require_call "MacPGP/MacPGP/Core/Services/EncryptionService.swift" \
  "RNP\.decryptFileTryingKeys|performStreamingTryDecryption" \
  "the streaming auto-detect decrypt (decryptFileTryingKeys)"
require_call "MacPGP/MacPGP/Core/Services/VerificationService.swift" \
  "RNP\.verifyFile" \
  "path-based verification (verifyFile)"

# Operation routing / Finder handoff must classify via bounded header sniffing,
# never a full-file analysis (issue #142, acceptance: bounded classification).
ext_comm="MacPGP/MacPGP/Core/Services/ExtensionCommunicationService.swift"
if [[ -f "$ext_comm" ]]; then
  if grep -qE "fileAnalyzer\.isEncrypted\(fileAt:" "$ext_comm"; then
    echo "Streaming-path check FAILED: $ext_comm routes via full-file isEncrypted(fileAt:)."
    echo "  Use fileAnalyzer.isEncryptedHeader(fileAt:) for bounded classification (issue #142)."
    fail=1
  fi
  require_call "$ext_comm" "isEncryptedHeader\(fileAt:" "bounded header classification (isEncryptedHeader)"
fi

# ShareExtension must stream its encryption between paths (issue #142) and never
# buffer the shared input file. (It may still read the small public keyring
# projection, so only the payload read is forbidden here.)
share_svc="MacPGP/ShareExtension/ExtensionServices.swift"
if [[ -f "$share_svc" ]]; then
  if grep -qE "Data\(contentsOf: file\)" "$share_svc"; then
    echo "Streaming-path check FAILED: $share_svc buffers the shared input file."
    echo "  Stream via RNP.encryptFile(inputPath:outputPath:) instead (issue #142)."
    fail=1
  fi
  require_call "$share_svc" "RNP\.encryptFile" "streaming share-sheet encryption (encryptFile)"
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "Streaming-path check passed: file-mode crypto flows remain bounded (issue #142)."
