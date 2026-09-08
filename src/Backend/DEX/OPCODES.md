# Complete DEX opcode inventory for the Edriç backend

This file is deliberately exhaustive before we implement more lowering. It accounts for every
8-bit DEX opcode slot `0x00`–`0xff`, including currently unused slots, and the three
data-bearing pseudo-instruction payload formats.

Primary references:

- Android Open Source Project, **Dalvik bytecode format**: https://source.android.com/docs/core/runtime/dalvik-bytecode
- Android Open Source Project, **Dalvik executable instruction formats**: https://source.android.com/docs/core/runtime/instruction-formats
- Android Open Source Project, **Dalvik executable format**: https://source.android.com/docs/core/runtime/dex-format

The public table currently defines 224 opcode slots and leaves 32 unused. DEX 038 added
`invoke-polymorphic` / `invoke-custom`; DEX 039 added `const-method-handle` /
`const-method-type`. DEX 040 changes file-format naming rules rather than adding bytecodes.
DEX 041 is an experimental Android 16 container format and is not a production target.

For the first Edriç Android backend, **DEX 035 is the conservative baseline**. It is enough for
the ordinary arithmetic, branch, array, object, field, and call instructions we need, and it
avoids making a newer runtime feature part of the language by accident.

## What the status column means

- **core** — directly useful for checked straight-line/control-flow lowering.
- **android-bridge** — likely required to call Android framework code or represent DEX references; keep it below the Edriç surface.
- **explicit-64** — only when an explicit 64-bit value or framework signature requires it.
- **late** — meaningful only after the corresponding Edriç semantics are specified.
- **avoid-unless-required** — historical/runtime machinery we should not import into the language without a concrete need.
- **unused** — reserved opcode slot; the encoder must reject it as an instruction.

These statuses are planning labels, not claims that an opcode itself is good or bad.

## Full 256-slot map

