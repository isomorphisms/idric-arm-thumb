# Idriç ARM/Thumb backend

Direct ARMv7 Thumb-2/VFP backend for Idriç, without routing numerical leaves through C.

The first slice is deliberately small. It compiles an exported, closure-free function whose arguments and result are `RendererPrimitives.Float32` and whose body is made from local copies, Float32 addition, and Float32 multiplication.

```text
.idric source
  -> current Idriç parser/typechecker/erasure
  -> Compiler.ANF
  -> validated runtime-free leaf IR
  -> deterministic Thumb-2/VFP .S
  -> ELF32 ARM object
```

The proof fixture is `examples/Affine.idric`:

```idris
%export "arm-thumb:evaluate_affine"
evaluate_affine : Float32 -> Float32 -> Float32 -> Float32
evaluate_affine a x b =
  float32_add (float32_multiply a x) b
```

The backend is pinned to Idriç commit:

```text
081b9cde0591154839fb5d80d76e5570e0436300
```

That compiler deliberately remains implemented on the current Idris 2 internals, so this backend uses its existing `Compiler.ANF` custom-codegen seam instead of creating a second competing Idriç IR.

## Target ABI

- Android `armeabi-v7a`
- ARMv7-A, Thumb-2
- VFPv3-D16 scalar Float32 arithmetic
- softfp C boundary: up to four Float32 words enter through `r0`-`r3`; the Float32 result leaves as raw bits in `r0`
- 8-byte-aligned stack frame
- no heap, GC, closures, or Idris runtime in the emitted numerical leaf

## Build and verify

Build the pinned Idriç compiler and install its compiler API/libraries, then run:

```sh
make verify IDRIC=/path/to/Idric/build/exec/idris2
```

`make verify` checks the compiler revision, typechecks and builds the custom driver, compiles the real `.idric` affine fixture through `--cg arm-thumb`, requires `vmul.f32` and `vadd.f32` in the generated assembly, assembles it with Clang for `armv7a-linux-androideabi21`, and checks that the result is an ELF32 ARM object.

GitHub Actions performs that path from a clean checkout by bootstrapping the exact pinned Idriç revision first.

## Current boundary

Accepted now:

- one exported runtime-free function at a time or multiple independent exports
- zero to four explicit `Float32` arguments
- `Float32` result
- local copies
- `float32_add`
- `float32_multiply`

Rejected now:

- integers and Float32 constants
- buffers and loads
- subtract/divide/negate/abs/sqrt
- branches and comparisons
- recursion or general calls
- constructors, closures, allocation, strings, IO, JNI, or Android lifecycle code

The older `idris-arm-backend` remains useful reference code for the broader arithmetic/buffer subset. This repository is the Idriç-specific line and advances only when the current Idriç compiler accepts and verifies the slice.

## Next slice

After this affine path is green: bring back the remaining proven Float32 operations and caller-owned `Float32Buffer` loads, then add comparisons and a constrained tail loop for Horner evaluation.
