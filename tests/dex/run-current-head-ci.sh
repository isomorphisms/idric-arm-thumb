#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
idric_repo=${IDRIC_REPO:-"$repo_root/Idric"}
compiler_ref=${IDRIC_COMPILER_REF:-Idriç}
compiler="$idric_repo/build/exec/idris2"
receipt="$repo_root/build/exec/current-head-receipt.tsv"
log="$repo_root/build/exec/current-head.log"
current_stage=compiler_build
passed='compiler_checkout'

if [[ -n ${IDRIC_SCHEME:-} ]]; then
  export PATH="$(dirname -- "$IDRIC_SCHEME"):$PATH"
fi

mkdir -p "$repo_root/build/exec"
: > "$log"

backend_sha=$(git -C "$repo_root" rev-parse HEAD)
compiler_sha=$(git -C "$idric_repo" rev-parse HEAD)
backend_dirty=$(if git -C "$repo_root" status --porcelain | grep -q .; then printf dirty; else printf clean; fi)
compiler_dirty=$(if git -C "$idric_repo" status --porcelain | grep -q .; then printf dirty; else printf clean; fi)

write_receipt() {
  outcome=$1
  diagnostic=${2:-none}
  {
    printf 'CURRENT_HEAD_COMPATIBILITY\t1\n'
    printf 'repository\tisomorphisms/idric-arm-thumb\n'
    printf 'requested_ref\t%s\n' "${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-local}}"
    printf 'resolved_sha\t%s\n' "$backend_sha"
    printf 'dirty_state\t%s\n' "$backend_dirty"
    printf 'dependent_repository\tisomorphisms/Idric\n'
    printf 'dependent_requested_ref\t%s\n' "$compiler_ref"
    printf 'dependent_resolved_sha\t%s\n' "$compiler_sha"
    printf 'dependent_dirty_state\t%s\n' "$compiler_dirty"
    for stage in compiler_checkout compiler_build compiler_api_install backend_build dex_generation dex_validation thumb_execution art_execution; do
      case " $passed " in
        *" $stage "*) printf 'stage\t%s\tPASS\n' "$stage" ;;
        *)
          if [ "$stage" = "$current_stage" ]; then
            printf 'stage\t%s\t%s\n' "$stage" "$outcome"
          else
            printf 'stage\t%s\tSKIP\tprerequisite_not_met\n' "$stage"
          fi
          ;;
      esac
    done
    if [ "$outcome" = FAIL ]; then
      printf 'first_failure\t%s\t%s\n' "$current_stage" "$diagnostic"
    else
      printf 'first_failure\tnone\n'
    fi
  } > "$receipt"
}

fail_receipt() {
  status=$?
  trap - ERR
  diagnostic=$(grep -E '(^FAIL|^Error:|^usage:|unsupported|rejected|not found|No such file)' "$log" | tail -n 1 || true)
  [[ -n $diagnostic ]] || diagnostic=$(tail -n 1 "$log" | tr '\t\r\n' '   ')
  write_receipt FAIL "${diagnostic:-exit_$status}"
  cat "$receipt" >&2
  exit "$status"
}
trap fail_receipt ERR

run_stage() {
  "$@" 2>&1 | tee -a "$log"
}

current_stage=compiler_build
if [[ ! -x "$compiler" ]]; then
  run_stage "$idric_repo/edric" bootstrap
fi
run_stage "$compiler" --version
passed="$passed compiler_build"

current_stage=compiler_api_install
run_stage make -C "$idric_repo/support/chez" install IDRIS2_VERSION=0.8.0
run_stage make -C "$idric_repo" install-bootstrap-libs IDRIS2="$compiler"
run_stage make -C "$idric_repo" install-api IDRIS2_BOOT="$compiler"
passed="$passed compiler_api_install"

current_stage=backend_build
run_stage make -C "$repo_root" check IDRIC="$compiler" IDRIC_REPO="$idric_repo" IDRIC_COMPILER_REF="$compiler_ref"
passed="$passed backend_build"

current_stage=dex_generation
run_stage make -C "$repo_root" dex-fixture IDRIC="$compiler" IDRIC_REPO="$idric_repo" IDRIC_COMPILER_REF="$compiler_ref"
passed="$passed dex_generation"

current_stage=dex_validation
run_stage make -C "$repo_root" dex-test IDRIC="$compiler" IDRIC_REPO="$idric_repo" IDRIC_COMPILER_REF="$compiler_ref"
passed="$passed dex_validation"

current_stage=thumb_execution
run_stage make -C "$repo_root" verify IDRIC="$compiler" IDRIC_REPO="$idric_repo" IDRIC_COMPILER_REF="$compiler_ref"
passed="$passed thumb_execution"
current_stage=art_execution
write_receipt SKIP device_job_owns_execution
trap - ERR
cat "$receipt"
