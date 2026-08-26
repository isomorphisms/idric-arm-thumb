module Backend.ARMThumb.IR

import Data.String

%default total

||| A dense four-byte stack home for one unboxed Float32 value.
public export
record Local where
  constructor MkLocal
  anf_variable : Int
  frame_slot : Int

public export
Show Local where
  show local =
    "v" ++ show local.anf_variable ++ "@" ++ show local.frame_slot

public export
data FloatBinaryOperation
  = AddFloat32
  | MultiplyFloat32

public export
Show FloatBinaryOperation where
  show AddFloat32 = "add"
  show MultiplyFloat32 = "multiply"

||| First-slice runtime-free IR: copies and Float32 arithmetic only.
public export
data Instruction
  = Copy Local Local
  | FloatBinary FloatBinaryOperation Local Local Local

public export
Show Instruction where
  show (Copy destination source) =
    show destination ++ " = copy " ++ show source
  show (FloatBinary operation destination left right) =
    show destination ++ " = " ++ show operation ++
    " " ++ show left ++ " " ++ show right

||| One C-callable, closure-free numerical leaf.
public export
record LeafFunction where
  constructor MkLeafFunction
  external_symbol : String
  arguments : List Local
  instructions : List Instruction
  result : Local
  frame_bytes : Int

public export
render_ir : LeafFunction -> String
render_ir function =
  unlines
    ([ "function " ++ function.external_symbol
     , "arguments: " ++ show function.arguments
     ] ++
     map (\instruction => "  " ++ show instruction) function.instructions ++
     [ "return " ++ show function.result
     , "frame-bytes: " ++ show function.frame_bytes
     ])
