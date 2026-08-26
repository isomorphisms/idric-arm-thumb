module Backend.ARMThumb.Lower

import Backend.ARMThumb.IR
import Compiler.ANF
import Core.Name
import Core.Name.Namespace

%default covering

private
max_locals : Int
max_locals = 256

private
record BuildState where
  constructor MkBuildState
  locals : List (Int, Local)
  next_slot : Int
  instructions_reversed : List Instruction

private
empty_state : BuildState
empty_state = MkBuildState [] 0 []

private
is_ascii_letter : Char -> Bool
is_ascii_letter character =
  (character >= 'A' && character <= 'Z') ||
  (character >= 'a' && character <= 'z')

private
is_ascii_digit : Char -> Bool
is_ascii_digit character =
  character >= '0' && character <= '9'

private
is_symbol_start : Char -> Bool
is_symbol_start character =
  is_ascii_letter character || character == '_'

private
is_symbol_rest : Char -> Bool
is_symbol_rest character =
  is_symbol_start character || is_ascii_digit character

public export
validate_external_symbol : String -> Either String String
validate_external_symbol symbol =
  case unpack symbol of
    [] => Left "An exported ARM symbol cannot be empty"
    first :: rest =>
      if is_symbol_start first && all is_symbol_rest rest
        then Right symbol
        else Left ("Invalid C-compatible ARM symbol `" ++ symbol ++ "`")

private
renderer_name : String -> Name
renderer_name leaf =
  NS (mkNamespace "RendererPrimitives") (UN (Basic leaf))

private
lookup_local : String -> Int -> BuildState -> Either String Local
lookup_local role variable state =
  find variable state.locals
  where
    find : Int -> List (Int, Local) -> Either String Local
    find requested [] =
      Left (role ++ " reads unbound ANF local v" ++ show requested)
    find requested ((candidate, local) :: rest) =
      if requested == candidate
        then Right local
        else find requested rest

private
bind_local : String -> Int -> BuildState -> Either String (BuildState, Local)
bind_local role variable state =
  if any (\entry => fst entry == variable) state.locals
    then Left (role ++ " v" ++ show variable ++ " is already defined")
    else if state.next_slot >= max_locals
      then Left "ARM Thumb leaf needs more than 256 four-byte locals"
      else
        let local = MkLocal variable state.next_slot
            next = MkBuildState
              ((variable, local) :: state.locals)
              (state.next_slot + 1)
              state.instructions_reversed
        in Right (next, local)

private
add_instruction : Instruction -> BuildState -> BuildState
add_instruction instruction state =
  MkBuildState state.locals state.next_slot
    (instruction :: state.instructions_reversed)

private
bind_arguments : List Int -> BuildState -> Either String (BuildState, List Local)
bind_arguments [] state = Right (state, [])
bind_arguments (variable :: rest) state = do
  (with_argument, argument) <- bind_local "Argument" variable state
  (complete, more) <- bind_arguments rest with_argument
  Right (complete, argument :: more)

private
data RendererPrimitive
  = Add
  | Multiply

private
renderer_primitive : Name -> Maybe RendererPrimitive
renderer_primitive name =
  if name == renderer_name "float32_add"
    then Just Add
    else if name == renderer_name "float32_multiply"
      then Just Multiply
      else Nothing

private
lower_external :
  Int -> Name -> List AVar -> BuildState -> Either String BuildState
lower_external destination name arguments state =
  case (renderer_primitive name, arguments) of
    (Just Add, [ALocal left, ALocal right]) =>
      lower_binary AddFloat32 destination left right state
    (Just Multiply, [ALocal left, ALocal right]) =>
      lower_binary MultiplyFloat32 destination left right state
    (Nothing, _) =>
      Left ("Unsupported external primitive `" ++ show name ++ "`")
    (_, _) =>
      Left ("Float32 arithmetic primitive `" ++ show name ++
            "` requires exactly two local operands")
  where
    lower_binary :
      FloatBinaryOperation -> Int -> Int -> Int -> BuildState ->
      Either String BuildState
    lower_binary operation destination left right state = do
      left_local <- lookup_local "Float32 left operand" left state
      right_local <- lookup_local "Float32 right operand" right state
      (with_destination, destination_local) <-
        bind_local "Let destination" destination state
      Right
        (add_instruction
          (FloatBinary operation destination_local left_local right_local)
          with_destination)

private
lower_value : Int -> ANF -> BuildState -> Either String BuildState
lower_value destination (AV _ (ALocal source)) state = do
  source_local <- lookup_local "Copy" source state
  (with_destination, destination_local) <-
    bind_local "Let destination" destination state
  Right (add_instruction (Copy destination_local source_local) with_destination)
lower_value destination (AExtPrim _ _ name arguments) state =
  lower_external destination name arguments state
lower_value destination expression state =
  Left
    ("Unsupported ANF value in first ARM Thumb slice: " ++ show expression)

private
lower_assignment : Int -> ANF -> BuildState -> Either String BuildState
lower_assignment destination (ALet _ nested_destination nested_value body) state = do
  after_nested <- lower_assignment nested_destination nested_value state
  lower_assignment destination body after_nested
lower_assignment destination value state =
  lower_value destination value state

private
fresh_variable_from : Int -> List (Int, Local) -> Int
fresh_variable_from candidate locals =
  if any (\entry => fst entry == candidate) locals
    then fresh_variable_from (candidate + 1) locals
    else candidate

private
collect_tail : ANF -> BuildState -> Either String (BuildState, Local)
collect_tail (ALet _ destination value body) state = do
  after_value <- lower_assignment destination value state
  collect_tail body after_value
collect_tail (AV _ (ALocal result)) state = do
  local <- lookup_local "Return" result state
  Right (state, local)
collect_tail expression state = do
  let result_variable = fresh_variable_from 0 state.locals
  after_value <- lower_value result_variable expression state
  result <- lookup_local "Return" result_variable after_value
  Right (after_value, result)

private
aligned_frame_bytes : Int -> Int
aligned_frame_bytes slots =
  let bytes = slots * 4 in
    if bytes <= 8
      then 8
      else if bytes `mod` 8 == 0 then bytes else bytes + 4

||| Lower one exported, closure-free Float32 leaf. The first slice admits only
||| Float32 arguments/results, copies, add, and multiply.
public export
lower_leaf : String -> Nat -> ANFDef -> Either String LeafFunction
lower_leaf requested_symbol expected_arity (MkAFun argument_variables body) = do
  symbol <- validate_external_symbol requested_symbol
  if length argument_variables /= expected_arity
    then
      Left
        ("Source ABI has " ++ show expected_arity ++
         " Float32 arguments, but ANF has " ++
         show (length argument_variables))
    else if length argument_variables > 4
      then Left "ARM Thumb softfp leaf admits at most four arguments"
      else do
        (with_arguments, arguments) <-
          bind_arguments argument_variables empty_state
        (complete, result) <- collect_tail body with_arguments
        Right
          (MkLeafFunction
            symbol
            arguments
            (reverse complete.instructions_reversed)
            result
            (aligned_frame_bytes complete.next_slot))
lower_leaf requested_symbol expected_arity definition =
  Left
    ("Export `" ++ requested_symbol ++
     "` is not a runtime-free function: " ++ show definition)
