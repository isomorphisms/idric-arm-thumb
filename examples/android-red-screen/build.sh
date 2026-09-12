#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
NDK_ROOT=${ANDROID_NDK_HOME:-}
ANDROID_API=${ANDROID_API:-23}
SDK_PLATFORM=${SDK_PLATFORM:-28}
BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION:-35.0.0}
OUT_INPUT=${OUT:-"$ROOT/build"}

if [ -z "$SDK_ROOT" ]; then
    printf '%s\n' 'ANDROID_SDK_ROOT or ANDROID_HOME is required' >&2
    exit 2
fi

if [ -z "$NDK_ROOT" ]; then
    printf '%s\n' 'ANDROID_NDK_HOME is required' >&2
    exit 2
fi

rm -rf "$OUT_INPUT"
mkdir -p "$OUT_INPUT"
OUT=$(CDPATH= cd -- "$OUT_INPUT" && pwd)

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
CC="$TOOLCHAIN/armv7a-linux-androideabi${ANDROID_API}-clang"
READELF="$TOOLCHAIN/llvm-readelf"
OBJDUMP="$TOOLCHAIN/llvm-objdump"
AAPT2="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/aapt2"
ZIPALIGN="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/zipalign"
APKSIGNER="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/apksigner"
ANDROID_JAR="$SDK_ROOT/platforms/android-$SDK_PLATFORM/android.jar"

for required in "$CC" "$READELF" "$OBJDUMP" "$AAPT2" "$ZIPALIGN" "$APKSIGNER" "$ANDROID_JAR"; do
    if [ ! -e "$required" ]; then
        printf 'missing required build input: %s\n' "$required" >&2
        exit 2
    fi
done

"$CC" \
    -std=c11 \
    -Oz \
    -fPIC \
    -ffunction-sections \
    -fdata-sections \
    -fvisibility=hidden \
    -march=armv7-a \
    -mthumb \
    -shared \
    -Wl,--gc-sections \
    -Wl,--no-undefined \
    -Wl,-soname,libredscreen.so \
    "$ROOT/red_screen.c" \
    "$ROOT/fill_red.S" \
    -landroid \
    -o "$OUT/libredscreen.so"

file "$OUT/libredscreen.so"
"$READELF" -h "$OUT/libredscreen.so" > "$OUT/libredscreen.elf.txt"
"$READELF" -d "$OUT/libredscreen.so" > "$OUT/libredscreen.dynamic.txt"
"$OBJDUMP" -d "$OUT/libredscreen.so" > "$OUT/libredscreen.disassembly.txt"

grep -q 'Class:.*ELF32' "$OUT/libredscreen.elf.txt"
grep -q 'Machine:.*ARM' "$OUT/libredscreen.elf.txt"
grep -q 'libandroid.so' "$OUT/libredscreen.dynamic.txt"
grep -q 'fill_red_8888' "$OUT/libredscreen.disassembly.txt"
grep -q 'fill_red_565' "$OUT/libredscreen.disassembly.txt"

"$AAPT2" link \
    --manifest "$ROOT/AndroidManifest.xml" \
    -I "$ANDROID_JAR" \
    --min-sdk-version 23 \
    --target-sdk-version 28 \
    -o "$OUT/base.apk"

mkdir -p "$OUT/package/lib/armeabi-v7a"
cp "$OUT/libredscreen.so" "$OUT/package/lib/armeabi-v7a/libredscreen.so"
cp "$OUT/base.apk" "$OUT/red-screen-unsigned.apk"
(
    cd "$OUT/package"
    zip -q -r "$OUT/red-screen-unsigned.apk" lib
)

"$ZIPALIGN" -f -p 4 \
    "$OUT/red-screen-unsigned.apk" \
    "$OUT/red-screen-aligned.apk"

KEYSTORE=${KEYSTORE:-"$OUT/red-screen-debug.keystore"}
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storepass android \
        -keypass android \
        -alias redscreen \
        -dname 'CN=Red Screen Debug,O=isomorphisms' \
        -keyalg RSA \
        -keysize 2048 \
        -validity 3650 \
        -noprompt
fi

"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-key-alias redscreen \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$OUT/red-screen-armv7.apk" \
    "$OUT/red-screen-aligned.apk"

"$APKSIGNER" verify --verbose --print-certs "$OUT/red-screen-armv7.apk" \
    > "$OUT/apksigner.txt"
"$ZIPALIGN" -c -p 4 "$OUT/red-screen-armv7.apk"

unzip -l "$OUT/red-screen-armv7.apk" > "$OUT/apk-contents.txt"
grep -q 'lib/armeabi-v7a/libredscreen.so' "$OUT/apk-contents.txt"
if grep -q 'classes.dex' "$OUT/apk-contents.txt"; then
    printf '%s\n' 'unexpected classes.dex in native-only APK' >&2
    exit 1
fi

sha256sum "$OUT/red-screen-armv7.apk" > "$OUT/red-screen-armv7.apk.sha256"
cat "$OUT/red-screen-armv7.apk.sha256"
printf 'apk=%s\n' "$OUT/red-screen-armv7.apk"
