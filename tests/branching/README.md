# Branching and dispatch acceptance fixtures

These eight source fixtures are deliberately ahead of the current runtime-free
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
| `IPv4ProtocolDispatch.idric` | sparse dispatch on an incoming 8-bit protocol tag | 1→ICMP, 6→TCP, 17→UDP, 41→IPv6, 47→GRE, 50→ESP, 51→AH, 58→ICMPv6, 132→SCTP, other→unknown | real network protocol dispatch; compare sparse branch lowering against a table with default-filled holes |
| `IBSubstringCatStep.idric` | one DFA transition for exact fixed-string search | state 0 + `c`→1, state 1 + `a`→2, state 2 + `t`→matched, failed prefix + `c`→restart | real IB-derived substring workload; compare ordinary conditional lowering with table/computed-branch or packed-state approaches without importing heap/string runtime into this fixture |
| `FieldmouseRenderChoice.idric` | Field Mouse `choice` construction + constructor dispatch | undefined→0, null→1, true→2, false→3, number→4, text→5 | real Edriç application boundary: lower a `choice` tag/payload representation and dispatch on constructors rather than only switching on raw integer selectors |

## Important distinctions

`AsciiClassify128` and `TokenDispatch64` are intentionally dense switches. They
are good candidates for Thumb jump-table forms once constant-case lowering
exists.

`IPv4ProtocolDispatch` is deliberately sparse but bounded by a real one-byte
wire field. It gives the backend a useful code-generation choice: a comparison
tree, a compact jump table with default entries, or later a true handler-table
lookup followed by an indirect branch/call when function-pointer lowering
exists. The present fixture tests only selection of the handler/action slot; it
does not pretend that indirect calls are implemented yet.

`UnicodeRangeLookup` is intentionally the opposite. A Unicode scalar space has
1,114,112 numeric positions, so a flat jump table would be wasteful. This
fixture keeps the source shaped like a compressed property lookup and gives the
backend a reason to learn ordered range branches or a searchable table.

`ParserDispatch` is also not a claim that this miniature table is a full parser.
It isolates the dispatch problem: given a parser state and a token class, select
one parser action.

`IBSubstringCatStep` comes from the browser optimization target tracked at
https://github.com/isomorphisms/ib/issues/33.  It deliberately models one
streaming state transition rather than importing `String`/`List Char` into this
runtime-free branch fixture. Repeated transitions are an exact search for the
literal `cat`; later executable tests should compare this ordinary DFA lowering
with the table/computed-branch experiment in #9 and packed-bit search in #10.

`FieldmouseRenderChoice` comes directly from Field Mouse's `value`/`render`
boundary at
https://github.com/isomorphisms/fieldmouse/blob/3ad88740df66e929d5cb195af6de255336afef7e/Fieldmouse.idric#L348-L355.
It preserves the five-constructor choice shape and the Boolean subcases, while
using Float32/Int32 stand-in payloads for the current Double/String payloads so
the fixture tests constructor representation and tag dispatch without pulling
those unrelated runtime surfaces into the ARM/Thumb experiment.
