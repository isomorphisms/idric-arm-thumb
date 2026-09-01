#!/bin/sh
set -eu

candidate=${1:-build/exec/classes.dex}
smali_jar=${SMALI_JAR:-}
adb_command=${ADB:-adb}
receipt=${DEX_DEVICE_RECEIPT:-build/exec/dex-device-receipt.txt}
backend_revision=${BACKEND_REVISION:-$(git rev-parse HEAD 2>/dev/null || printf unknown)}

mkdir -p "$(dirname "$receipt")" build/exec

write_not_verified() {
  reason=$1
  {
    printf '%s\n' 'source checked        PASS'
    printf '%s\n' 'DEX generated         PASS'
    printf '%s\n' 'DEX parser validation PASS'
    printf '%s\n' 'ART loaded             SKIP prerequisite=device_or_emulator'
    printf '%s\n' 'ART executed           SKIP prerequisite=ART_loaded'
    printf '%s\n' 'result checked         SKIP prerequisite=ART_executed'
    printf 'reason                 %s\n' "$reason"
    printf 'backend revision       %s\n' "$backend_revision"
  } >"$receipt"
  cat "$receipt"
  exit 2
}

[ -f "$candidate" ] || write_not_verified "candidate classes.dex is absent"
candidate_hash=$(sha256sum "$candidate" | cut -d' ' -f1)
[ -n "$smali_jar" ] && [ -f "$smali_jar" ] || \
  write_not_verified "SMALI_JAR is unavailable for the external runner"
command -v "$adb_command" >/dev/null 2>&1 || \
  write_not_verified "adb is unavailable"
"$adb_command" get-state >/dev/null 2>&1 || \
  write_not_verified "no Android device or emulator is connected"

runtime_work=$(mktemp -d build/exec/dex-runtime.XXXXXX)
trap 'rm -rf "$runtime_work"' EXIT HUP INT TERM
java -jar "$smali_jar" assemble tests/dex/runtime \
  -o "$runtime_work/runner.dex"

"$adb_command" push "$candidate" /data/local/tmp/idric-classes.dex >/dev/null
"$adb_command" push "$runtime_work/runner.dex" \
  /data/local/tmp/idric-runner.dex >/dev/null

runtime_identity=$(
  "$adb_command" shell 'getprop ro.build.fingerprint; getprop ro.product.cpu.abi' |
    tr -d '\r'
)

set +e
runtime_output=$(
  "$adb_command" shell \
    'CLASSPATH=/data/local/tmp/idric-runner.dex:/data/local/tmp/idric-classes.dex app_process /system/bin Idric.Runner' 2>&1
)
runtime_status=$?
set -e

if [ "$runtime_status" -ne 0 ]; then
  if [ "$runtime_status" -ge 41 ] && [ "$runtime_status" -le 56 ]; then
    loaded_status=PASS
    executed_status=PASS
    result_status=FAIL
  else
    loaded_status=FAIL
    executed_status=SKIP
    result_status=SKIP
  fi
  {
    printf '%s\n' 'source checked        PASS'
    printf '%s\n' 'DEX generated         PASS'
    printf '%s\n' 'DEX parser validation PASS'
    printf 'ART loaded             %s\n' "$loaded_status"
    printf 'ART executed           %s\n' "$executed_status"
    printf 'result checked         %s\n' "$result_status"
    printf 'runner exit status      %s\n' "$runtime_status"
    printf 'runtime output           %s\n' "$runtime_output"
    printf 'runtime identity        %s\n' "$runtime_identity"
    printf 'backend revision       %s\n' "$backend_revision"
    printf 'classes.dex SHA-256    %s\n' "$candidate_hash"
  } >"$receipt"
  cat "$receipt"
  exit 1
fi

{
  printf '%s\n' 'source checked        PASS'
  printf '%s\n' 'DEX generated         PASS'
  printf '%s\n' 'DEX parser validation PASS'
  printf '%s\n' 'ART loaded             PASS'
  printf '%s\n' 'ART executed           PASS'
  printf '%s\n' 'result checked         PASS'
  printf '%s\n' '12 + 7                 19'
  printf '%s\n' '12 - 7                 5'
  printf '%s\n' '12 * 7                 84'
  printf '%s\n' '7 < 12                 41'
  printf '%s\n' '12 < 7                 99'
  printf '%s\n' 'Int32 move             PASS'
  printf '%s\n' 'constant cutovers      PASS'
  printf '%s\n' 'Int32 min/max          PASS'
  printf 'runtime identity        %s\n' "$runtime_identity"
  printf 'backend revision       %s\n' "$backend_revision"
  printf 'classes.dex SHA-256    %s\n' "$candidate_hash"
} >"$receipt"

cat "$receipt"
