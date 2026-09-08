# Idriç DEX backend

Direct Android Runtime DEX backend for Idriç.

This development line is a sibling of the ARM/Thumb backend. Both consume checked compiler forms, but DEX lowering, encoding, packaging, and acceptance are independent of ARM instruction selection and execution.

DEX is ART's class-and-method executable format. Direct DEX output may use
classes, inheritance, constructors, Android framework methods, and native
method declarations when the program or Android entry boundary needs them.
The constraint here is that Idriç writes those DEX structures directly: Java
source, `javac`, Kotlin, Gradle, and `d8` are not intermediate compiler stages.

The DEX executable registers only the `dex` code generator. Its acceptance path produces `classes.dex`, validates it independently, and executes it on ART. ARM source modules, ARM emulation, and QEMU are not part of the DEX build or correctness receipt.

The generic compiler package contains only the checked-ANF DEX backend. A
separate `wegert-dex.ipkg` package contains the current direct-DEX
NativeActivity/JNI adapter used to exercise an Android application boundary.
That adapter is DEX/Android work, but it is not presented as generic Idriç
lowering.

See `src/Backend/DEX/README.md` and `tests/dex/README.md` for the current executable slice and evidence layers.

## Licensing and provenance

The repository license is GPL-3.0-or-later where contributors have authority
to grant it. [`THIRD_PARTY.md`](THIRD_PARTY.md) records external tools and one
unresolved copied-source issue in the DEX compiler-handoff glue. Independent
Git ancestry from ARM fixes the backend architecture; it does not by itself
erase copied-text provenance.
