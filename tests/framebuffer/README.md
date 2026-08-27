# Framebuffer backend tests

This directory starts the executable acceptance work for #24.

## Current test: RGB565 ISA oracle

`rgb565_oracle.S` is a handwritten Thumb-2 reference program. It establishes the exact low-level semantics that later Idriç-generated code should match; it is **not** evidence that the backend already lowers framebuffer operations.

The oracle models a 4-pixel-wide RGB565 surface whose logical rows occupy 8 bytes but whose physical stride is 12 bytes. It checks:

- `(0, 0)` addressing
- nonzero `x` and `y`: `(3, 2)` must land at byte offset `2 * 12 + 2 * 3 = 30`
- independent adjacent 16-bit stores
- a 2x2 rectangle fill over two padded rows
- untouched pixels and row-padding around that rectangle
- guard halfwords immediately before and after the framebuffer

`check.sh` assembles/links the oracle as a static ARMv7 Thumb executable and runs it under `qemu-arm`. A nonzero exit status identifies the failed assertion.

## Next compiler-generated gate

The current backend only has the Float32 renderer seam, so the next implementation step is to add the smallest integer/pointer/store representation needed for a source-level RGB565 fixture. At that point the generated-code tests should require:

```text
byte_offset = y * stride_bytes + 2 * x
address     = base + byte_offset
store       = 16-bit RGB565 pixel
```

and inspect the generated Thumb assembly for a halfword store (`STRH` or an equivalent 16-bit store), while keeping bounds/proof work out of the inner pixel loop.

Do not make `/dev/fb0` part of this compiler contract. fbdev, DRM/KMS, Android native windows, and bare-metal displays are platform adapters over the same surface semantics.