| op | mnemonic | format | family | status | Edriç/backend note |
|---:|---|---|---|---|---|
| `0x00` | `nop` | `10x` | control/layout | **core** | No semantic effect; also tags payload pseudo-instructions. |
| `0x01` | `move` | `12x` | register move | **core** | 32-bit non-reference move; encoding choice depends on register numbers. |
| `0x02` | `move/from16` | `22x` | register move | **core** | Same semantic move, larger source register. |
| `0x03` | `move/16` | `32x` | register move | **core** | Same semantic move, large source and destination registers. |
| `0x04` | `move-wide` | `12x` | register move | **explicit-64** | 64-bit pair move; only for explicit 64-bit values/interoperability. |
| `0x05` | `move-wide/from16` | `22x` | register move | **explicit-64** | 64-bit pair move with larger source register. |
| `0x06` | `move-wide/16` | `32x` | register move | **explicit-64** | 64-bit pair move with large register numbers. |
| `0x07` | `move-object` | `12x` | reference move | **android-bridge** | Reference move; backend detail, not an Edriç object model. |
| `0x08` | `move-object/from16` | `22x` | reference move | **android-bridge** | Reference move with larger source register. |
| `0x09` | `move-object/16` | `32x` | reference move | **android-bridge** | Reference move with large register numbers. |
| `0x0a` | `move-result` | `11x` | call result | **android-bridge** | Must immediately follow an invocation that returns a 32-bit non-reference value. |
| `0x0b` | `move-result-wide` | `11x` | call result | **explicit-64** | Immediate 64-bit invocation result transfer. |
| `0x0c` | `move-result-object` | `11x` | call result | **android-bridge** | Immediate reference result transfer after invoke/filled-new-array. |
| `0x0d` | `move-exception` | `11x` | exception | **late** | Handler-entry instruction; only relevant once Edriç exception semantics are explicit. |
| `0x0e` | `return-void` | `10x` | return | **core** | Return with no value. |
| `0x0f` | `return` | `11x` | return | **core** | Return a 32-bit non-reference value. |
| `0x10` | `return-wide` | `11x` | return | **explicit-64** | Return a 64-bit pair. |
| `0x11` | `return-object` | `11x` | return | **android-bridge** | Return a reference. |
| `0x12` | `const/4` | `11n` | constant | **core** | Small signed literal; encoding optimization only. |
| `0x13` | `const/16` | `21s` | constant | **core** | 16-bit signed literal widened to 32 bits. |
| `0x14` | `const` | `31i` | constant | **core** | Arbitrary 32-bit bit pattern. |
| `0x15` | `const/high16` | `21h` | constant | **core** | 32-bit literal with low 16 bits zero; encoding optimization. |
| `0x16` | `const-wide/16` | `21s` | constant | **explicit-64** | Small literal widened to 64 bits. |
| `0x17` | `const-wide/32` | `31i` | constant | **explicit-64** | 32-bit literal widened to 64 bits. |
| `0x18` | `const-wide` | `51l` | constant | **explicit-64** | Arbitrary 64-bit bit pattern. |
| `0x19` | `const-wide/high16` | `21h` | constant | **explicit-64** | 64-bit literal with only high 16 bits encoded. |
| `0x1a` | `const-string` | `21c` | constant pool | **android-bridge** | Load a string-pool reference. |
| `0x1b` | `const-string/jumbo` | `31c` | constant pool | **android-bridge** | Same semantics with 32-bit string index. |
| `0x1c` | `const-class` | `21c` | constant pool | **android-bridge** | Load a type/class reference; keep below Edriç surface. |
| `0x1d` | `monitor-enter` | `11x` | monitor | **avoid-unless-required** | Java/ART monitor acquisition; do not infer Edriç concurrency semantics from it. |
| `0x1e` | `monitor-exit` | `11x` | monitor | **avoid-unless-required** | Java/ART monitor release. |
| `0x1f` | `check-cast` | `21c` | runtime type | **avoid-unless-required** | Runtime reference cast check; not a model for Edriç typechecking. |
| `0x20` | `instance-of` | `22c` | runtime type | **avoid-unless-required** | Runtime reference-class query. |
| `0x21` | `array-length` | `12x` | array | **android-bridge** | Array length; useful for framework interop and an eventual array representation. |
| `0x22` | `new-instance` | `21c` | allocation | **android-bridge** | Allocate framework/class instance; backend-only Android bridge. |
| `0x23` | `new-array` | `22c` | allocation | **android-bridge** | Allocate a DEX array. |
| `0x24` | `filled-new-array` | `35c` | allocation | **android-bridge** | Allocate/fill a small single-word-element array. |
| `0x25` | `filled-new-array/range` | `3rc` | allocation | **android-bridge** | Range-register form of filled-new-array. |
| `0x26` | `fill-array-data` | `31t` | array payload | **android-bridge** | Initialize primitive array from an aligned payload. |
| `0x27` | `throw` | `11x` | exception | **late** | Needs explicit Edriç exception/effect semantics before source lowering. |
| `0x28` | `goto` | `10t` | branch | **core** | Unconditional short branch. |
| `0x29` | `goto/16` | `20t` | branch | **core** | Same branch with wider offset. |
| `0x2a` | `goto/32` | `30t` | branch | **core** | Same branch with 32-bit offset. |
| `0x2b` | `packed-switch` | `31t` | multiway branch | **core** | Dense integer dispatch via payload table. |
| `0x2c` | `sparse-switch` | `31t` | multiway branch | **core** | Sparse integer dispatch via key/target payload. |
| `0x2d` | `cmpl-float` | `23x` | comparison | **core** | Float comparison produces -1/0/1; l/g variants choose opposite NaN bias. |
| `0x2e` | `cmpg-float` | `23x` | comparison | **core** | Float comparison produces -1/0/1; l/g variants choose opposite NaN bias. |
| `0x2f` | `cmpl-double` | `23x` | comparison | **avoid-unless-required** | Float64 comparison; retain only for explicit interop/precision. |
| `0x30` | `cmpg-double` | `23x` | comparison | **avoid-unless-required** | Float64 comparison; retain only for explicit interop/precision. |
| `0x31` | `cmp-long` | `23x` | comparison | **explicit-64** | 64-bit signed comparison produces -1/0/1. |
| `0x32` | `if-eq` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x33` | `if-ne` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x34` | `if-lt` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x35` | `if-ge` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x36` | `if-gt` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x37` | `if-le` | `22t` | conditional branch | **core** | Compare two low-numbered registers and branch; no exposed CPU flags/predication. |
| `0x38` | `if-eqz` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x39` | `if-nez` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x3a` | `if-ltz` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x3b` | `if-gez` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x3c` | `if-gtz` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x3d` | `if-lez` | `21t` | conditional branch | **core** | Compare one register with zero/null and branch. |
| `0x3e` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x3f` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x40` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x41` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x42` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x43` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the current public bytecode table. |
| `0x44` | `aget` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x45` | `aget-wide` | `23x` | array access | **explicit-64** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x46` | `aget-object` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x47` | `aget-boolean` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x48` | `aget-byte` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x49` | `aget-char` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4a` | `aget-short` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4b` | `aput` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4c` | `aput-wide` | `23x` | array access | **explicit-64** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4d` | `aput-object` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4e` | `aput-boolean` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x4f` | `aput-byte` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x50` | `aput-char` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x51` | `aput-short` | `23x` | array access | **android-bridge** | Typed DEX array load/store; treat the type suffix as target representation, not source-language meaning. |
| `0x52` | `iget` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x53` | `iget-wide` | `22c` | instance field | **explicit-64** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x54` | `iget-object` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x55` | `iget-boolean` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x56` | `iget-byte` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x57` | `iget-char` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x58` | `iget-short` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x59` | `iput` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5a` | `iput-wide` | `22c` | instance field | **explicit-64** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5b` | `iput-object` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5c` | `iput-boolean` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5d` | `iput-byte` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5e` | `iput-char` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x5f` | `iput-short` | `22c` | instance field | **android-bridge** | Framework/DEX field access; keep class-field mechanics below Edriç surface. |
| `0x60` | `sget` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x61` | `sget-wide` | `21c` | static field | **explicit-64** | Framework/DEX static field access; interoperability machinery. |
| `0x62` | `sget-object` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x63` | `sget-boolean` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x64` | `sget-byte` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x65` | `sget-char` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x66` | `sget-short` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x67` | `sput` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x68` | `sput-wide` | `21c` | static field | **explicit-64** | Framework/DEX static field access; interoperability machinery. |
| `0x69` | `sput-object` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x6a` | `sput-boolean` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x6b` | `sput-byte` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x6c` | `sput-char` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x6d` | `sput-short` | `21c` | static field | **android-bridge** | Framework/DEX static field access; interoperability machinery. |
| `0x6e` | `invoke-virtual` | `35c` | call | **android-bridge** | DEX dispatch flavor required by callee metadata; should not determine Edriç call semantics. |
| `0x6f` | `invoke-super` | `35c` | call | **android-bridge** | DEX dispatch flavor required by callee metadata; should not determine Edriç call semantics. |
| `0x70` | `invoke-direct` | `35c` | call | **android-bridge** | DEX dispatch flavor required by callee metadata; should not determine Edriç call semantics. |
| `0x71` | `invoke-static` | `35c` | call | **android-bridge** | DEX dispatch flavor required by callee metadata; should not determine Edriç call semantics. |
| `0x72` | `invoke-interface` | `35c` | call | **android-bridge** | DEX dispatch flavor required by callee metadata; should not determine Edriç call semantics. |
| `0x73` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot. |
| `0x74` | `invoke-virtual/range` | `3rc` | call | **android-bridge** | Range-register encoding of the corresponding invocation. |
| `0x75` | `invoke-super/range` | `3rc` | call | **android-bridge** | Range-register encoding of the corresponding invocation. |
| `0x76` | `invoke-direct/range` | `3rc` | call | **android-bridge** | Range-register encoding of the corresponding invocation. |
| `0x77` | `invoke-static/range` | `3rc` | call | **android-bridge** | Range-register encoding of the corresponding invocation. |
| `0x78` | `invoke-interface/range` | `3rc` | call | **android-bridge** | Range-register encoding of the corresponding invocation. |
| `0x79` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot. |
| `0x7a` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot. |
| `0x7b` | `neg-int` | `12x` | unary/conversion | **core** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x7c` | `not-int` | `12x` | unary/conversion | **core** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x7d` | `neg-long` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x7e` | `not-long` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x7f` | `neg-float` | `12x` | unary/conversion | **core** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x80` | `neg-double` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x81` | `int-to-long` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x82` | `int-to-float` | `12x` | unary/conversion | **core** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x83` | `int-to-double` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x84` | `long-to-int` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x85` | `long-to-float` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x86` | `long-to-double` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x87` | `float-to-int` | `12x` | unary/conversion | **core** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x88` | `float-to-long` | `12x` | unary/conversion | **explicit-64** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x89` | `float-to-double` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8a` | `double-to-int` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8b` | `double-to-long` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8c` | `double-to-float` | `12x` | unary/conversion | **avoid-unless-required** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8d` | `int-to-byte` | `12x` | unary/conversion | **android-bridge** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8e` | `int-to-char` | `12x` | unary/conversion | **android-bridge** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x8f` | `int-to-short` | `12x` | unary/conversion | **android-bridge** | Explicit numeric/bit conversion; source typing must decide when this is legal. |
| `0x90` | `add-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x91` | `sub-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x92` | `mul-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x93` | `div-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x94` | `rem-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x95` | `and-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x96` | `or-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x97` | `xor-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x98` | `shl-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x99` | `shr-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9a` | `ushr-int` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9b` | `add-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9c` | `sub-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9d` | `mul-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9e` | `div-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0x9f` | `rem-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa0` | `and-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa1` | `or-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa2` | `xor-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa3` | `shl-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa4` | `shr-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa5` | `ushr-long` | `23x` | binary arithmetic/bit op | **explicit-64** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa6` | `add-float` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa7` | `sub-float` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa8` | `mul-float` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xa9` | `div-float` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xaa` | `rem-float` | `23x` | binary arithmetic/bit op | **core** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xab` | `add-double` | `23x` | binary arithmetic/bit op | **avoid-unless-required** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xac` | `sub-double` | `23x` | binary arithmetic/bit op | **avoid-unless-required** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xad` | `mul-double` | `23x` | binary arithmetic/bit op | **avoid-unless-required** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xae` | `div-double` | `23x` | binary arithmetic/bit op | **avoid-unless-required** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xaf` | `rem-double` | `23x` | binary arithmetic/bit op | **avoid-unless-required** | Three-register form; exact integer and IEEE-754 behavior must be reflected in checked lowering. |
| `0xb0` | `add-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb1` | `sub-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb2` | `mul-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb3` | `div-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb4` | `rem-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb5` | `and-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb6` | `or-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb7` | `xor-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb8` | `shl-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xb9` | `shr-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xba` | `ushr-int/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xbb` | `add-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xbc` | `sub-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xbd` | `mul-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xbe` | `div-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xbf` | `rem-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc0` | `and-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc1` | `or-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc2` | `xor-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc3` | `shl-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc4` | `shr-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc5` | `ushr-long/2addr` | `12x` | binary arithmetic/bit op | **explicit-64** | Two-address encoding; same operation, destination is also first source. |
| `0xc6` | `add-float/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xc7` | `sub-float/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xc8` | `mul-float/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xc9` | `div-float/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xca` | `rem-float/2addr` | `12x` | binary arithmetic/bit op | **core** | Two-address encoding; same operation, destination is also first source. |
| `0xcb` | `add-double/2addr` | `12x` | binary arithmetic/bit op | **avoid-unless-required** | Two-address encoding; same operation, destination is also first source. |
| `0xcc` | `sub-double/2addr` | `12x` | binary arithmetic/bit op | **avoid-unless-required** | Two-address encoding; same operation, destination is also first source. |
| `0xcd` | `mul-double/2addr` | `12x` | binary arithmetic/bit op | **avoid-unless-required** | Two-address encoding; same operation, destination is also first source. |
| `0xce` | `div-double/2addr` | `12x` | binary arithmetic/bit op | **avoid-unless-required** | Two-address encoding; same operation, destination is also first source. |
| `0xcf` | `rem-double/2addr` | `12x` | binary arithmetic/bit op | **avoid-unless-required** | Two-address encoding; same operation, destination is also first source. |
| `0xd0` | `add-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd1` | `rsub-int` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd2` | `mul-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd3` | `div-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd4` | `rem-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd5` | `and-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd6` | `or-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd7` | `xor-int/lit16` | `22s` | integer literal op | **core** | Integer operation with 16-bit literal; mostly an encoding-selection concern. |
| `0xd8` | `add-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xd9` | `rsub-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xda` | `mul-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xdb` | `div-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xdc` | `rem-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xdd` | `and-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xde` | `or-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xdf` | `xor-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xe0` | `shl-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xe1` | `shr-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xe2` | `ushr-int/lit8` | `22b` | integer literal op | **core** | Integer operation with 8-bit literal; mostly an encoding-selection concern. |
| `0xe3` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe4` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe5` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe6` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe7` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe8` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xe9` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xea` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xeb` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xec` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xed` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xee` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xef` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf0` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf1` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf2` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf3` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf4` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf5` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf6` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf7` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf8` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xf9` | `(unused)` | `10x` | unused | **unused** | Reserved/unused opcode slot in the public instruction set. |
| `0xfa` | `invoke-polymorphic` | `45cc` | dynamic call | **avoid-unless-required** | DEX 038+ method-handle invocation; not needed for ordinary direct Android calls. |
| `0xfb` | `invoke-polymorphic/range` | `4rcc` | dynamic call | **avoid-unless-required** | Range form of method-handle invocation. |
| `0xfc` | `invoke-custom` | `35c` | dynamic call | **avoid-unless-required** | DEX 038+ call-site/bootstrap mechanism; do not import into Edriç unless demanded. |
| `0xfd` | `invoke-custom/range` | `3rc` | dynamic call | **avoid-unless-required** | Range form of custom call-site invocation. |
| `0xfe` | `const-method-handle` | `21c` | dynamic call constant | **avoid-unless-required** | DEX 039+ method-handle constant. |
| `0xff` | `const-method-type` | `21c` | dynamic call constant | **avoid-unless-required** | DEX 039+ method-prototype constant. |

