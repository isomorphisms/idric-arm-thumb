#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

ARM_CLANG=${ARM_CLANG:-clang}
ARM_EXEC_TARGET=${ARM_EXEC_TARGET:-armv7a-linux-gnueabihf}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
READ_ELF=${READ_ELF:-readelf}
FILE=${FILE:-file}

out_dir=${OUT_DIR:-"$repo_root/build/exec/framebuffer"}
oracle="$out_dir/rgb565-oracle.armv7-thumb2"
fbdev="$out_dir/linux-fbdev-red.armv7-thumb2"

mkdir -p "$out_dir"

"$ARM_CLANG" --target="$ARM_EXEC_TARGET" -fuse-ld=lld -nostdlib -static \
  -march=armv7-a -mthumb \
  -Wl,-e,_start -Wl,--no-dynamic-linker \
  "$script_dir/rgb565_oracle.S" -o "$oracle"

"$FILE" "$oracle" | grep -q 'ELF 32-bit.*ARM'
"$READ_ELF" -h "$oracle" | grep -q 'Class:.*ELF32'
"$READ_ELF" -h "$oracle" | grep -q 'Machine:.*ARM'

"$QEMU_ARM" -cpu cortex-a9 "$oracle"

"$ARM_CLANG" --target="$ARM_EXEC_TARGET" -fuse-ld=lld -nostdlib -static \
  -march=armv7-a -mthumb \
  -Wl,-e,_start -Wl,--no-dynamic-linker \
  "$script_dir/linux_fbdev_red.S" -o "$fbdev"

"$FILE" "$fbdev" | grep -q 'ELF 32-bit.*ARM'
"$READ_ELF" -h "$fbdev" | grep -q 'Class:.*ELF32'
"$READ_ELF" -h "$fbdev" | grep -q 'Machine:.*ARM'

printf '%s\n' \
  'PASS: RGB565 oracle assembled, inspected, and executed under qemu-arm' \
  'PASS: Linux fbdev red-screen reference assembled and inspected' \
  'PENDING: full-system guest display execution and presented-output capture'
