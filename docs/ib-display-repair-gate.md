# IB DisplayRepair ARM/Thumb design probe

`tests/ib/IB/DisplayRepair.idric` is copied verbatim from IB. The companion
program constructs one repair and observes all four fields. Its provisional
observable output is recorded in `tests/ib/expected.txt`.

This is not the acceptance contract for IB or Idriç. Producing a binary, or
even producing the expected output with direct Thumb instructions, does not
establish that the language or the browser has been designed correctly. The
fixture exists to force concrete language decisions and expose them for
review.

Before implementation, the probe asks:

- What is an Idriç string: encoding, length, ownership, mutability, slicing,
  lifetime, and native representation?
- What is a small named choice such as `copy_target_kind`, and when should its
  representation be narrower than a machine word?
- What is a record such as `DisplayRepair`: field layout, alignment,
  ownership, construction, and return convention?
- How should named functions, vector-indexed function families, and
  vector-indexed left-hand sides appear before and after lowering?
- What is the Idriç account of sequencing and outside effects, rather than
  inheriting Idris `IO` merely because it already exists?
- Which decisions belong to Idriç itself, which belong to the ARM/Thumb
  backend, and which are unavoidable Android NDK boundaries?

The current compiler happens to expose this source through ANF forms including
`AV`, `ALet`, string `APrimVal`, direct `AAppName`, `ACon`, and
`AConCase`. Those names describe the inherited compiler today. They neither
specify Idriç nor determine the order in which the language must be designed.

## Non-negotiable direction

The direct Float32 path remains separate and unboxed. Ordinary values must
also acquire native Idriç representations; RefC is not a fallback. There is no
generic boxed value, RefC allocator, RefC reference counter, RefC garbage
collector, or RefC ABI in the IB ARM/Thumb path.

The Android NDK supplies target tools and the specific platform facilities
that Idriç deliberately chooses to use. It is not a substitute high-level
runtime. Generated ARMv7 Thumb-2 instructions, data layout, calls, branches,
allocation decisions, and platform crossings must remain inspectable.

Likely representations—UTF-8 bytes in `.rodata`, an explicit string slice, a
narrow choice tag, or a stack/caller-owned record—are proposals to examine,
not automatic decisions. A locally efficient representation can still be
rejected when it fights the desired language.

## Meaning of success

This probe becomes green only after its source concepts and native
representations have been deliberately chosen and reviewed, its generated
instructions implement those choices, and its behavior is correct under
emulation and on the ARMv7 phone.

Even then it is only one settled piece. IB is accepted when its construction
is, in the user's judgment, the ground-up browser and programming-language
design intended—not merely when an Idriç binary exists.

Later design probes may include `IB.Storage.storage_kind_text`,
`IB.Storage.classify_path`, and IB's `Smoke.idric`, but they must not turn
into a race to compile progressively larger inherited Idris programs.