## Payload pseudo-instructions

These are data records carried in the instruction stream under the `nop` opcode family. They
are not ordinary control-flow instructions and must be 4-byte aligned.

| ident | name | referred to by | backend obligation |
|---:|---|---|---|
| `0x0100` | `packed-switch-payload` | `packed-switch` | Emit first key plus target offsets; targets are relative to the switch instruction. |
| `0x0200` | `sparse-switch-payload` | `sparse-switch` | Emit sorted keys plus corresponding target offsets. |
| `0x0300` | `fill-array-data-payload` | `fill-array-data` | Emit element width, element count, and raw primitive data; pad/alignment as required. |

## Branch/control-flow pass

This is the part worth comparing directly with ARM Thumb rather than assuming the DEX model
is the meaning of branching.

DEX exposes a deliberately small control-flow surface:

- unconditional branch: `goto`, `goto/16`, `goto/32`;
- two-register conditional branch: `if-eq`, `if-ne`, `if-lt`, `if-ge`, `if-gt`, `if-le`;
- compare-with-zero/null branch: `if-eqz`, `if-nez`, `if-ltz`, `if-gez`, `if-gtz`, `if-lez`;
- dense and sparse integer dispatch: `packed-switch`, `sparse-switch`;
- float/double/long comparisons that first produce `-1`, `0`, or `1` in a register.

