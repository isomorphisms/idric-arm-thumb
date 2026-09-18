#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=${WORK_DIR:-"$script_dir/build"}
cc=${ARM_CC:-arm-linux-gnueabihf-gcc}
qemu=${QEMU_ARM:-qemu-arm}
sysroot=${ARM_SYSROOT:-/usr/arm-linux-gnueabihf}

rm -rf "$work"
mkdir -p "$work"

for name in gpio_output gpio_input gpio_edge_wait; do
    "$cc" -std=c11 -Wall -Wextra -Werror -O2 \
        -I"$script_dir" "$script_dir/$name.c" -o "$work/$name"
    file "$work/$name" | grep -q 'ELF 32-bit.*ARM'
    set +e
    "$qemu" -L "$sysroot" "$work/$name" /dev/idric-gpio-does-not-exist 0 >/dev/null 2>&1
    status=$?
    set -e
    [ "$status" -eq 10 ] || {
        printf 'FAIL: %s no-chip status %s, expected 10\n' "$name" "$status" >&2
        exit 1
    }
done

printf '%s\n' \
    'PASS: ARMv7 GPIO v2 oracles build as native ARM EABI executables' \
    'PASS: qemu-arm confirms the explicit no-chip boundary for all three actions'
