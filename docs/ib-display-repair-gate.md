# IB DisplayRepair ARM/Thumb gate

`tests/ib/IB/DisplayRepair.idric` is copied verbatim from IB. The companion
program constructs one repair and observes all four fields. Its output is
fixed by `tests/ib/expected.txt`.

This is the first ordinary-Idriç acceptance gate. It requires the pieces that
the numerical-leaf backend does not exercise:

- `AV` and nested `ALet` for ordinary managed values;
- string `APrimVal` values;
- direct `AAppName` calls;
- `ACon` lowered to a concrete native layout chosen for this program;
- `AConCase` tag dispatch and field binding;
- the small `IO`/`putStrLn` path needed to execute the oracle.

The direct Float32 path remains separate and unboxed. Ordinary values must
also acquire native Idriç representations in this backend; RefC is not a
fallback. For this gate, string literals can live as UTF-8 bytes in `.rodata`,
the three-way choice can use a narrow tag, and `DisplayRepair` can use a
known stack or caller-owned record layout. Direct calls and pattern matches
become Thumb calls, loads, comparisons, and branches. No generic boxed value,
RefC allocator, RefC reference counter, RefC garbage collector, or RefC ABI is
part of the path.

On the compiler's present ANF, the smallest apparent implementation order is
native copies and lets, string slices and literals, direct named calls, the
concrete record, constructor cases, then the output boundary. That ANF shape
is also replaceable scaffolding. The acceptance contract is the behavior of
the real IB fixture and inspectable ARMv7 Thumb-2 output, not compatibility
with Idris's prelude, primitives, runtime, or intermediate representation.
General closures, partial application, recursion, generic heap allocation,
arrays, and the rest of Idris `IO` are not required by this gate.

The executable is assembled and linked with the Android NDK toolchain. The
oracle must inspect the generated instructions and execute under `qemu-arm`;
the eventual phone boundary uses only the specific Android/NDK facilities the
program actually needs.

After this program executes under `qemu-arm`, the next IB gates are
`IB.Storage.storage_kind_text`, `IB.Storage.classify_path`, and finally IB's
existing `Smoke.idric` program.
