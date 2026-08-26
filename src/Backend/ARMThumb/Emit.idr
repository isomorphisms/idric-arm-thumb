module Backend.ARMThumb.Emit

import Backend.ARMThumb.IR
import Backend.ARMThumb.Lower
import Data.String

%default total

private
slot_address : Local -> String
slot_address local =
  "[sp, #" ++ show (local.frame_slot * 4) ++ "]"

private
load_word : String -> Local -> List String
load_word register local =
  ["        ldr     " ++ register ++ ", " ++ slot_address local]

private
store_word : String -> Local -> List String
store_word register local =
  ["        str     " ++ register ++ ", " ++ slot_address local]

private
load_float : String -> Local -> List String
load_float register local =
  ["        vldr    " ++ register ++ ", " ++ slot_address local]

private
store_float : String -> Local -> List String
store_float register local =
  ["        vstr    " ++ register ++ ", " ++ slot_address local]

private
float_binary_mnemonic : FloatBinaryOperation -> String
float_binary_mnemonic AddFloat32 = "vadd.f32"
float_binary_mnemonic MultiplyFloat32 = "vmul.f32"

private
emit_instruction : Instruction -> List String
emit_instruction (Copy destination source) =
  load_word "r0" source ++ store_word "r0" destination
emit_instruction (FloatBinary operation destination left right) =
  load_float "s0" left ++
  load_float "s1" right ++
  [ "        " ++ float_binary_mnemonic operation ++ " s0, s0, s1" ] ++
  store_float "s0" destination

private
emit_instructions : List Instruction -> List String
emit_instructions [] = []
emit_instructions (instruction :: rest) =
  emit_instruction instruction ++ emit_instructions rest

private
argument_registers : List String
argument_registers = ["r0", "r1", "r2", "r3"]

private
store_arguments : List Local -> List String -> List String
store_arguments [] registers = []
store_arguments (argument :: rest) (register :: registers) =
  store_word register argument ++ store_arguments rest registers
store_arguments arguments [] = []

private
validate_local_home : LeafFunction -> Local -> Either String ()
validate_local_home function local =
  if local.frame_slot < 0 || local.frame_slot * 4 + 4 > function.frame_bytes
    then
      Left
        ("Local " ++ show local ++ " is outside the " ++
         show function.frame_bytes ++ "-byte frame")
    else Right ()

private
validate_instruction : LeafFunction -> Instruction -> Either String ()
validate_instruction function (Copy destination source) = do
  validate_local_home function destination
  validate_local_home function source
validate_instruction function (FloatBinary operation destination left right) = do
  validate_local_home function destination
  validate_local_home function left
  validate_local_home function right

private
validate_instructions : LeafFunction -> List Instruction -> Either String ()
validate_instructions function [] = Right ()
validate_instructions function (instruction :: rest) = do
  validate_instruction function instruction
  validate_instructions function rest

private
validate_arguments : LeafFunction -> List Local -> Either String ()
validate_arguments function [] = Right ()
validate_arguments function (argument :: rest) = do
  validate_local_home function argument
  validate_arguments function rest

private
validate_leaf_for_emission : LeafFunction -> Either String ()
validate_leaf_for_emission function = do
  _ <- validate_external_symbol function.external_symbol
  if function.frame_bytes <= 0 ||
     function.frame_bytes > 1024 ||
     function.frame_bytes `mod` 8 /= 0
    then
      Left
        ("ARM Thumb leaf frame must be 8-byte aligned and between 8 and " ++
         "1024 bytes, got " ++ show function.frame_bytes)
    else Right ()
  if length function.arguments > 4
    then Left "ARM Thumb softfp leaf admits at most four arguments"
    else Right ()
  validate_arguments function function.arguments
  validate_instructions function function.instructions
  validate_local_home function function.result

||| Emit Android armeabi-v7a Thumb-2. Float32 values cross the C ABI as raw
||| words in r0-r3; VFPv3-D16 is used only inside the numerical leaf.
public export
emit_leaf : LeafFunction -> Either String String
emit_leaf function = do
  validate_leaf_for_emission function
  Right (unlines
    ([ ""
     , "        .p2align 2"
     , "        .global " ++ function.external_symbol
     , "        .type " ++ function.external_symbol ++ ", %function"
     , "        .thumb_func"
     , function.external_symbol ++ ":"
     , "        sub.w   sp, sp, #" ++ show function.frame_bytes
     ] ++
     store_arguments function.arguments argument_registers ++
     emit_instructions function.instructions ++
     load_word "r0" function.result ++
     [ "        add.w   sp, sp, #" ++ show function.frame_bytes
     , "        bx      lr"
     , "        .size " ++ function.external_symbol ++
       ", .-" ++ function.external_symbol
     ]))

public export
assembly_header : String
assembly_header =
  unlines
    [ ".syntax unified"
    , ".arch armv7-a"
    , ".fpu vfpv3-d16"
    , ".thumb"
    , ".text"
    , ""
    , "@ Runtime-free Idriç numerical leaf for Android armeabi-v7a."
    , "@ ABI: softfp boundary, VFP Float32 arithmetic internally."
    ]

public export
assembly_footer : String
assembly_footer =
  "\n.section .note.GNU-stack,\"\",%progbits\n"
