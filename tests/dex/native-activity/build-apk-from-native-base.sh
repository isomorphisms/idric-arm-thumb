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
if [[ -z $build_tools ]]; then
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
keystore="$work/debug.keystore"

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
  zip -q -r "$unaligned" lib assets
)

"$zipalign" -f -p 4 "$unaligned" "$aligned"
keytool -genkeypair -noprompt \
  -keystore "$keystore" \
  -storepass android \
  -keypass android \
  -alias androiddebugkey \
  -dname 'CN=Android Debug,O=Android,C=US' \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 >/dev/null 2>&1
"$apksigner" sign \
  --ks "$keystore" \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$output" \
  "$aligned"
"$apksigner" verify --verbose "$output"

unzip -l "$output" > "$work/files.txt"
grep -Eq '[[:space:]]classes\.dex$' "$work/files.txt"
grep -Eq '[[:space:]]lib/x86_64/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]lib/arm64-v8a/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]lib/armeabi-v7a/.+\.so$' "$work/files.txt"
grep -Eq '[[:space:]]assets/.+' "$work/files.txt"

printf 'direct DEX APK         %s\n' "$output"
printf 'direct classes SHA-256 %s\n' "$(sha256sum "$classes_dex" | cut -d' ' -f1)"
printf 'base native APK SHA-256 %s\n' "$(sha256sum "$base_apk" | cut -d' ' -f1)"
