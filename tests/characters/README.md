# Character and UTF-8 ARM/Thumb smoke gates

These fixtures deliberately start with observable text behavior instead of numerical leaves.

The current backend does not yet accept `IO ()`, strings, or `Char`; `check-current-boundary.sh` therefore requires each valid Idriç fixture to reach the ARM/Thumb source-ABI rejection rather than fail earlier in parsing or typechecking. As character I/O is implemented, these fixtures should move one by one from expected rejection to executable semantic tests.

| Fixture | Input bytes | Required output bytes | What it forces |
| --- | --- | --- | --- |
| `PrintASCII.idric` | — | `78` | `putChar 'x'`, ASCII output |
| `PrintUTF8.idric` | — | `ce bb` | UTF-8 output for `λ` through `putStr` |
| `ReadASCII.idric` | `58` | `58` | `getChar` + `putChar` byte echo for `X` |
| `ReadUTF8.idric` | `ce bb 0a` | `ce bb` | `getLine` + `putStr`, UTF-8 string input/output |
| `Concat.idric` | — | `78 ce bb` | string concatenation across ASCII and UTF-8 |
| `FGrepLambda.idric` | `78 ce bb 78 0a` | `78 ce bb 78 0a` | read, decode/traverse, compare with `'λ'`, branch, output |

`FGrepLambda.idric` must also produce no output for input `xxx\n`.

The distinction between the byte and UTF-8 paths is intentional. In the pinned Idriç Prelude, `putChar` and `getChar` are documented as single-byte operations. `putStr`/`getLine` are therefore the initial UTF-8 I/O path; a future Unicode-aware scalar `Char` I/O API can be specified separately rather than accidentally treating UTF-8 bytes as characters.