There is no DEX-visible condition-code register, branch prediction hint, predicated instruction,
or conditional-select instruction. Those physical-machine choices are hidden below ART. This is
exactly why the DEX backend is a useful comparison target: it lets us ask whether Edriç's meaning
of a conditional is completely captured by control-flow semantics, or whether a direct backend
such as ARM Thumb exposes machine facts worth preserving at a lower checked-IR layer.

Important lowering constraints:

- `if-*` branch offsets are signed 16-bit code-unit offsets and may not be zero.
- `goto` has 8-, 16-, and 32-bit offset forms; encoding selection can happen after layout.
- float comparison requires choosing `cmpl-*` versus `cmpg-*`; this determines the result for NaN.
- switch payloads are out-of-line data and require alignment.
- the DEX verifier still constrains which value kinds can legally be compared; a syntactically
  available opcode is not permission to erase Edriç type information.

## Register/encoding pass

DEX registers are method-local slots. Ordinary bit values use 32-bit registers; 64-bit values
occupy adjacent register pairs. Many encodings can name only the first 16 or 256 registers,
which is why `move`, `/from16`, `/16`, `/range`, and `/2addr` variants exist.

For Edriç this suggests a useful separation:

1. checked IR decides values, operations, and control flow;
2. a DEX register-placement pass decides register numbers;
3. a final encoding-selection pass chooses short/wide opcode forms without changing meaning.

