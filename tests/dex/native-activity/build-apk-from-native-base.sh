#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
base_apk=${1:?usage: build-apk-from-native-base.sh BASE_APK CLASSES_DEX MANIFEST OUTPUT}
classes_dex=${2:?usage: build-apk-from-native-base.sh BASE_APK CLASSES_DEX MANIFEST OUTPUT}
manifest=${3:?usage: build-apk-from-native-base.sh BASE_APK CLASSES_DEX MANIFEST OUTPUT}
output=${4:?usage: build-apk-from-native-base.sh BASE_APK CLASSES_DEX MANIFEST OUTPUT}
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}

for required in "$base_apk" "$classes_dex" "$manifest"; do
  [[ -f $required ]] || { echo "missing APK input: $required" >&2; exit 1; }
done
[[ -n $android_home ]] || { echo 'ANDROID_HOME/ANDROID_SDK_ROOT is required' >&2; exit 1; }

build_tools=${ANDROID_BUILD_TOOLS:-}
if [[ -z $build_tools || ! -d $build_tools ]]; then
  build_tools=$(find "$android_home/build-tools" -mindepth 1 -maxdepth 1 -type d |
    sort -V | tail -n 1)
fi
[[ -d $build_tools ]] || { echo 'Android build-tools not found' >&2; exit 1; }

aapt2="$build_tools/aapt2"
zipalign="$build_tools/zipalign"
apksigner="$build_tools/apksigner"
android_jar="$android_home/platforms/android-36/android.jar"
for required in "$aapt2" "$zipalign" "$apksigner" "$android_jar"; do
  [[ -e $required ]] || { echo "missing Android packaging input: $required" >&2; exit 1; }
done

name=$(basename -- "$output" .apk)
work="$repo_root/build/exec/native-shell/apk-work/$name"
payload="$work/payload"
rm -rf "$work"
mkdir -p "$payload" "$(dirname -- "$output")"

# Reuse only the already-built native renderer and opaque runtime assets.
# The Android class/lifecycle layer is replaced by the direct DEX candidate.
unzip -q "$base_apk" 'lib/*' 'assets/*' -d "$payload"
test -d "$payload/lib"

unsigned="$work/manifest.apk"
unaligned="$work/unaligned.apk"
aligned="$work/aligned.apk"

"$aapt2" link \
  -I "$android_jar" \
  --manifest "$manifest" \
  --min-sdk-version 26 \
  --target-sdk-version 36 \
  -o "$unsigned"

cp "$unsigned" "$unaligned"
zip -q -j "$unaligned" "$classes_dex"
(
  cd "$payload"
  # Android packages that request extractNativeLibs=false must keep native
  # libraries uncompressed so the loader can mmap them directly from the APK.
  zip -q -0 -r "$unaligned" lib
  zip -q -r "$unaligned" assets
)

# Align uncompressed native libraries for both 4 KiB and 16 KiB page devices.
"$zipalign" -P 16 -f 4 "$unaligned" "$aligned"
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
"$zipalign" -c -P 16 -v 4 "$output" >/dev/null

unzip -lv "$output" > "$work/files.txt"
grep -Eq '[[:space:]]classes\.dex$' "$work/files.txt"
grep -Eq '[[:space:]]lib/x86_64/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]lib/arm64-v8a/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]lib/armeabi-v7a/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]assets/.+' "$work/files.txt"
awk '
  $8 ~ /^lib\/.+\.so$/ && $2 != "Stored" {
    print "compressed native library: " $8 > "/dev/stderr"
    bad = 1
  }
  END { exit bad }
' "$work/files.txt"

printf 'direct DEX APK          %s\n' "$output"
printf 'direct classes SHA-256 %s\n' "$(sha256sum "$classes_dex" | cut -d' ' -f1)"
printf 'base native APK SHA-256 %s\n' "$(sha256sum "$base_apk" | cut -d' ' -f1)"
