# ARM/Thumb screen-red oracle

This directory preserves the ARMv7/Thumb-2 side of the device-action matrix in
`isomorphisms/Idric#85` without claiming compiler support that has not yet been
established.

The sequencing authority is `isomorphisms/idric-arm-thumb#31`: framebuffer
oracles may proceed independently, while a generated Idriç screen action waits
for the required integer, memory, record, and surface contracts.

## `rgb565_oracle.S`

A handwritten Thumb-2 semantic oracle for a small RGB565 surface. It checks
stride-aware addressing, independent 16-bit stores, rectangle fill, row padding,
and guard values. `check.sh` assembles and links it as an ARMv7 Thumb ELF and
executes it under `qemu-arm`.

This proves the handwritten ISA oracle only. It is not evidence that the Idriç
compiler emitted the instructions.

## `linux_fbdev_red.S`

A handwritten no-libc Linux reference program for the action "show the selected
display red". It enters the Linux kernel directly, tries `/dev/graphics/fb0`
and `/dev/fb0`, obtains framebuffer geometry, maps the framebuffer, constructs a
red pixel from the reported bitfield, fills the visible image, waits three
seconds, and exits.

`check.sh` assembles and inspects this program but deliberately does not execute
it under user-mode QEMU. User-mode QEMU does not provide the required framebuffer
device boundary. Full-system guest execution and captured presented output are
separate matrix evidence and remain pending until a guest with an explicit
display device is provisioned.

The fbdev path is a platform adapter, not the source-language contract. DRM/KMS,
Android native-window/SurfaceFlinger paths, or a bare-metal framebuffer may
implement the same semantic action independently.

## Evidence levels

Keep these distinct:

1. source/oracle presence;
2. ARMv7 Thumb assembly/link and object inspection;
3. user-mode execution of the in-memory RGB565 oracle;
4. full-system Linux guest execution through a declared display device;
5. physical-device execution.

Only the first three are exercised by this directory today.
