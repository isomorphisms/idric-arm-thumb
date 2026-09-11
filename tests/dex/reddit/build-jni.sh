#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
output=${1:-"$repo_root/build/exec/reddit/libreddit_cli.so"}
api=${ANDROID_API:-24}
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
"$clang" -shared -fPIC -O2 -Wall -Wextra -Werror \
  -Wl,--no-undefined -Wl,-soname,libreddit_cli.so \
  "$repo_root/tests/dex/reddit/reddit_cli.c" -o "$output"

"$readelf" -Ws "$output" |
  grep -q 'Java_org_isomorphisms_reddit_RedditCli_run'
printf 'Reddit JNI ABI          %s\n' "$abi"
printf 'Reddit JNI API          %s\n' "$api"
