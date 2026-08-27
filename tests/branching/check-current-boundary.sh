#!/usr/bin/env bash
set -euo pipefail

: "${IDRIC:?set IDRIC to the pinned Idriç compiler}"

mkdir -p build/exec/branching-boundary

for source in tests/branching/*.idric; do
  name="$(basename "$source" .idric)"
  log="build/exec/branching-boundary/${name}.log"

  if IDRIS2_PATH="$PWD/build/ttc:${IDRIS2_PATH:-}" \
      ./build/exec/idric-arm-thumb \
        --cg arm-thumb \
        --source-dir tests/branching \
        "$source" \
        -o "$name" >"$log" 2>&1; then
    cat "$log"
    echo "$source unexpectedly compiled through control-flow lowering"
    exit 1
  fi

  if grep -q 'arm-thumb rejected source ABI' "$log"; then
    cat "$log"
    echo "$source stopped at the ABI boundary instead of reaching control-flow lowering"
    exit 1
  fi

  if ! grep -q 'arm-thumb rejected reachable program:' "$log"; then
    cat "$log"
    echo "$source failed before reaching the expected reachable-program boundary"
    exit 1
  fi
done

echo 'All branching/dispatch fixtures reached the current control-flow lowering boundary.'
