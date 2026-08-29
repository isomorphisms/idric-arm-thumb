# Temporary typed pseudo-register IR experiment

This note records a **provisional** idea suggested by studying DEX. It is not a commitment to a new permanent IR. The pseudo-register layer may later shrink, merge into existing checked ANF/IR, split into more precise forms, or disappear entirely if it proves redundant.

The useful part of DEX here is its simple, inspectable register-machine shape. The goal is to borrow that clarity without importing DEX/Java semantics into Edriç.

## Shape

Treat pseudo-registers as names for checked values, not as claims about physical CPU registers:

```text
r0 : A
r1 : B
r2 ← operation r0 r1
```

A later backend may keep a value in a physical register, spill it, recompute it, map it to SIMD lanes, or realize it in GPU work. None of those choices changes the meaning of `r2` here.

## Mathematical operations before execution strategy

The main reason to try this layer is to keep mathematical structure visible until a backend actually has to choose an implementation.

### Ordinary typed addition

```text
r0 : Vector n F
r1 : Vector n F
r2 ← add r0 r1
```

Before this instruction exists, checking should already have established compatible dimension and scalar structure. `add` does not mean `for` loop. A backend may lower it to scalar iteration, SIMD, GPU work, or another target-specific mechanism.

### Einstein contraction

```text
vⁱ : V
ωᵢ : V*
r0 ← multiply_indexed ωᵢ vⁱ
r1 ← contract i r0
```

The repeated index `i` records contraction. It should not be defined as a loop at this level.

### Free indices / tensor product

```text
vⁱ : V
ωⱼ : V*
r0ⁱⱼ ← tensor_product vⁱ ωⱼ
```

The two free indices survive into the result. This is semantically different from contraction even if some eventual implementation traverses memory with similar machine instructions.

## Type and index constraints

Compile-time type inference and index checking are validation of the pseudo-register program, not ordinary runtime opcodes.

Examples of facts that may be established before lowering:

```text
same_dimension r0 r1
same_scalar_structure r0 r1
upper_index v i
lower_index ω i
repeated_index i → contraction
free_indices (i,j) → result indexed by (i,j)
```

Runtime type discrimination, when genuinely required by a program or Android interoperability boundary, should be represented separately rather than confusing it with compile-time checking.

## Candidate semantic operations

The experiment should be allowed to represent operations such as:

```text
copy
constant
add
subtract
multiply
divide
compare
branch
select
tensor_product
contract
elementwise
iterate
reduce
load
store
call
return
```

This list is exploratory. An operation should survive only if it describes a useful semantic distinction shared by multiple backends.

## Lowering experiments

Use the same checked pseudo-register fixture to compare:

```text
pseudo-register IR
    ├─→ DEX
    ├─→ ARM Thumb
    ├─→ x86-64
    ├─→ SIMD-oriented lowering
    └─→ GPU lowering
```

For Einstein-indexed operations in particular, compare at least:

```text
scalar iteration
SIMD
GPU execution
```

without assuming in advance that one is the semantic definition of the source operation.

## Reasons to delete this layer

Remove or merge the pseudo-register representation if experiments show any of the following:

- it duplicates existing checked ANF/IR without preserving additional meaning;
- every backend immediately reconstructs different information anyway;
- mathematical structure is better represented directly in another existing compiler form;
- pseudo-register naming encourages accidental assumptions about physical registers;
- maintaining the extra layer costs more than the cross-backend comparison value it provides.

Related issue: https://github.com/isomorphisms/idric-arm-thumb/issues/38
