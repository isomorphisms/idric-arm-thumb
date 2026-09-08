#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
adb_command=${ADB:-adb}
receipt=${WEGERT_PHONE_RECEIPT:-"$repo_root/build/exec/wegert/phone-receipt.txt"}
android_api=${ANDROID_API:-21}

mkdir -p "$(dirname -- "$receipt")"

fail_phone() {
  local reason=$1
  {
    echo 'physical Android phone FAIL'
    printf 'reason                 %s\n' "$reason"
  } >"$receipt"
  cat "$receipt"
  exit 1
}

command -v "$adb_command" >/dev/null 2>&1 || fail_phone 'adb is unavailable'
"$adb_command" get-state >/dev/null 2>&1 || fail_phone 'no Android device is connected'

kernel_qemu=$("$adb_command" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')
boot_qemu=$("$adb_command" shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')
[[ $kernel_qemu != 1 ]] || fail_phone 'connected runtime is an emulator (ro.kernel.qemu=1)'
[[ $boot_qemu != 1 ]] || fail_phone 'connected runtime is an emulator (ro.boot.qemu=1)'

phone_abi=$("$adb_command" shell getprop ro.product.cpu.abi | tr -d '\r')
phone_fingerprint=$("$adb_command" shell getprop ro.build.fingerprint | tr -d '\r')
case "$phone_abi" in
  x86_64|x86|arm64-v8a|armeabi-v7a) ;;
  *) fail_phone "unsupported phone ABI: ${phone_abi:-empty}" ;;
esac
[[ -n $phone_fingerprint ]] || fail_phone 'connected phone did not report a build fingerprint'

cd "$repo_root"
IDRIC=${IDRIC:-idris2} tests/dex/wegert-host-acceptance.sh

ANDROID_ABI="$phone_abi" ANDROID_API="$android_api" \
  tests/dex/wegert/build-jni.sh build/exec/wegert/libwegert.so
ANDROID_ABI="$phone_abi" \
  tests/dex/wegert/build-apk.sh \
    build/exec/wegert/classes.dex \
    build/exec/wegert/libwegert.so \
    build/exec/wegert/wegert-phone.apk

WEGERT_ART_RECEIPT="$receipt" \
  tests/dex/wegert/art-acceptance.sh build/exec/wegert/wegert-phone.apk

{
  echo 'physical Android phone PASS'
  printf 'phone ABI               %s\n' "$phone_abi"
  printf 'phone fingerprint       %s\n' "$phone_fingerprint"
  printf 'native API floor        %s\n' "$android_api"
} >>"$receipt"

printf '%s\n' 'physical Android phone PASS'
printf 'phone ABI               %s\n' "$phone_abi"
printf 'phone fingerprint       %s\n' "$phone_fingerprint"
printf 'native API floor        %s\n' "$android_api"
