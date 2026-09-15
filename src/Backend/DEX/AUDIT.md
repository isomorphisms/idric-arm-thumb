# DEX backend audit

Audit base: branch `dex-backend`, revision `2e1f194`.

## What existed

- `src/Backend/DEX/README.md`, `OPCODES.md`, and
  `PSEUDO_REGISTER_IR.md` were design notes and an opcode inventory.
- `tests/dex/oracles/AddInts.smali` was a handwritten illustrative fixture.
- There was no Idris/Idriç DEX module, code-generator registration, lowering,
  binary encoder, generated `classes.dex`, DEX test target, or DEX CI job.
- The Makefile, package, executable main, source fixtures, and CI exercised the
  direct ARM Thumb backend only.
- The repository did not invoke smali, baksmali, d8, dexdump, adb, ART, or an
  Android packager. No path called a DEX compiler was executable, so there was
  no source recognizer, textual mock, oracle substitution, or hidden fallback
  to distinguish from a real DEX path.

The handwritten smali file therefore proved only that a proposed instruction
sequence was expressible in smali. It did not prove that checked Idriç produced
that sequence or that the repository produced or executed DEX.

## Genuine compiler input available

The repository pins Idriç compiler revision
`081b9cde0591154839fb5d80d76e5570e0436300`. Its supported custom-codegen seam
can provide `Compiler.ANF` after normal parsing, elaboration/type checking,
export selection, and compiler lowering. The ARM backend already used that
seam. That checked ANF is sufficient for the ordinary Int32 slice; no parser or
source-pattern bridge belongs in the DEX repository.

The missing boundary was: register a `dex` code generator, validate exported
source ABI types, select the checked ANF definitions, lower them into a small
target plan, encode the required DEX class/method structures, validate with an
independent implementation, and invoke the artifact on ART.

## Implemented boundary

`Backend.DEX.Codegen` now owns the compiler handoff and evidence files;
`Backend.DEX.Lower` maps checked ANF temporaries deterministically to DEX virtual
registers; `Backend.DEX.IR` is a small typed target plan; and
`Backend.DEX.Encode` emits DEX 035 directly. Smali/baksmali remain pinned test
oracles. The external smali runtime harness calls methods in the candidate DEX
and never substitutes an oracle-built candidate.

Issue `isomorphisms/ai-ci#41` asks that DEX versus direct CPU lowering remain an
experiment. This implementation preserves that separation: ANF owns checked
meaning, while DEX instruction and file-format decisions remain target-local.
