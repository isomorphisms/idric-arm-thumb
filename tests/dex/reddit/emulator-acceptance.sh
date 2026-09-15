#!/usr/bin/env bash
# Exercise the direct DEX/JNI command boundary inside one shell process.
# android-emulator-runner executes multiline `script` entries line by line,
# so status variables, traps, redirections, and continuations belong here.
set -eu

work=build/exec/reddit
device=/data/local/tmp/idric-reddit
mkdir -p "$work"

adb logcat -c || true
save_logcat() {
  adb logcat -d -v threadtime > "$work/emulator-logcat.txt" 2>&1 || true
}
trap save_logcat EXIT

adb shell 'getprop ro.build.version.release; getprop ro.product.cpu.abi; getenforce' \
  > "$work/emulator-device.txt" 2>&1 || true
adb shell "mkdir -p $device"
adb push "$work/classes.dex" "$device/classes.dex"
adb push "$work/libreddit_cli-x86_64.so" "$device/libreddit_cli.so"

set +e
adb shell 'CLASSPATH=/data/local/tmp/idric-reddit/classes.dex /system/bin/app_process -Dreddit.library=/data/local/tmp/idric-reddit/libreddit_cli.so /system/bin org.isomorphisms.reddit.RedditCli url "computer science degree regret"' \
  > "$work/emulator-url.raw.txt" 2>&1
url_status=$?
set -e
printf '%s\n' "$url_status" > "$work/emulator-url.status"
tr -d '\r' < "$work/emulator-url.raw.txt" > "$work/emulator-url.txt"
cat "$work/emulator-url.txt"
test "$url_status" -eq 0
grep -Fq 'q=computer%20science%20degree%20regret' "$work/emulator-url.txt"

set +e
adb shell 'CLASSPATH=/data/local/tmp/idric-reddit/classes.dex /system/bin/app_process -Dreddit.library=/data/local/tmp/idric-reddit/libreddit_cli.so /system/bin org.isomorphisms.reddit.RedditCli search "computer science degree regret"' \
  > "$work/emulator-no-token.txt" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$work/emulator-no-token.status"
cat "$work/emulator-no-token.txt"
test "$status" -ne 0
grep -Fq 'reddit: missing REDDIT_ACCESS_TOKEN' "$work/emulator-no-token.txt"

printf 'reddit_dex_jni_emulator=pass\n'