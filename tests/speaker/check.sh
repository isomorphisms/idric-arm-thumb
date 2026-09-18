#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

ARM_CLANG=${ARM_CLANG:-clang}
ARM_EXEC_TARGET=${ARM_EXEC_TARGET:-armv7a-linux-gnueabihf}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
FILE=${FILE:-file}
READ_ELF=${READ_ELF:-readelf}

out_dir=${OUT_DIR:-"$repo_root/build/exec/speaker-tone"}
program="$out_dir/speaker-tone.armv7-thumb2"

mkdir -p "$out_dir"

"$ARM_CLANG" --target="$ARM_EXEC_TARGET" -fuse-ld=lld -nostdlib -static \
    -march=armv7-a -mthumb \
    -Wl,-e,_start -Wl,--no-dynamic-linker \
    "$script_dir/speaker_tone.S" -o "$program"

"$FILE" "$program" | grep -q 'ELF 32-bit.*ARM'
"$READ_ELF" -h "$program" | grep -q 'Class:.*ELF32'
"$READ_ELF" -h "$program" | grep -q 'Machine:.*ARM'

if [ ! -e /dev/dsp ]; then
    set +e
    "$QEMU_ARM" -cpu cortex-a9 "$program"
    status=$?
    set -e
    if [ "$status" -ne 10 ]; then
        printf 'FAIL: expected no-/dev/dsp exit 10 under qemu-arm, got %s\n' "$status" >&2
        exit 1
    fi
    printf '%s\n' 'PASS: qemu-arm exercised the explicit no-/dev/dsp path (exit 10)'
else
    printf '%s\n' 'SKIP: host has /dev/dsp; device playback belongs to the full-system receipt'
fi

printf '%s\n' \
    'PASS: ARMv7 Thumb speaker-tone oracle assembled, linked, and inspected' \
    'PENDING: full-system virtual audio playback and WAV capture'