That prevents DEX's compact-encoding accidents from leaking upward into the language.

## Numeric pass

The opcode table makes the numeric boundary unusually clear:

- direct 32-bit integer operations are extensive;
- direct IEEE-754 Float32 arithmetic exists;
- 64-bit integer and Float64 operations use register pairs;
- there is **no Float16 arithmetic opcode**;
- `boolean`, `byte`, `char`, and `short` suffixes appear mainly around array/field access and
  narrowing conversions; they should not automatically become Edriç's source type system.

Float64 remains an explicit exception rather than a default. If an Android framework signature
requires it, the bridge can use the wide DEX operation without changing the source-language
numeric policy.

## Object/runtime machinery pass

DEX includes classes, references, allocation, fields, dynamic dispatch, monitors, exceptions,
casts, method handles, and custom call sites. Their existence does **not** imply that Edriç needs
corresponding source constructs.

For an Android app we can treat much of this as FFI/bridge machinery generated from checked
framework bindings. In particular, an Edriç application should not need to spell inheritance,
a Java class declaration, `invoke-virtual`, or a field opcode merely because Android's runtime
requires those structures in `classes.dex`.

## First implementation slices

Do not implement the table in numeric order. Implement semantic slices and keep this inventory
as the completeness checklist.

### Slice A — tiny checked integer/control-flow method

