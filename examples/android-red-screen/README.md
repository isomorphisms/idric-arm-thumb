# Android ARMv7 red-screen probe

This is the unrooted Android-phone counterpart to the ordinary Linux fbdev sample.
It is deliberately a small application harness, not an Idriç compiler-acceptance claim.

The APK contains no application `classes.dex`. Android's framework `NativeActivity`
loads `libredscreen.so`; the activity obtains an `ANativeWindow`, locks its CPU-visible
buffer, and calls a handwritten ARMv7 Thumb-2 leaf that fills the visible surface red.
The activity keeps the window fullscreen and red for about three seconds, then asks
Android to finish it.

```text
android.app.NativeActivity
        ↓
ANativeWindow
        ↓
ANativeWindow_lock
        ↓
ARMv7 Thumb-2 fill_red_8888 / fill_red_565
        ↓
ANativeWindow_unlockAndPost
```

No root access, Termux runtime, direct `/dev/fb0`, Binder protocol implementation,
or Java/Kotlin application source is required. `libandroid.so` is the Android-specific
boundary. The top-level Idriç meaning remains something like “show the selected display
red”; this APK is one replaceable Android implementation beneath that action.

## Build

The build intentionally avoids Gradle. It needs an Android SDK platform, Android SDK
Build Tools, and an NDK. On a Linux build host with those installed:

```sh
ANDROID_SDK_ROOT=/path/to/sdk \
ANDROID_NDK_HOME=/path/to/sdk/ndk/26.3.11579264 \
BUILD_TOOLS_VERSION=35.0.0 \
sh examples/android-red-screen/build.sh
```

The phone artifact is:

```text
examples/android-red-screen/build/red-screen-armv7.apk
```

The builder verifies that the native library is ELF32 ARM, links `libandroid.so`,
contains the two Thumb fill leaves, packages only `lib/armeabi-v7a/libredscreen.so`,
zip-aligns the APK, signs it with a disposable debug key unless `KEYSTORE` is supplied,
and verifies the signature. The resulting APK still needs actual installation and
physical-device launch before the red-screen behavior is accepted.

## Install on this phone

Once an APK is published somewhere reachable from the phone, download it normally and
open it with Android's package installer. In Termux, `termux-open red-screen-armv7.apk`
is merely a convenient way to hand the APK to the package installer; Termux is not part
of the application's runtime.

## Evidence boundary

A successful host build proves packaging and native-code identity only. It does not prove
installation, launch, window creation, pixel presentation, timing, or physical-display
behavior. Those remain separate phone receipts.
