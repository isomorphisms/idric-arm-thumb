#!/usr/bin/env bash
set -euo pipefail

: "${IDRIC:?set IDRIC to the pinned Idriç compiler}"

make driver IDRIC="$IDRIC"

mkdir -p build/exec/character-boundary

for source in tests/characters/*.idric; do
  name="$(basename "$source" .idric)"
  log="build/exec/character-boundary/${name}.log"

  if IDRIS2_PATH="$PWD/build/ttc:${IDRIS2_PATH:-}" \
      ./build/exec/idric-arm-thumb \
        --cg arm-thumb \
        --source-dir tests/characters \
        "$source" \
        -o "$name" >"$log" 2>&1; then
    cat "$log"
    echo "$source unexpectedly compiled through the current ARM/Thumb backend"
    exit 1
  fi

  if ! grep -q 'arm-thumb rejected source ABI' "$log"; then
    cat "$log"
    echo "$source failed before reaching the expected ARM/Thumb source-ABI boundary"
    exit 1
  fi

done

echo 'All character/UTF-8 fixtures typechecked far enough to reach the current ARM/Thumb IO/ABI boundary.'
