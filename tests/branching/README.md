# Branching and dispatch acceptance fixtures

These five source fixtures are deliberately ahead of the current runtime-free
ARM/Thumb lowering surface. They are tests now, not claims that branches are
implemented.

Every exported function keeps the existing accepted C ABI: a caller-owned
`Float32Buffer`, up to two `Int32` selectors, and one `Float32` result. The
buffer is only an oracle: slot `n` contains a distinct Float32 sentinel, so a
future executable test can observe which integer result or dispatch action was
selected without adding an integer return ABI.

`check-current-boundary.sh` requires each fixture to pass parsing, typechecking,
export resolution, and source-ABI validation, then fail specifically at the
current reachable-program lowering boundary. A parser/type error or source-ABI
error therefore fails the test. When a control-flow primitive is implemented,
the corresponding fixture should be promoted from expected rejection to exact
assembly and QEMU semantic checks.

## Fixtures

| Fixture | Shape | Representative semantic checks | Intended lowering lesson |
| --- | --- | --- | --- |
| `AsciiCaseBit.idric` | guarded `Int32` bit toggle | `A→a`, `Z→z`, `a→A`, `z→Z`, `0→0` | ASCII letter case is bit 5 (`xor 32`) after a range guard; do not build a 52-entry jump table |
| `AsciiClassify128.idric` | exact 128-way constant case | NUL→control, space→space, `0`→digit, `A`→uppercase, `a`→lowercase, `!`→punctuation, 128→non-ASCII | dense constant dispatch and jump-table pressure |
| `TokenDispatch64.idric` | 64 contiguous token kinds | identifier→atom, `+`→infix, `if`→control, `module`→declaration, EOF→EOF action | realistic lexer/token dispatch over a dense tag range |
| `UnicodeRangeLookup.idric` | ordered range decisions | `λ`→Greek, U+0301→combining, U+4E00→CJK, U+1F600→emoji range, surrogate→invalid | Unicode tables are compressed/range-shaped, not million-way jump tables |
| `ParserDispatch.idric` | nested parser-state × token-class cases | want-expression+atom→shift atom, have-expression+infix→shift infix, have-expression+EOF→accept | parser action dispatch; nested dense cases can become tables or mixed branch/table lowering |

## Important distinctions

`AsciiClassify128` and `TokenDispatch64` are intentionally dense switches. They
are good candidates for Thumb jump-table forms once constant-case lowering
exists.

`UnicodeRangeLookup` is intentionally the opposite. A Unicode scalar space has
1,114,112 numeric positions, so a flat jump table would be wasteful. This
fixture keeps the source shaped like a compressed property lookup and gives the
backend a reason to learn ordered range branches or a searchable table.

`ParserDispatch` is also not a claim that this miniature table is a full parser.
It isolates the dispatch problem: given a parser state and a token class, select
one parser action.
