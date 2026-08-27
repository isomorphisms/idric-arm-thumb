# Arm Thumb output-policy adverbs

Date: 2026-08-26

## Why this belongs in the backend

A runtime-free Arm Thumb backend makes implementation costs unusually visible.

For the seed fixture

```text
emit `X\b` 100,000 times
```

a loop representation can keep the executable tiny while still doing substantial work at runtime. But a direct lowering that performs one kernel `write` per iteration can make 100,000 syscalls. A buffered lowering can preserve the final byte stream while changing latency, memory use, error boundaries, and syscall count.

The backend therefore should not hide this distinction behind one permanent lowering rule.

## Candidate output policies

### Immediate

Conceptually:

```text
for 100000 iterations:
    write(stdout, "X\b", 2)
```

Properties:

- tiny working state;
- earliest visibility permitted by the OS/device;
- individual write errors remain individually observable;
- approximately 100,000 write syscalls for this fixture;
- can be very expensive when tiny syscalls dominate.

### Bounded buffered

Conceptually:

```text
buffer <= N bytes
append repetitions into buffer
write when full
flush remainder
```

Properties:

- bounded additional memory;
- drastically fewer syscalls;
- delayed visibility;
- different failure/error boundary;
- still runtime-free if the buffer and write loop are emitted directly without libc/runtime support.

For 200,000 bytes and a 4096-byte buffer, the lower bound is about 49 full writes plus one final partial write, rather than 100,000 two-byte writes.

### Precomputed static payload

For a compile-time-known finite repetition count, another candidate is embedding all 200,000 output bytes in the ELF and making one/few writes.

Properties:

- minimal runtime computation/syscalls;
- executable grows by roughly the payload size;
- bad choice when artifact size matters;
- demonstrates a direct space-time tradeoff.

This is intentionally the opposite end of the spectrum from the 114-byte loop representation.

### Chunked generated repetition

A middle policy can embed/generate a moderate repeated chunk such as 256 or 4096 bytes and loop over that chunk.

Properties:

- small executable increase;
- bounded memory;
- small syscall count;
- avoids embedding the entire 200,000-byte payload.

This is likely a useful practical point on the tradeoff curve.

### Adaptive selector

Compile multiple versions and select from runtime facts.

Possible facts:

- stdout is a terminal versus pipe/file;
- interactive latency requested;
- available memory class;
- output count/size;
- deployment profile.

The selector is itself ordinary Arm code and should remain inspectable.

## Preserve semantics explicitly

Combining output operations is only allowed when the relevant observational contract permits it.

The backend must not silently combine writes when source semantics require any of:

- explicit flush after each item;
- externally visible progress between writes;
- per-write error handling;
- hardware timing boundaries;
- a possible interaction between output events.

A byte-stream-only contract permits more batching than an immediate-effect contract.

## Cost report

The backend should be able to report estimates or exact structural facts before/after lowering, for example:

```text
policy: immediate
payload bytes: 200000
working buffer: 2
predicted write syscalls: 100000
code bytes: known after assembly
runtime dependency: none

policy: buffer-4096
payload bytes: 200000
working buffer: <=4096
predicted write syscalls: about 49-50
runtime dependency: none

policy: static-payload
embedded payload: 200000
predicted write syscalls: 1 or small constant
runtime dependency: none
```

The purpose is not for the backend to declare a winner. It should expose the consequences to Idriç/the programmer/profile.

## Important distinction: representation versus execution

The small loop result demonstrates:

```text
space representation:
  counter + branch + two payload bytes

runtime execution:
  branch back and perform the effect 100,000 times
```

A compiler optimization that recognizes repetition can move work from stored representation into time. Conversely, unrolling or embedding a static payload moves work/data from time into space.

The backend should make those transformations measurable.

## Proposed fixture family

Keep one semantic source fixture and lower it under several adverbs:

1. `immediate`
2. `buffered 256`
3. `buffered 4096`
4. `static-payload`
5. `adaptive`

For each artifact inspect:

- ELF bytes;
- loadable bytes;
- `.text`/payload bytes where available;
- syscall count;
- output byte count;
- maximum temporary memory;
- startup/wall/user/system time;
- exact output hash.

Run output timing both to `/dev/null`/pipe and to a real terminal. Terminal rendering can overwhelm backend differences.

## Broader Arm adverbs

The same interface could eventually expose other Arm-specific realization choices:

```text
compactly          -- prefer T32 encodings/code size
quickly            -- prefer larger/faster sequences where justified
branching          -- explicit branch
predicated         -- conditional/predicated form where supported
unrolled N         -- trade code size for branch overhead
hardware-float     -- when target/ABI permits
software-float     -- when required
runtime-free       -- reject unsupported runtime needs rather than import one
```

These are not all semantics-preserving under every observation or target. Each needs a stated contract and capability check rather than a global "optimization" switch.