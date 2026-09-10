# Agent instructions

Apply the shared evidence and acceptance guardrails in
`isomorphisms/ai-ci/AGENTS.md`.

## Keep this repository ARM/Thumb-specific

This repository owns the ARM/Thumb backend. Do not stack DEX/ART, JNI launcher,
or application-specific Android work onto an ARM/Thumb branch merely because an
existing ARM branch already has useful CI or compiler plumbing.

ARM/QEMU acceptance is not DEX/ART acceptance, and a DEX branch inheriting ARM
history does not make the two backends one architecture. Put a distinct backend
on its own repository/branch boundary unless the current architecture explicitly
integrates them.

## Prove the native backend being claimed

An ARM/Thumb backend claim must bind the exact Idriç/compiler contract to the
exact backend head and inspect or execute the ARM/Thumb artifact required by the
task.

Generated C, RefC, a host implementation, a JNI shell, a simulator for another
ISA, or a handwritten equivalent may be useful as an oracle or bootstrap, but
it is not native ARM/Thumb backend evidence when the native path is the claim.

Temporary application harnesses must remain replaceable and must not define the
generic backend interface merely because they were the first executable path.
