#!/usr/bin/env bash
set -euo pipefail

: "${IDRIC:?set IDRIC to the declared Idriç compiler}"

mkdir -p build/exec/branching-boundary

for source in tests/branching/*.idric; do
  name="$(basename "$source" .idric)"
  log="build/exec/branching-boundary/${name}.log"
  artifact="build/exec/${name}.arm-thumb.S"

  if [[ -e "$artifact" ]]; then
    echo "Remove stale $artifact before the boundary test"
    exit 1
  fi

  IDRIS2_PATH="$PWD/build/ttc:${IDRIS2_PATH:-}" \
      ./build/exec/idric-arm-thumb \
        --cg arm-thumb \
        --source-dir tests/branching \
        "$source" \
        -o "$name" >"$log" 2>&1 || true

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

  if [[ -e "$artifact" ]]; then
    cat "$log"
    echo "$source emitted an artifact despite the reachable-program rejection"
    exit 1
  fi
done

echo 'All branching/dispatch fixtures reached the current control-flow lowering boundary.'
