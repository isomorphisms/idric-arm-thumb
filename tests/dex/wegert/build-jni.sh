#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
output=${1:-"$repo_root/build/exec/wegert/libwegert.so"}
api=${ANDROID_API:-29}
abi=${ANDROID_ABI:-x86_64}

case "$abi" in
  x86_64) target=x86_64-linux-android ;;
  x86) target=i686-linux-android ;;
  arm64-v8a) target=aarch64-linux-android ;;
  armeabi-v7a) target=armv7a-linux-androideabi ;;
  *)
    echo "unsupported Android ABI: $abi" >&2
    exit 1
    ;;
esac

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

ndk_bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
clang="$ndk_bin/${target}${api}-clang"
readelf="$ndk_bin/llvm-readelf"
[[ -x $clang ]] || {
  echo "Android $abi clang not found: $clang" >&2
  exit 1
}
[[ -x $readelf ]] || {
  echo "Android NDK llvm-readelf not found: $readelf" >&2
  exit 1
}

mkdir -p "$(dirname -- "$output")"
"$clang" -shared -fPIC -O2 -Wl,--no-undefined -Wl,-soname,libwegert.so \
  "$repo_root/tests/dex/wegert/wegert_probe.c" -llog -landroid -o "$output"

# Finish readelf before grep -q can close a pipe and make LLVM exit 74.
# Keep readelf failure fatal even when its partial output contains a match.
symbols=$("$readelf" -Ws "$output")
grep -Fq 'Java_org_isomorphisms_wegert_WegertActivity_jniProbe' <<<"$symbols"
grep -Fq 'ANativeActivity_onCreate' <<<"$symbols"
printf 'JNI ABI                 %s\n' "$abi"
