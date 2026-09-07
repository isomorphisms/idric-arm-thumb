# Copied, adapted, generated, and third-party material

This audit supports F-Droid/source-distribution review. It records what can be established from repository contents and history without inferring copyright ownership from a Git identity.

The root `LICENSE` is the repository's explicit GPL-3.0-or-later choice for original copyrightable material that contributors have authority to license. The same text was introduced on `feature/dex-nativeactivity-jni` by commit `2f60f0cb995cfc1e2effe09ec1afe93a2d541da2` with commit message `License: mark backend as GPL-3.0-or-later`; this branch carries that already-made repository-local choice into the DEX integration line rather than choosing a new license.

Audit base for the direct DEX integration: `efd912b7e1cf74340f683913eaec693e262f7b05` (`integration/dex-follow-current-idric`). Downstream `feature/dex-nativeactivity-jni` at `0b124173872627d222aa81e1fb7e55eeada83ca5` was also inspected for F-Droid-relevant additions.

## Copied/adapted source: older ARM backend

The current ARM/Thumb backend is not merely inspired by `isomorphisms/idris-arm-backend`; it contains substantial ported/adapted source from that repository. Direct comparison shows extensive line-for-line or near-line-for-line continuity in at least:

- `src/Backend/ARMThumb/Codegen.idr` from `idris-arm-backend/src/Backend/ARMv7/Codegen.idr`
- `src/Backend/ARMThumb/IR.idr` from `idris-arm-backend/src/Backend/ARMv7/IR.idr`
- `src/Backend/ARMThumb/Emit.idr` from `idris-arm-backend/src/Backend/ARMv7/Emit.idr`
- `src/Backend/ARMThumb/Lower.idr` from `idris-arm-backend/src/Backend/ARMv7/Lower.idr`
- `src/Backend/ARMThumb/Main.idr` from `idris-arm-backend/src/Backend/ARMv7/Main.idr`
- `src/RendererPrimitives.idr` from `idris-arm-backend/src/RendererPrimitives.idr`

Repository history reinforces that classification: commit `59f3c3392e916145c9aeb46d72ccdbbae6a8874f` is titled `Port typed Float32 and buffer lowering`.

The audited `main` tree of `isomorphisms/idris-arm-backend` contains no `LICENSE`, `COPYING`, or other explicit repository-wide license file. Therefore this audit does **not** infer permission to relicense that older material from matching account/commit identities.

`src/Backend/DEX/Codegen.idr` also retains substantial structural and textual continuity with `ARMThumb/Codegen.idr` in its compiler handoff: export ABI parsing, checked-ANF lookup, export validation, fully-qualified export resolution, codegen entry/exit structure, and `MkCG` registration. Conservatively, the unresolved older-ARM provenance therefore reaches the DEX codegen glue as well, even though the DEX IR/lowering/encoder itself was added later.

**Unresolved holder action:** before treating this copied/adapted family as cleared for F-Droid, a copyright holder or otherwise authorized party must do one of the following:

1. confirm that the relevant older `idris-arm-backend` material and its adaptations may be licensed GPL-3.0-or-later; or
2. identify the older material's actual pre-existing license/permission; or
3. replace the affected copied/adapted material with independently written code.

This file deliberately does not choose among those holder actions.

## Direct DEX implementation and AOSP specifications

The direct DEX implementation under `src/Backend/DEX/` was introduced in this repository as checked Idriç-to-DEX work. `src/Backend/DEX/OPCODES.md` explicitly identifies the Android Open Source Project Dalvik bytecode, instruction-format, and DEX-format documentation as its primary specification references.

Specification/reference use is recorded here so it is not mistaken for a claim that AOSP material has been relicensed under this repository's GPL. No AOSP source-code tree or Android platform binary is vendored in the audited repository tree.

## smali/baksmali test tooling

The Makefile downloads pinned `smali` and `baksmali` 3.0.10 release JARs during tests and verifies their SHA-256 hashes. Those JARs are **not checked into this repository** and are not the production DEX encoder.

Upstream `baksmali/smali` carries its own license file: most smali/baksmali code is under BSD-style redistribution terms, with separately identified Google contributions and AOSP/Guava portions under their upstream terms, including Apache-2.0 material. Nothing in this repository's GPL grant relicenses those downloaded tools.

The production candidate remains the DEX bytes written directly by the Idriç backend. Smali/baksmali is used only as an independent test/disassembly/oracle tool.

## Checked-in smali fixtures

The audited integration tree contains small `.smali` test fixtures, not a vendored smali implementation:

- `tests/dex/oracles/AddInts.smali` is described by the repository's DEX audit as a handwritten/bootstrap oracle and was introduced by commit `80dcd497a178f4a5c060905eb41b748510286167` (`Add first DEX smali oracle`).
- `tests/dex/runtime/IdricRunner.smali` describes itself as a runtime harness external to the *candidate backend*; its history introduces it with the direct DEX implementation rather than identifying an external source. Here, `external` means outside the candidate under test, not proven third-party provenance.

Downstream `feature/dex-nativeactivity-jni` adds `tests/dex/oracles/WegertActivity.smali` as another small readable oracle. No file notice or checked history for these fixtures identifies an upstream copied source. This audit therefore finds no mechanically supported basis to classify them as vendored third-party code; the root license still applies only where contributors actually have licensing authority.

## External compiler, Android and CI inputs

Idriç/Idris compiler sources and libraries, Android SDK/NDK/build-tools/platform components, Clang, ART/emulator images, Java used to run the test-only smali tools, and GitHub Actions are external build/test/runtime inputs. They are not copied into the audited repository as source trees and retain their own licenses.

## Generated artifacts

DEX/APK/shared-library outputs and validation receipts are build artifacts, not checked-in source in the audited integration/downstream trees. In particular, the repository tree contains no vendored `.jar`, `.dex`, `.apk`, or `.so` payload that would need a copied-binary license notice.

The direct production path writes `classes.dex` from the checked Idriç backend and packages the exact candidate DEX where the Android acceptance path requires an APK. Test-only smali assembly/disassembly does not become a fallback production compiler.

The repository's source license does not purport to relicense external compiler/toolchain/platform material merely because those tools participate in producing or executing an artifact.

## Audit conclusion

No vendored third-party source tree or binary dependency was found in the audited direct-DEX repository tree. The material licensing issue that remains is narrower and more important: verified copied/adapted source from the older, presently unlicensed `idris-arm-backend` lineage, including ancestry that reaches DEX `Codegen.idr`. That is the only identified blocker in this audit that requires a genuine copyright-holder/permission decision rather than another mechanical repository change.
