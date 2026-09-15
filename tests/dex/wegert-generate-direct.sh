#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
idric=${IDRIC:-idris2}
runtime_library=${IDRIC_RUNTIME_LIBRARY:-$(dirname -- "$idric")/idris2_app/libidris2_support.so}
build="$repo_root/build/exec"
generator="$build/wegert-dex-gen"
candidate="$build/wegert/classes.dex"
output=${1:-$candidate}

mkdir -p "$build/wegert" "$(dirname -- "$output")"

(
  cd "$repo_root"
  "$idric" --build wegert-dex.ipkg
  IDRIS2_PATH="$repo_root/build/ttc:${IDRIS2_PATH:-}" \
    "$idric" --source-dir "$repo_root/tests/dex" \
    "$repo_root/tests/dex/WegertDexGen.idr" -o wegert-dex-gen
)

[[ -f $runtime_library ]] || {
  echo "missing Idriç runtime library: $runtime_library" >&2
  exit 1
}
cp "$runtime_library" "${generator}_app/"

(
  cd "$repo_root"
  LD_LIBRARY_PATH="$(dirname -- "$runtime_library"):${LD_LIBRARY_PATH:-}" \
    "$generator"
)

python3 "$repo_root/tests/dex/check_wegert_dex.py" "$candidate"

if [[ $output != "$candidate" ]]; then
  cp "$candidate" "$output"
fi

printf 'PASS: direct Wegert classes.dex %s\n' "$output"
printf 'SHA-256: %s\n' "$(sha256sum "$output" | cut -d' ' -f1)"
