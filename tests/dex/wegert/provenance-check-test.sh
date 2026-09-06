#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
check="$repo_root/tests/dex/wegert/provenance-check.sh"
backend_revision=$(git -C "$repo_root" rev-parse HEAD)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

candidate="$temporary/classes.dex"
host_receipt="$temporary/host-receipt.txt"
current_head="$temporary/current-head-receipt.tsv"
receipt="$temporary/provenance-receipt.txt"

printf '%s\n' 'synthetic Wegert candidate' >"$candidate"
candidate_hash=$(sha256sum "$candidate" | cut -d' ' -f1)

write_host() {
  hash=$1
  {
    echo 'WEGERT_DIRECT_DEX        1'
    echo 'direct encoder          PASS'
    echo 'deterministic output    PASS'
    echo 'structural validation   PASS'
    printf 'classes.dex SHA-256     %s\n' "$hash"
  } >"$host_receipt"
}

write_current_head() {
  backend=$1
  status=$2
  {
    printf 'CURRENT_HEAD_COMPATIBILITY\t1\n'
    printf 'resolved_sha\t%s\n' "$backend"
    printf 'dependent_resolved_sha\t%s\n' 'synthetic-current-idric'
    printf 'stage\twegert_direct_dex\t%s\n' "$status"
  } >"$current_head"
}

run_check() {
  WEGERT_HOST_RECEIPT="$host_receipt" \
  DEX_CURRENT_HEAD_RECEIPT="$current_head" \
  WEGERT_PROVENANCE_RECEIPT="$receipt" \
  BACKEND_REVISION="$backend_revision" \
    bash "$check" "$candidate" >/dev/null 2>&1
}

write_host "$candidate_hash"
write_current_head "$backend_revision" PASS
run_check
grep -F 'host direct DEX        PASS' "$receipt" >/dev/null
grep -F "classes.dex SHA-256    $candidate_hash" "$receipt" >/dev/null
grep -F 'Idriç SHA              synthetic-current-idric' "$receipt" >/dev/null

write_host deadbeef
if run_check; then
  echo 'Mismatched Wegert DEX hash unexpectedly passed provenance' >&2
  exit 1
fi
grep -F 'reason                 Wegert classes.dex hash differs from host-validated candidate' "$receipt" >/dev/null

write_host "$candidate_hash"
write_current_head deadbeef PASS
if run_check; then
  echo 'Mismatched Wegert backend revision unexpectedly passed provenance' >&2
  exit 1
fi
grep -F 'reason                 backend checkout differs from Wegert host-validation revision' "$receipt" >/dev/null

write_current_head "$backend_revision" FAIL
if run_check; then
  echo 'Non-PASS Wegert host stage unexpectedly passed provenance' >&2
  exit 1
fi
grep -F 'reason                 upstream Wegert direct DEX stage is not PASS' "$receipt" >/dev/null

echo 'Wegert ART provenance gate: PASS'
