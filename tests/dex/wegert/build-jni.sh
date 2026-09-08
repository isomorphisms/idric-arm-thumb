#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
output=${1:-"$repo_root/build/exec/wegert/libwegert.so"}
api=${ANDROID_API:-29}

ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [[ -z $ndk ]]; then
  android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  [[ -n $android_home ]] || {
    echo 'ANDROID_HOME/ANDROID_SDK_ROOT is required' >&2
    exit 1
  }
  ndk=$(find "$android_home/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
    sort -V | tail -n 1)
fi
[[ -n $ndk && -d $ndk ]] || {
  echo 'Android NDK not found' >&2
  exit 1
}

clang="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android${api}-clang"
[[ -x $clang ]] || {
  echo "Android x86_64 clang not found: $clang" >&2
  exit 1
}

mkdir -p "$(dirname -- "$output")"
"$clang" -shared -fPIC -O2 -Wl,--no-undefined -Wl,-soname,libwegert.so \
  "$repo_root/tests/dex/wegert/wegert_probe.c" -llog -landroid -o "$output"

readelf -Ws "$output" | grep -q 'Java_org_isomorphisms_wegert_WegertActivity_jniProbe'
readelf -Ws "$output" | grep -q 'ANativeActivity_onCreate'
