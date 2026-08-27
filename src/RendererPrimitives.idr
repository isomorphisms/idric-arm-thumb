module RendererPrimitives

%default total

||| Explicit unboxed renderer scalar used at the ARM ABI seam.
export
data Float32 : Type where [external]

||| Caller-owned contiguous Float32 memory. The backend assumes a non-null,
||| suitably aligned pointer and an in-bounds Int32 index at the FFI boundary.
export
data Float32Buffer : Type where [external]

||| Device-independent validated RGB565 surface descriptor.
|||
||| The ARM seam receives one pointer to caller-owned metadata:
|||   word 0: pixel base address
|||   word 1: buffer extent in bytes
|||   word 2: width in pixels
|||   word 3: height in pixels
|||   word 4: stride in bytes
|||
||| RGB565 is carried by the type rather than an operating-system handle.
||| Platform adapters establish bounds/ownership before this hot-path value
||| reaches generated code; no Idris heap object is required here.
export
data RGB565Surface : Type where [external]

export %extern float32_buffer_load : Float32Buffer -> Int32 -> Float32

export %extern float32_add : Float32 -> Float32 -> Float32
export %extern float32_subtract : Float32 -> Float32 -> Float32
export %extern float32_multiply : Float32 -> Float32 -> Float32
export %extern float32_divide : Float32 -> Float32 -> Float32

export %extern float32_negate : Float32 -> Float32
export %extern float32_absolute : Float32 -> Float32
export %extern float32_square_root : Float32 -> Float32

||| Store the low 16 bits at base + y * stride_bytes + 2 * x and return
||| the original Int32 pixel word. The return keeps this first generated
||| straight-line fixture observable without introducing Unit lowering.
export %extern rgb565_surface_store :
  RGB565Surface -> Int32 -> Int32 -> Int32 -> Int32

||| Fill an already validated rectangle using scalar RGB565 halfword stores.
||| x, y, width, and height are established before the hot pixel loop; the
||| backend must not introduce per-pixel surface bounds checks. Non-positive
||| width or height is an empty fill. The original pixel word is returned to
||| keep this slice inside the existing one-word result boundary.
export %extern rgb565_surface_fill_rect :
  RGB565Surface -> Int32 -> Int32 -> Int32 -> Int32 -> Int32 -> Int32
