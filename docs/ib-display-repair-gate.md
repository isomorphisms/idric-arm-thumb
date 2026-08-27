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

The direct Float32 path remains separate and unboxed. The existing RefC
representation and runtime are available as bootstrap scaffolding for the
first ordinary values; they are not an Idriç language contract. The backend
may emit Thumb assembly for generated functions while borrowing RefC C sources
for allocation, strings, reference counting, or primitives. If the IB gate
exposes a better Idriç primitive or representation, the language, prelude,
runtime, and backend may change together.

On the compiler's present ANF, the smallest apparent implementation order is
managed copies and lets, string constants, direct named calls, constructors,
constructor cases, then the output primitive. That ANF shape is also
replaceable scaffolding. The acceptance contract is the behavior of the real
IB fixture, not compatibility with Idris's prelude, primitives, runtime, or
intermediate representation. General closures, partial application,
recursion, arrays, and the rest of `IO` are not required by this gate.

After this program executes under `qemu-arm`, the next IB gates are
`IB.Storage.storage_kind_text`, `IB.Storage.classify_path`, and finally IB's
existing `Smoke.idric` program.
