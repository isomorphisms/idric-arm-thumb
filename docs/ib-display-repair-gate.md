# IB DisplayRepair ARM/Thumb gate

`tests/ib/IB/DisplayRepair.idric` is copied verbatim from IB. The companion
program constructs one repair and observes all four fields. Its output is
fixed by `tests/ib/expected.txt`.

This is the first ordinary-Idriç acceptance gate. It requires the pieces that
the numerical-leaf backend does not exercise:

- `AV` and nested `ALet` for ordinary managed values;
- string `APrimVal` values;
- direct `AAppName` calls;
- `ACon` allocation using the existing RefC `Idris2_Value` constructor ABI;
- `AConCase` tag dispatch and field binding;
- the small `IO`/`putStrLn` path needed to execute the oracle.

The direct Float32 path remains separate and unboxed. Ordinary values use the
RefC representation and runtime instead of inventing a second object layout.
The backend still emits Thumb assembly for generated functions; the RefC C
sources supply allocation, strings, reference counting, and primitives.

The intended implementation order is managed copies and lets, string
constants, direct named calls, constructors, constructor cases, then the
output primitive. General closures, partial application, recursion, arrays,
and the rest of `IO` are not part of this gate.

After this program executes under `qemu-arm`, the next IB gates are
`IB.Storage.storage_kind_text`, `IB.Storage.classify_path`, and finally IB's
existing `Smoke.idric` program.
