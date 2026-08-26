module RendererPrimitives

%default total

||| Explicit unboxed renderer scalar used at the ARM ABI seam.
export
data Float32 : Type where [external]

export %extern float32_add : Float32 -> Float32 -> Float32
export %extern float32_multiply : Float32 -> Float32 -> Float32
