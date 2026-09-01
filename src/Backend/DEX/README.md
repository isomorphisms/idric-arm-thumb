# Idriç → DEX backend

DEX is an Android Runtime target, not a processor ABI. This backend emits one
small DEX 035 application-code class directly and leaves ARMv7, AArch64, x86,
or x86-64 machine-code generation to ART.

The executable path is now:

```text
.idric source
  -> current declared Idriç parser, elaborator, and type checker
  -> Compiler.ANF
  -> Backend.DEX.IR method plan
  -> Backend.DEX.Encode
  -> classes.dex
```

`Backend.DEX.Smali` renders the same plan for review. The smali assembler is an
oracle and builds the external test runner only; it is not in the candidate
compiler path.

## Checked compiler handoff

The custom code generator uses `getCompileDataWith ["dex"] False ANF` from the
Idriç revision resolved from the declared `Idriç` branch. The first green
historical revision was `081b9cde0591154839fb5d80d76e5570e0436300`. It accepts only
functions selected by `%export "dex:<method_name>"` after elaboration.

The first source ABI is deliberately explicit:

- zero or more ordinary `Int32` parameters;
- an `Int32` result;
- no erased or implicit method parameters.

The lowerer consumes `Compiler.ANF`, not source text. It currently recognizes
checked Int32 constants, locals/lets, `Add Int32Type`, `Sub Int32Type`, and
`Mul Int32Type`. The currently tested compiler retains overloaded Int32 `<` as the
resolved checked name `Prelude.EqOrd.<`; the bridge lowers that exact checked
call and its Boolean 0/1 case form. Other named calls are rejected.

Compilation retains four adjacent evidence files for `-o classes`:

- `classes.checked.anf` — selected checked one-step definitions;
- `classes.dex.plan` — typed target plan;
- `classes.smali` — readable oracle rendering;
- `classes.dex` — direct production artifact.

The literal-only `add_constants` fixture is legitimately folded to `19` by the
current compiler. The parameterized checked `add` definition retains
`%op +Int32`; the ART harness calls it with 12 and 7 and checks 19.

## Implemented DEX subset

The typed target plan has integer constants, moves, add/subtract/multiply,
six two-register integer conditions, conditional branches, labels, `goto`, and
integer return. The direct encoder implements these concrete formats:

| Operation | DEX opcode / format |
| --- | --- |
| constant | `const/4` 11n, `const/16` 21s, `const` 31i |
| move | `move` 12x, `move/from16` 22x, `move/16` 32x |
| arithmetic | `add-int`, `sub-int`, `mul-int` 23x |
| comparison branch | `if-eq` through `if-le` 22t |
| jump | `goto` 10t |
| result | `return` 11x |

Format selection checks register and signed-literal ranges. Branch labels are
resolved in code units; zero and out-of-range 10t/22t offsets are rejected.
Parameters occupy the last virtual registers as required by DEX. There is no
physical CPU register allocator.

The file writer owns DEX magic/version, header, sorted string/type/prototype and
method identifiers, one class definition, type lists, code items, string data,
class data, map list, alignment, SHA-1 signature, and Adler-32 checksum. Output
is deterministic for a deterministic plan.

## Verification

Run:

```sh
make dex-test IDRIC=/path/to/Idric/build/exec/idris2
```

This checks the compiler revision, typechecks the backend, compiles the real
Idriç fixture, retains checked ANF and the plan, tests encoder boundaries and
malformed plans, rejects a 64-bit `Int` export, regenerates deterministically,
checks the DEX header and hashes independently, disassembles with pinned
baksmali, and compares that disassembly with the smali-oracle artifact.

`make dex-device` additionally uses a connected Android device or emulator. It
loads the directly encoded candidate beside a separately assembled test runner
and invokes it with Android's `app_process`. Absence of a device is reported as
`SKIP` with exit status 2. CI provides a bounded API-29 x86-64 emulator
job; it does not require a permanently attached phone.

See [`AUDIT.md`](./AUDIT.md) for the starting boundary and
[`OPCODES.md`](./OPCODES.md) for the complete opcode inventory.

## Explicitly unsupported

The first slice does not claim general calls, recursion, constructors, objects,
arrays, fields, strings, exceptions, monitors, annotations, debug data, wide
64-bit values, floats, Float16, Android framework calls, lifecycle classes,
resources, APK packaging, signing, or source-level IO. Unsupported ANF and DEX
plans fail; there is no RefC, Java, Chez, ARM Thumb, smali, or d8 fallback.

APK/UI machinery is intentionally outside the semantic backend. A framework
call or other Android-facing extension should be added only with a concrete
checked Idriç fixture that requires it.
