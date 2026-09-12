# Android hardware sample programs

These are ARM/Thumb sample targets for small hardware-facing programs that also belong in the Grease command set.

The first live sample is `sensors.c`: enumerate Android sensors through the public native sensor boundary (`libandroid.so`) and print the list. The same program is carried on the Grease `android-sensors-live` line as the `sensors` command. A physical ARMv7 Android phone has executed the cross-built binary and returned its real sensor list.

This file is deliberately an oracle/sample, not evidence that Idriç currently lowers Android sensor calls. It is freestanding C that becomes ARMv7 Thumb-2 machine code and calls the phone's `libandroid.so`. Until an Idriç source equivalent is accepted by the backend, do not count this as an Idriç-generated backend receipt.

The intended sample progression is:

```text
sensors
    enumerate available sensors

read accelerometer
    wait for one fresh acceleration measurement and print it

watch accelerometer
    stream acceleration measurements
```

Those program meanings should stay stable while the machine-specific adapter varies. On Android the first implementation uses the native sensor service boundary; on ordinary Linux a later implementation may use IIO or another kernel interface.

For the ARM/Thumb backend, each sample should eventually have two distinct pieces of evidence:

1. semantic/device evidence that the target operation works on the real machine;
2. backend evidence that Idriç generated the claimed ARM/Thumb implementation for the exact source and backend revision.

Do not substitute the current C oracle, Termux:API, DEX/JNI, QEMU-only execution, or a host implementation for the second claim.

The current `sensors` oracle avoids libc for output only to keep the executable small; libc-free execution is not part of the program's semantics. The architectural boundary being tested is the Android sensor service reached through `libandroid`, not the absence of libc.

Grease counterpart: `isomorphisms/grease` PR #22 (`android-sensors-live`).
