#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
device_script="$repo_root/tests/dex/device-acceptance.sh"
backend_revision=$(git -C "$repo_root" rev-parse HEAD)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

candidate="$temporary/classes.dex"
validation="$temporary/dex-validation-receipt.txt"
current_head="$temporary/current-head-receipt.tsv"
receipt="$temporary/device-receipt.txt"

printf '%s\n' 'synthetic candidate for provenance-only test' >"$candidate"
candidate_hash=$(sha256sum "$candidate" | cut -d' ' -f1)

write_validation() {
  hash=$1
  {
    printf '%s\n' 'DEX parser validation PASS'
    printf 'classes.dex SHA-256    %s\n' "$hash"
  } >"$validation"
}

write_current_head() {
  backend=$1
  dex_status=$2
  {
    printf 'CURRENT_HEAD_COMPATIBILITY\t1\n'
    printf 'resolved_sha\t%s\n' "$backend"
    printf 'dependent_resolved_sha\t%s\n' 'synthetic-current-idric'
    printf 'stage\tdex_validation\t%s\n' "$dex_status"
  } >"$current_head"
}

run_device() {
  set +e
  DEX_PROVENANCE_REQUIRED=${DEX_PROVENANCE_REQUIRED_VALUE:-1} \
  DEX_VALIDATION_RECEIPT="$validation" \
  DEX_CURRENT_HEAD_RECEIPT="$current_head" \
  DEX_DEVICE_RECEIPT="$receipt" \
  BACKEND_REVISION="$backend_revision" \
  SMALI_JAR= \
    "$device_script" "$candidate" >/dev/null 2>&1
  status=$?
  set -e
  return "$status"
}

write_validation "$candidate_hash"
write_current_head "$backend_revision" PASS
if run_device; then
  echo 'Expected provenance-only run to stop because SMALI_JAR is absent' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 2 ] || { echo "Expected exit 2 after provenance PASS, got $status" >&2; exit 1; }
grep -F 'provenance checked      PASS' "$receipt" >/dev/null
grep -F 'compiler revision      synthetic-current-idric' "$receipt" >/dev/null

write_validation deadbeef
if run_device; then
  echo 'Mismatched DEX hash unexpectedly passed provenance' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 1 ] || { echo "Expected hash mismatch exit 1, got $status" >&2; exit 1; }
grep -F 'provenance checked      FAIL' "$receipt" >/dev/null
grep -F 'reason                 classes.dex hash differs from validated candidate' "$receipt" >/dev/null

write_validation "$candidate_hash"
write_current_head deadbeef PASS
if run_device; then
  echo 'Mismatched backend revision unexpectedly passed provenance' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 1 ] || { echo "Expected backend mismatch exit 1, got $status" >&2; exit 1; }
grep -F 'reason                 backend checkout differs from validated backend revision' "$receipt" >/dev/null

write_current_head "$backend_revision" FAIL
if run_device; then
  echo 'Non-PASS upstream DEX validation unexpectedly passed provenance' >&2
  exit 1
else
  status=$?
fi
[ "$status" -eq 1 ] || { echo "Expected upstream status failure exit 1, got $status" >&2; exit 1; }
grep -F 'reason                 upstream DEX validation is not PASS' "$receipt" >/dev/null

write_validation "$candidate_hash"
rm -f "$current_head"
DEX_PROVENANCE_REQUIRED_VALUE=0
if run_device; then
  echo 'Optional local run unexpectedly reached device execution' >&2
  exit 1
else
  status=$?
fi
unset DEX_PROVENANCE_REQUIRED_VALUE
[ "$status" -eq 2 ] || { echo "Expected optional local exit 2 without SMALI_JAR, got $status" >&2; exit 1; }
grep -F 'provenance checked      SKIP' "$receipt" >/dev/null

echo 'DEX ART provenance gate: PASS'
