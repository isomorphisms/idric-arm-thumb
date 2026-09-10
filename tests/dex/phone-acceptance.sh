#!/bin/sh
set -eu

candidate=${1:-build/exec/classes.dex}
adb_command=${ADB:-adb}
receipt=${DEX_PHONE_RECEIPT:-build/exec/dex-phone-receipt.txt}
smali_jar=${SMALI_JAR:-build/oracles/smali-3.0.10.jar}

mkdir -p "$(dirname "$receipt")"

fail_phone() {
  reason=$1
  {
    printf '%s\n' 'physical Android phone FAIL'
    printf 'reason                 %s\n' "$reason"
  } >"$receipt"
  cat "$receipt"
  exit 1
}

command -v "$adb_command" >/dev/null 2>&1 || fail_phone 'adb is unavailable'
"$adb_command" get-state >/dev/null 2>&1 || fail_phone 'no Android device is connected'
[ -f "$smali_jar" ] || fail_phone "runtime harness assembler is absent: $smali_jar"

kernel_qemu=$("$adb_command" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')
boot_qemu=$("$adb_command" shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')
[ "$kernel_qemu" != 1 ] || fail_phone 'connected runtime is an emulator (ro.kernel.qemu=1)'
[ "$boot_qemu" != 1 ] || fail_phone 'connected runtime is an emulator (ro.boot.qemu=1)'

phone_abi=$("$adb_command" shell getprop ro.product.cpu.abi | tr -d '\r')
phone_fingerprint=$("$adb_command" shell getprop ro.build.fingerprint | tr -d '\r')
[ -n "$phone_abi" ] || fail_phone 'connected phone did not report a CPU ABI'
[ -n "$phone_fingerprint" ] || fail_phone 'connected phone did not report a build fingerprint'

SMALI_JAR="$smali_jar" DEX_DEVICE_RECEIPT="$receipt" \
  tests/dex/device-acceptance.sh "$candidate"

{
  printf '%s\n' 'physical Android phone PASS'
  printf 'phone ABI               %s\n' "$phone_abi"
  printf 'phone fingerprint       %s\n' "$phone_fingerprint"
} >>"$receipt"

printf '%s\n' 'physical Android phone PASS'
printf 'phone ABI               %s\n' "$phone_abi"
printf 'phone fingerprint       %s\n' "$phone_fingerprint"
