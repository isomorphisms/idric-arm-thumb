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

## Generated putPixel gate

`GeneratedPixelStore.idric` first established the generated Idriç framebuffer
store. It accepts a device-independent `RGB565Surface` descriptor plus `x`,
`y`, and a pixel word, then invokes the exact renderer primitive that the ARM
backend lowers.

The descriptor is caller-owned, contains base/extent/width/height/stride
metadata, and is independent of fbdev, DRM/KMS, Android native windows, or
bare-metal scanout. RGB565 itself is carried by the type. Bounds and ownership
must already have been established when this hot-path descriptor is supplied;
the generated store deliberately performs no per-pixel bounds check.

The backend emits the equivalent of:

```text
base        = surface.base
stride      = surface.stride_bytes
byte_offset = y * stride + 2 * x
address     = base + byte_offset
store16(address, pixel)
```

## Generated fillRect gate

The next slice deliberately keeps that same `RGB565Surface` boundary. The
exported fixture accepts only `surface` and `pixel`; the Idriç source supplies
the handwritten oracle rectangle `x=1`, `y=0`, `width=2`, `height=2` to the
internal `rgb565_surface_fill_rect` primitive. This avoids widening the
four-register exported ABI or inventing a rectangle descriptor merely for the
first loop acceptance test.

Lowering adds one dedicated `FillRGB565` instruction rather than generic
branch/loop IR. Emission reuses the putPixel start-address calculation, rejects
non-positive width/height before loop entry, and keeps the hot pixel loop to:

```text
store16(pixel_address, pixel)
pixel_address += 2
remaining_width -= 1
branch if remaining_width != 0
```

Stride reload and row advance occur between rows. Rectangle validity is a
precondition established before this hot primitive, so there is no surface
bounds check inside the pixel loop.

`make verify` checks the generated assembly shape, rejects runtime calls, links
both generated functions with `generated_selftest.S`, and executes them under
QEMU on the same padded 12-byte-stride geometry used by the handwritten oracle.
The generated fill must touch exactly the four rectangle pixels while leaving
row padding, row 2, and both outer guards unchanged.

Generic integer/pointer arithmetic, generic control flow, clipping,
proof construction, platform adapters, blit/scroll/glyph work, wider pixel
formats, and SIMD remain later slices.
