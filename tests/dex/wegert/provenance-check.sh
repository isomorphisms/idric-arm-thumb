#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
candidate=${1:-"$repo_root/build/exec/wegert/classes.dex"}
host_receipt=${WEGERT_HOST_RECEIPT:-"$repo_root/build/exec/wegert/host-receipt.txt"}
current_head_receipt=${DEX_CURRENT_HEAD_RECEIPT:-"$repo_root/build/exec/current-head-receipt.tsv"}
receipt=${WEGERT_PROVENANCE_RECEIPT:-"$repo_root/build/exec/wegert/provenance-receipt.txt"}
backend_revision=${BACKEND_REVISION:-$(git -C "$repo_root" rev-parse HEAD)}
compiler_revision=unknown

mkdir -p "$(dirname -- "$receipt")"

fail_receipt() {
  explanation=$1
  {
    echo 'WEGERT_ART_PROVENANCE  1'
    echo 'host direct DEX        FAIL'
    echo 'candidate hash         SKIP'
    echo 'backend revision       SKIP'
    echo 'compiler revision      SKIP'
    printf 'reason                 %s\n' "$explanation"
  } >"$receipt"
  cat "$receipt"
  exit 1
}

[[ -f $candidate ]] || fail_receipt "candidate classes.dex is absent: $candidate"
[[ -f $host_receipt ]] || fail_receipt "Wegert host receipt is absent: $host_receipt"
[[ -f $current_head_receipt ]] || fail_receipt "current-head receipt is absent: $current_head_receipt"

candidate_hash=$(sha256sum "$candidate" | cut -d' ' -f1)
validated_hash=$(awk '$1 == "classes.dex" && $2 == "SHA-256" { print $3; exit }' "$host_receipt")
receipt_backend=$(awk -F '\t' '$1 == "resolved_sha" { print $2; exit }' "$current_head_receipt")
compiler_revision=$(awk -F '\t' '$1 == "dependent_resolved_sha" { print $2; exit }' "$current_head_receipt")
wegert_status=$(awk -F '\t' '$1 == "stage" && $2 == "wegert_direct_dex" { print $3; exit }' "$current_head_receipt")

[[ -n $validated_hash ]] || fail_receipt 'Wegert host receipt has no classes.dex SHA-256'
[[ -n $receipt_backend ]] || fail_receipt 'current-head receipt has no backend SHA'
[[ -n $compiler_revision ]] || fail_receipt 'current-head receipt has no Idriç SHA'
[[ $wegert_status == PASS ]] || fail_receipt 'upstream Wegert direct DEX stage is not PASS'
[[ $candidate_hash == "$validated_hash" ]] || fail_receipt 'Wegert classes.dex hash differs from host-validated candidate'
[[ $backend_revision == "$receipt_backend" ]] || fail_receipt 'backend checkout differs from Wegert host-validation revision'

{
  echo 'WEGERT_ART_PROVENANCE  1'
  echo 'host direct DEX        PASS'
  echo 'candidate hash         PASS'
  echo 'backend revision       PASS'
  echo 'compiler revision      PASS'
  printf 'classes.dex SHA-256    %s\n' "$candidate_hash"
  printf 'backend SHA            %s\n' "$backend_revision"
  printf 'Idriç SHA              %s\n' "$compiler_revision"
} >"$receipt"

cat "$receipt"
