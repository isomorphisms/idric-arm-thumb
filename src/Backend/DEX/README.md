# Idriç → DEX backend

This backend lives beside `Backend.ARMThumb`, but it is deliberately a different
kind of target.

- `ARMThumb` emits processor instructions directly.
- `DEX` emits Android Runtime bytecode. ART is responsible for the eventual
  ARMv7, ARM64, x86, or x86-64 machine code.

The immediate goal is therefore **one Android application-code target without
per-ABI native libraries**. APK/AAB packaging, resources, manifest handling, and
signing remain separate layers around `classes.dex`.

## First slice

Keep the bootstrap small and inspectable:

```text
checked Idriç / ANF
        ↓
DEX lowering
        ↓
smali text
        ↓
smali assembler (oracle/bootstrap only)
        ↓
classes.dex
```

After the lowering is stable, replace the smali assembler with a direct binary
DEX encoder while keeping the smali rendering as a readable oracle.

First semantic fixture:

```text
a ← 12
b ← 7
c ← a + b
return c
```

Expected DEX-shaped lowering:

```smali
const/16 v0, 12
const/16 v1, 7
add-int  v2, v0, v1
return   v2
```

The first executable acceptance test should load the generated class/method in
an Android/Dalvik-compatible runtime and verify the returned integer. Do not
claim Android application acceptance merely because smali assembles.

## Initial instruction surface

Start with the small register-machine core:

- `const`
- `move`
- `add-int`, `sub-int`, `mul-int`
- integer comparison + `if-*`
- `goto`
- `return`

Then add calls, objects, fields, and arrays only when an Android application
fixture requires them.

## Numeric boundary

DEX arithmetic directly provides 32-bit integer/float operations and 64-bit
wide operations. It has no Float16 arithmetic opcode. Preserve Idriç's explicit
numeric-resolution boundary rather than silently treating `Float16` as
`Float32`.

A later Float16 design must choose explicitly among:

1. a 16-bit stored representation with Float32 arithmetic plus checked rounding,
2. software half arithmetic, or
3. a native/GPU backend for operations that genuinely require half arithmetic.

## Android boundary

Generating DEX does **not** mean generating Java source. The backend may emit
DEX classes and methods directly, including calls into Android framework
classes. The surrounding Android package still needs at least a manifest,
resources as applicable, APK/AAB construction, and signing.

## Repository placement

Keep this backend here beside the direct CPU backend:

```text
src/Backend/
  ARMThumb/
  DEX/
```

Conceptually, however, label DEX a **runtime/VM backend**, not a processor ABI.
That distinction matters whenever we discuss native ABI rules, Float16, raw
memory layout, or instruction-level behavior.
