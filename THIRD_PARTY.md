# Copied, adapted, generated, and third-party material

This records the source and tool boundaries relevant to the direct DEX line.
The root `LICENSE` applies to original material only where contributors have
authority to grant GPL-3.0-or-later permission.

## DEX compiler handoff provenance

The DEX IR, lowering, binary encoder, hashing, and validation code were added
as direct DEX work. `src/Backend/DEX/Codegen.idr`, however, retains substantial
structural and textual continuity with compiler-handoff code previously ported
through the ARM backend family: export ABI parsing, checked-ANF lookup, export
validation, fully qualified export resolution, and `MkCG` registration.

The older `isomorphisms/idris-arm-backend` repository from which that handoff
structure was adapted has no explicit repository-wide license in its audited
`main` tree. Moving DEX onto independent Git ancestry does not settle the
copyright provenance of copied text.

Before F-Droid or another source distribution treats that code as cleared, an
authorized copyright holder must do one of the following:

1. confirm that the relevant older material and adaptations may be licensed
   GPL-3.0-or-later;
2. identify the older material's existing license or permission; or
3. replace the affected DEX compiler-handoff code independently.

This record does not choose among those actions and does not infer permission
from matching Git account identities.

## DEX and Android specifications

`src/Backend/DEX/OPCODES.md` identifies Android Open Source Project Dalvik
bytecode, instruction-format, and DEX-format documentation as primary
specification references. No AOSP source tree or Android platform binary is
vendored here. Specification use is not a claim that AOSP material is
relicensed under this repository's license.

## Smali and Baksmali

Tests download pinned Smali and Baksmali 3.0.10 release JARs and verify their
SHA-256 hashes. They are not checked into the repository and do not produce the
candidate DEX. They retain their upstream licenses.

The checked-in `.smali` files are small test fixtures:

- `tests/dex/oracles/AddInts.smali` is a handwritten oracle;
- `tests/dex/runtime/IdricRunner.smali` is an ART test harness outside the
  candidate;
- `tests/dex/oracles/WegertActivity.smali` is the readable oracle for the
  direct Wegert activity encoder.

No checked history identifies these fixtures as vendored third-party source.

## External build and runtime inputs

The Idriç compiler, Android SDK/NDK/build tools and platform files, Clang,
ART/emulator images, Java used to run test-only Smali tools, and GitHub Actions
are external inputs. They are not copied into this repository as source trees
and retain their own licenses.

## Generated artifacts

DEX, APK, shared-library outputs, and receipts are generated artifacts, not
checked-in source. The repository contains no vendored `.jar`, `.dex`, `.apk`,
or `.so` candidate. The production `classes.dex` bytes are written directly by
the Idriç DEX code; test-only Smali assembly remains outside that path.
