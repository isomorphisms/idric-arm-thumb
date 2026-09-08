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
