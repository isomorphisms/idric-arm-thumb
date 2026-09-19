#!/bin/sh
set -eu

IDRIC=${IDRIC:-idris2}
DRIVER=${DRIVER:-build/exec/idric-arm-thumb}
BUILD_DIR=${BUILD_DIR:-build/ib-display-repair}
LOG="$BUILD_DIR/compiler.log"

mkdir -p "$BUILD_DIR"

if "$DRIVER" --cg arm-thumb --source-dir tests/ib \
    tests/ib/DisplayRepairMain.idric -o ib-display-repair >"$LOG" 2>&1; then
  test -f build/exec/ib-display-repair.arm-thumb.S
  echo 'IB.DisplayRepair crossed the current ARM/Thumb backend boundary.'
  exit 0
fi

grep -q 'arm-thumb rejected' "$LOG"
grep -Eq 'source ABI|reachable program' "$LOG"
echo 'IB.DisplayRepair reached the ARM/Thumb backend and stopped at the known ordinary-value/runtime boundary.'
