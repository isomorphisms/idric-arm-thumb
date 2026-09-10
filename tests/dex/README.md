# DEX executable first slice

`examples/DexArithmetic.idric` is the candidate input. It is parsed,
elaborated, type checked, converted to `Compiler.ANF`, lowered into the typed
DEX plan, and encoded directly as `build/exec/classes.dex`.

The adjacent `.checked.anf`, `.dex.plan`, and `.smali` files retain the selected
checked compiler form and readable evidence from the same plan. The smali file
is never assembled into the candidate artifact.

`make dex-test` also:

- exercises constant formats 11n, 21s, and 31i at their cutovers;
- exercises all three non-wide move formats in the encoder self-test;
- rejects invalid register/branch ranges and a non-Int32 source export;
- verifies SHA-1 and Adler-32 independently;
- rejects a deliberately malformed candidate;
- disassembles the candidate with pinned baksmali;
- assembles the readable oracle separately and requires identical structural
  disassembly;
- regenerates the candidate byte-for-byte.

The receipt distinguishes these layers:

- source checked;
- DEX generated;
- independently parsed/disassembled;
- loaded by Android/ART;
- executed;
- result checked.

Missing Android device/runtime access is `NOT_VERIFIED`, never `PASS` or an
implicit success.

`device-acceptance.sh` assembles only `runtime/IdricRunner.smali`. That harness
invokes the methods in the separately supplied candidate DEX and checks
arithmetic, both branch directions, move, signed constant cutovers, and Int32
minimum/maximum values. It runs through Android `app_process`; it does not
replace or rewrite the candidate.

## Supported environments and test order

The host target is Debian 13. CI runs the compiler/backend acceptance inside
`debian:13-slim` and asserts `/etc/os-release` before building. The surrounding
GitHub-hosted VM is only CI infrastructure; Ubuntu is not a supported host
claim.

Android acceptance has two deliberately different levels:

1. one low-resource x86_64 emulator boot provides a fast ART sanity check for
   both the direct DEX candidate and the Wegert/JNI slice;
2. a physical Android phone is authoritative device evidence.

The emulator job is not called phone acceptance. It boots only once for both
runtime checks and uses a headless, low-memory configuration.

For a connected physical phone, run the host DEX validation first, then:

```sh
sh tests/dex/phone-acceptance.sh build/exec/classes.dex
```

`phone-acceptance.sh` uses the Smali harness already fetched by `dex-test`,
rejects Android emulators using the QEMU properties, then records the real
device build fingerprint and CPU ABI in the receipt.

For the Wegert NativeActivity/JNI slice, with the Android SDK/NDK available:

```sh
IDRIC=/path/to/idris2 \
  bash tests/dex/wegert/phone-acceptance.sh
```

That path reads `ro.product.cpu.abi` from the attached phone, builds
`libwegert.so` for that ABI (`armeabi-v7a`, `arm64-v8a`, x86, or x86_64),
packages the matching APK, installs it, and requires the JNI sentinel and
`ANativeActivity_onCreate` on the physical device.

Alpine/musl is not a target merely because its container image is smaller.
Use a lighter environment when it still represents a deployed environment;
do not introduce a third compatibility target solely for CI convenience.

## Android class/JNI boundary

`wegert-dex.ipkg` is a separate DEX/Android package. It directly emits the
Java-shaped `WegertActivity` class that ART expects, including NativeActivity
inheritance, construction, `System.loadLibrary`, a native method declaration,
and `onCreate`. This is exactly a use of DEX as the ART class target; it does
not use Java source or a Java compiler pipeline.

The adapter is currently Wegert-specific and hand encoded. The tests therefore
classify it as Android application-boundary acceptance, not as evidence that
the generic checked-ANF lowerer already supports arbitrary classes or Android
framework calls.
