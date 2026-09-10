#!/usr/bin/env bash
set -Eeuo pipefail

apk=${1:-build/exec/wegert/wegert-test.apk}
adb_command=${ADB:-adb}
receipt=${WEGERT_ART_RECEIPT:-build/exec/wegert/art-receipt.txt}
package=org.isomorphisms.wegert
component="$package/.WegertActivity"

mkdir -p "$(dirname -- "$receipt")"

fail_receipt() {
  explanation=$1
  {
    echo 'APK installed           FAIL'
    echo 'WegertActivity started SKIP'
    echo 'JNI probe linked       SKIP'
    echo 'JNI sentinel observed  SKIP'
    echo 'NativeActivity entered SKIP'
    printf 'reason                  %s\n' "$explanation"
  } >"$receipt"
  cat "$receipt"
  exit 1
}

[[ -f $apk ]] || fail_receipt "APK is absent: $apk"
command -v "$adb_command" >/dev/null 2>&1 || fail_receipt 'adb unavailable'
"$adb_command" get-state >/dev/null 2>&1 || fail_receipt 'no Android runtime connected'

"$adb_command" uninstall "$package" >/dev/null 2>&1 || true
"$adb_command" install -r "$apk" >/dev/null || fail_receipt 'adb install failed'
trap '"$adb_command" uninstall "$package" >/dev/null 2>&1 || true' EXIT

"$adb_command" logcat -c
"$adb_command" shell am force-stop "$package"
start_output=$("$adb_command" shell am start -W -n "$component" 2>&1 | tr -d '\r')
printf '%s\n' "$start_output" | grep -q 'Status: ok' ||
  fail_receipt "activity start failed: $start_output"

logs=
for _ in 1 2 3 4 5; do
  logs=$("$adb_command" logcat -d -v brief 2>/dev/null | tr -d '\r')
  if printf '%s\n' "$logs" | grep -q 'IdricWegert.*jniProbe=47047' &&
     printf '%s\n' "$logs" | grep -q 'IdricWegert.*ANativeActivity_onCreate'; then
    break
  fi
  sleep 1
done

printf '%s\n' "$logs" | grep -q 'IdricWegert.*jniProbe=47047' ||
  fail_receipt 'JNI probe sentinel was not observed'
printf '%s\n' "$logs" | grep -q 'IdricWegert.*ANativeActivity_onCreate' ||
  fail_receipt 'NativeActivity native entry was not observed'

if printf '%s\n' "$logs" | grep -E -q 'VerifyError|UnsatisfiedLinkError|ClassNotFoundException'; then
  fail_receipt 'ART/linker error found in logcat'
fi

runtime_identity=$(
  "$adb_command" shell 'getprop ro.build.fingerprint; getprop ro.product.cpu.abi' |
    tr -d '\r'
)

{
  echo 'APK installed           PASS'
  echo 'WegertActivity started  PASS'
  echo 'JNI probe linked        PASS'
  echo 'JNI sentinel observed   PASS value=47047'
  echo 'NativeActivity entered  PASS'
  printf 'runtime identity        %s\n' "$runtime_identity"
  printf 'APK SHA-256             %s\n' "$(sha256sum "$apk" | cut -d' ' -f1)"
} >"$receipt"

cat "$receipt"
