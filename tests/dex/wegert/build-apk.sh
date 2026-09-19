#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
classes_dex=${1:-"$repo_root/build/exec/wegert/classes.dex"}
native_library=${2:-"$repo_root/build/exec/wegert/libwegert.so"}
output=${3:-"$repo_root/build/exec/wegert/wegert-test.apk"}
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
abi=${ANDROID_ABI:-x86_64}

case "$abi" in
  x86_64|x86|arm64-v8a|armeabi-v7a) ;;
  *)
    echo "unsupported Android ABI: $abi" >&2
    exit 1
    ;;
esac

[[ -f $classes_dex ]] || { echo "missing direct classes.dex: $classes_dex" >&2; exit 1; }
[[ -f $native_library ]] || { echo "missing libwegert.so: $native_library" >&2; exit 1; }
[[ -n $android_home ]] || { echo 'ANDROID_HOME/ANDROID_SDK_ROOT is required' >&2; exit 1; }

build_tools=${ANDROID_BUILD_TOOLS:-}
if [[ -z $build_tools ]]; then
  build_tools=$(find "$android_home/build-tools" -mindepth 1 -maxdepth 1 -type d |
    sort -V | tail -n 1)
fi
[[ -d $build_tools ]] || { echo 'Android build-tools not found' >&2; exit 1; }

aapt2="$build_tools/aapt2"
zipalign="$build_tools/zipalign"
apksigner="$build_tools/apksigner"
android_jar="$android_home/platforms/android-29/android.jar"
for required in "$aapt2" "$zipalign" "$apksigner" "$android_jar"; do
  [[ -e $required ]] || { echo "missing Android packaging input: $required" >&2; exit 1; }
done

work="$repo_root/build/exec/wegert/apk-work"
rm -rf "$work"
mkdir -p "$work/lib/$abi" "$(dirname -- "$output")"
cp "$native_library" "$work/lib/$abi/libwegert.so"

unsigned="$work/manifest.apk"
unaligned="$work/unaligned.apk"
aligned="$work/aligned.apk"

"$aapt2" link \
  -I "$android_jar" \
  --manifest "$repo_root/tests/dex/wegert/AndroidManifest.xml" \
  --min-sdk-version 21 \
  --target-sdk-version 29 \
  -o "$unsigned"

cp "$unsigned" "$unaligned"
zip -q -j "$unaligned" "$classes_dex"
(
  cd "$work"
  zip -q -u "$unaligned" "lib/$abi/libwegert.so"
)

"$zipalign" -f -p 4 "$unaligned" "$aligned"
keystore=${ANDROID_KEYSTORE:-}
keystore_password=${ANDROID_KEYSTORE_PASSWORD:-wegert-debug}
key_password=${ANDROID_KEY_PASSWORD:-$keystore_password}
key_alias=${ANDROID_KEY_ALIAS:-wegert-debug}
expected_signer_sha256=${ANDROID_EXPECTED_CERT_SHA256:-DE:9B:1D:47:C5:A6:5E:6D:46:A2:04:B7:9D:D9:EE:56:6B:9D:3C:98:32:BA:81:EB:C4:21:3D:33:92:E9:2F:F9}

[[ -n $keystore ]] || {
  echo 'ANDROID_KEYSTORE is required; refusing to generate a throwaway APK signer' >&2
  exit 1
}
[[ -f $keystore ]] || { echo "missing Android signing keystore: $keystore" >&2; exit 1; }

signer_sha256=$(
  keytool -list -v \
    -keystore "$keystore" \
    -storepass "$keystore_password" \
    -alias "$key_alias" 2>/dev/null |
    sed -n 's/^[[:space:]]*SHA256: //p' |
    head -n 1
)
[[ $signer_sha256 == "$expected_signer_sha256" ]] || {
  echo "unexpected Android test signer: ${signer_sha256:-missing}" >&2
  exit 1
}

"$apksigner" sign \
  --ks "$keystore" \
  --ks-key-alias "$key_alias" \
  --ks-pass "pass:$keystore_password" \
  --key-pass "pass:$key_password" \
  --out "$output" \
  "$aligned"

"$apksigner" verify --verbose --print-certs "$output" |
  tee "$work/signing.txt"
expected_digest=$(printf '%s' "$expected_signer_sha256" | tr '[:upper:]' '[:lower:]' | tr -d ':')
grep -Fq "Signer #1 certificate SHA-256 digest: $expected_digest" "$work/signing.txt"
printf 'APK native ABI          %s\n' "$abi"