`nop`; `move*`; `return-void`; `return`; `const/4`, `const/16`, `const`, `const/high16`;
`goto*`; `if-*`; core Int32 arithmetic/bit operations; literal forms.

### Slice B — Float32

`cmpl-float`, `cmpg-float`, `neg-float`, Int32↔Float32 conversions, Float32 arithmetic and
their `/2addr` encodings. Test signed zero, NaN branch behavior, infinities, division, and
conversion edges explicitly.

### Slice C — Android framework bridge

Reference moves/results/returns, string constants, `new-instance`, arrays as needed, field
access as needed, and ordinary `invoke-direct` / `invoke-static` / `invoke-virtual` /
`invoke-super` / `invoke-interface` forms. Generate this machinery from bindings; do not
expose it as Java-shaped Edriç syntax.

### Slice D — switches and compact encoding

Add packed/sparse switch payload construction, then perform register and instruction-width
selection (`/from16`, `/16`, `/range`, `/2addr`, literal forms) as a size/layout pass.

### Explicit opt-in only

64-bit operations, Float64, exceptions, monitors, runtime casts, method handles, and custom
call sites. Each needs a concrete source/interop requirement before it becomes part of the
backend acceptance surface.

## Completeness invariant

Any future opcode-table change must preserve the invariant that this file accounts for exactly
256 opcode slots. A later machine-readable `Opcode` table should test that no opcode number is
duplicated or silently omitted, and should keep the three payload pseudo-instructions separate
from executable opcodes.