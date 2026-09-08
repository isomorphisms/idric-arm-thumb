#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

fail() {
  printf 'DEX branch separation FAIL: %s\n' "$1" >&2
  exit 1
}

arm_paths=$(git ls-files | grep -E \
  '^(src/Backend/ARMThumb/|tests/arm/|tests/branching/|src/RendererPrimitives\.idr$|examples/(Affine|Operations)\.idric$)' \
  || true)
[[ -z $arm_paths ]] || fail "tracked ARM files remain:\n$arm_paths"

if grep -Eiq 'Backend\.ARMThumb|qemu|arm-linux|thumb' \
    backend.ipkg Makefile src/Backend/DEX/Main.idr \
    .github/workflows/dex-verify.yml; then
  fail 'DEX build or CI still names an ARM/Thumb dependency'
fi

grep -qx 'package idric_dex' backend.ipkg ||
  fail 'generic package does not have DEX identity'
grep -qx 'executable = idric-dex' backend.ipkg ||
  fail 'generic executable does not have DEX identity'

if grep -q 'Backend.DEX.EncodeNativeActivity' backend.ipkg; then
  fail 'Wegert Android adapter leaked into the generic compiler package'
fi
grep -q 'Backend.DEX.EncodeNativeActivity' wegert-dex.ipkg ||
  fail 'Wegert Android adapter is absent from its DEX/Android package'

for arm_head in \
  e3a26f3a6b9098ef331dada3a4a0a29019dcaaf5 \
  ff8fa96ec7c5ecf89baa0a1e9796585bf47081db \
  d9345597e107743842d13fa5bf05313e7021ff32
do
  if git cat-file -e "$arm_head^{commit}" 2>/dev/null &&
     git merge-base --is-ancestor "$arm_head" HEAD; then
    fail "ARM development head $arm_head is an ancestor of the DEX line"
  fi
done

echo 'DEX branch separation PASS'
