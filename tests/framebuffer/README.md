# Framebuffer backend tests

This directory carries the executable acceptance work for #24.

## Handwritten RGB565 ISA oracle

`rgb565_oracle.S` is the handwritten Thumb-2 reference program established by
the parent oracle PR. It fixes the low-level semantics independently of the
compiler:

- a 4-pixel logical RGB565 row occupies 8 bytes
- physical stride is deliberately padded to 12 bytes
- `(3, 2)` lands at byte offset `2 * 12 + 2 * 3 = 30`
- adjacent 16-bit pixels remain independent
- multi-row writes respect padded stride
- row padding and guard halfwords remain untouched

`check.sh` assembles/links that reference program and runs it under `qemu-arm`.

## Smallest generated gate

`GeneratedPixelStore.idric` is the first generated Idriç framebuffer slice. It
accepts a device-independent `RGB565Surface` descriptor plus `x`, `y`, and a
pixel word, then invokes the exact renderer primitive that the ARM backend
lowers.

The descriptor is caller-owned, contains base/extent/width/height/stride
metadata, and is independent of fbdev, DRM/KMS, Android native windows, or
bare-metal scanout. RGB565 itself is carried by the type. Bounds and ownership
must already have been established when this hot-path descriptor is supplied;
the generated store deliberately performs no per-pixel bounds check.

The backend must emit the equivalent of:

```text
base        = surface.base
stride      = surface.stride_bytes
byte_offset = y * stride + 2 * x
address     = base + byte_offset
store16(address, pixel)
```

`make verify` therefore checks the generated assembly for the descriptor loads,
`MLA`, the `x << 1` address term, and `STRH`, rejects runtime calls, links the
generated function with `generated_selftest.S`, and executes it under QEMU on
the same padded 12-byte-stride geometry used by the oracle.

This PR intentionally stops at one generated `putPixel`. Generic integer
arithmetic, general pointer arithmetic, `fillRect`, proof construction, and
platform adapters remain later slices.
