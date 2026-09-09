# Provisional complex/projective follower

For general backend development, Thumb-2 remains the human-in-the-loop leader. Complex and projective arithmetic are an explicit current exception: the direct x86-64 implementation is the executable CPU leader and oracle for this subsystem, following the canonical mathematical semantics and shared corpus.

This Thumb-2 implementation is **provisional and disposable**.

The user may later replace its register assignments, polar representation, helper conventions, lowering structure, floating-point choices, or the implementation as a whole. Such a rewrite is not a semantic break if it continues to satisfy the shared mathematical contract.

Nothing in the present polar slice constrains the x86-64, compiler-level, or GPU design.

## What this branch actually proves

The inherited `polar-complex-first` slice lowers one logical complex multiplication to two Float32 leaves:

```text
(magnitude, phaseTurns)
```

and the ARM self-test executes under QEMU:

```text
(2, 1/8 turn) * (3, 1/4 turn) = (6, 3/8 turn).
```

That is a genuine executable complex-multiplication follower receipt. It is not a general complex arithmetic implementation.

## What it does not prove

The current Thumb implementation does not yet consume the complete shared Cartesian Float32 corpus. In particular, this branch does not claim support for:

- complex addition/subtraction in the logical complex representation;
- reciprocal/division;
- general Cartesian/polar conversion;
- the bounded shared complex exponential;
- polynomial/rational evaluation as complex values;
- C^n dimensional complex coordinate types;
- homogeneous/projective coordinates;
- projective equivalence or chart extraction;
- the shared headless render.

Those stages are recorded as `SKIP`, not `PASS`.

## Why not expand the polar ABI here

The existing polar pair is useful for multiplication and exact dyadic phase fixtures, but it is not automatically the correct general machine representation for all complex operations. Addition in particular would force conversion or additional machinery, and projective coordinates should not be shaped by a temporary four-word Thumb ABI.

This job therefore preserves the existing executable proof and documents its status instead of growing a temporary ARM design until it starts dictating the shared semantics.

## Semantic boundaries that already apply

Even before full follower coverage exists:

- mathematical `Complex` is not defined as a Thumb register pair;
- machine precision may not be silently narrowed;
- projective points, when implemented, must use homogeneous representatives with common nonzero rescaling semantics rather than raw component equality;
- conjugation, magnitude, and phase are observational/non-holomorphic operations and must not enter a state advertised as a holomorphic deformation merely because the polar representation makes phase convenient;
- the current whole-plane explorer contract remains `f(z)=R(z) exp(q(z))`, with the explicit zero/pole divisor in `R` and entire freedom in `q`.
