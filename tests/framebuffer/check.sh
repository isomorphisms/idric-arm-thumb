#!/bin/sh
set -eu

ARM_CLANG=${ARM_CLANG:-clang}
ARM_EXEC_TARGET=${ARM_EXEC_TARGET:-armv7a-linux-gnueabihf}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
OUT=${OUT:-build/exec/framebuffer-rgb565-oracle}

mkdir -p "$(dirname "$OUT")"

"$ARM_CLANG" --target="$ARM_EXEC_TARGET" -fuse-ld=lld -nostdlib -static \
  -march=armv7-a -mthumb \
  -Wl,-e,_start -Wl,--no-dynamic-linker \
  tests/framebuffer/rgb565_oracle.S -o "$OUT"

file "$OUT" | grep -q 'ELF 32-bit.*ARM'
readelf -h "$OUT" | grep -q 'Class:.*ELF32'
readelf -h "$OUT" | grep -q 'Machine:.*ARM'

"$QEMU_ARM" -cpu cortex-a9 "$OUT"
