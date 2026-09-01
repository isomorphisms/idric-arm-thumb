module Backend.DEX.Lower

import Backend.DEX.IR
import Compiler.ANF
import Core.Name
import Core.TT.Primitive
import Data.Vect

%default covering

private
record LowerState where
  constructor MkLowerState
  integer_less_name : Name
  registers : List (Int, Register)
  result_register : Register
  next_label : Int
  instructions_reversed : List Instruction

private
emit : Instruction -> LowerState -> LowerState
emit instruction state =
  { instructions_reversed := instruction :: state.instructions_reversed } state

private
fresh_label : LowerState -> (Label, LowerState)
fresh_label state =
  (MkLabel state.next_label, { next_label $= (+ 1) } state)

private
lookup_register : String -> Int -> LowerState -> Either String Register
lookup_register role variable state =
  case find_register variable state.registers of
    Nothing => Left (role ++ " reads unknown ANF local v" ++ show variable)
    Just register => Right register
  where
    find_register : Int -> List (Int, Register) -> Maybe Register
    find_register requested [] = Nothing
    find_register requested ((candidate, register) :: rest) =
      if requested == candidate
        then Just register
        else find_register requested rest

private
append_unique : List Int -> Int -> List Int
append_unique values value =
  if elem value values then values else values ++ [value]

private
append_uniques : List Int -> List Int -> List Int
append_uniques values [] = values
append_uniques values (value :: rest) =
  append_uniques (append_unique values value) rest

mutual
  private
  collect_variables : ANF -> List Int
  collect_variables (ALet _ destination value body) =
    append_uniques
      (append_unique (collect_variables value) destination)
      (collect_variables body)
  collect_variables (AConCase _ _ alternatives fallback) =
    append_uniques
      (collect_constructor_alternatives alternatives)
      (maybe [] collect_variables fallback)
  collect_variables (AConstCase _ _ alternatives fallback) =
    append_uniques
      (collect_constant_alternatives alternatives)
      (maybe [] collect_variables fallback)
  collect_variables expression = []

  private
  collect_constructor_alternatives : List AConAlt -> List Int
  collect_constructor_alternatives [] = []
  collect_constructor_alternatives
    (MkAConAlt _ _ _ arguments body :: rest) =
      append_uniques arguments
        (append_uniques (collect_variables body)
          (collect_constructor_alternatives rest))

  private
  collect_constant_alternatives : List AConstAlt -> List Int
  collect_constant_alternatives [] = []
  collect_constant_alternatives (MkAConstAlt _ body :: rest) =
    append_uniques (collect_variables body)
      (collect_constant_alternatives rest)

private
number_registers_from : Int -> List Int -> List (Int, Register)
number_registers_from next [] = []
number_registers_from next (variable :: rest) =
  (variable, MkRegister next) :: number_registers_from (next + 1) rest

private
integer_condition : PrimFn 2 -> Maybe IntegerCondition
integer_condition (LT Int32Type) = Just LessThanInteger
integer_condition (LTE Int32Type) = Just LessEqualInteger
integer_condition (EQ Int32Type) = Just EqualInteger
integer_condition (GTE Int32Type) = Just GreaterEqualInteger
integer_condition (GT Int32Type) = Just GreaterThanInteger
integer_condition _ = Nothing

private
integer_binary : PrimFn 2 -> Maybe IntegerBinaryOperation
integer_binary (Add Int32Type) = Just AddInteger
integer_binary (Sub Int32Type) = Just SubtractInteger
integer_binary (Mul Int32Type) = Just MultiplyInteger
integer_binary _ = Nothing

private
underlying_name : Name -> Name
underlying_name (DN _ name) = underlying_name name
underlying_name name = name

private
is_checked_int32_less : Name -> Name -> Bool
is_checked_int32_less actual resolved_expected =
  underlying_name actual == underlying_name resolved_expected ||
  show actual == "Prelude.EqOrd.<" ||
  case actual of
    DN "Prelude.EqOrd.<" _ => True
    _ => False

private
lower_comparison :
  IntegerCondition -> Register -> Register -> Register -> LowerState -> LowerState
lower_comparison condition destination left right state =
  let (true_label, after_true_label) = fresh_label state
      (done_label, after_done_label) = fresh_label after_true_label
  in emit (Mark done_label)
       (emit (IntegerConstant destination 1)
         (emit (Mark true_label)
           (emit (Goto done_label)
             (emit (IntegerBranch condition left right true_label)
               (emit (IntegerConstant destination 0) after_done_label)))))

private
lower_primitive :
  Register -> PrimFn arity -> Vect arity AVar -> LowerState ->
  Either String LowerState
lower_primitive destination operation arguments state =
  case (operation, arguments) of
    (binary, [ALocal left_variable, ALocal right_variable]) => do
      left <- lookup_register "Int32 primitive left operand" left_variable state
      right <- lookup_register "Int32 primitive right operand" right_variable state
      case integer_binary binary of
        Just accepted =>
          Right (emit (IntegerBinary accepted destination left right) state)
        Nothing =>
          case integer_condition binary of
            Just accepted =>
              Right (lower_comparison accepted destination left right state)
            Nothing =>
              Left
                ("Unsupported checked primitive in DEX Int32 subset: " ++
                 show operation)
    _ =>
      Left
        ("DEX Int32 primitive operands must be two ANF locals, got " ++
         show operation)

mutual
  private
  lower_to : Register -> ANF -> LowerState -> Either String LowerState
  lower_to destination (AV _ (ALocal source_variable)) state = do
    source <- lookup_register "Copy" source_variable state
    if destination == source
      then Right state
      else Right (emit (Move destination source) state)
  lower_to destination (APrimVal _ (I32 value)) state =
    Right (emit (IntegerConstant destination (cast value)) state)
  lower_to destination (APrimVal _ (I value)) state =
    Left
      ("Idriç Int is 64-bit in the current compiler; the first DEX slice " ++
       "accepts Int32 (got literal " ++ show value ++ ")")
  lower_to destination (AOp _ _ operation arguments) state =
    lower_primitive destination operation arguments state
  lower_to destination (AAppName _ _ name [ALocal left_variable, ALocal right_variable]) state =
    if is_checked_int32_less name state.integer_less_name
      then do
        left <- lookup_register "Int32 < left operand" left_variable state
        right <- lookup_register "Int32 < right operand" right_variable state
        Right (lower_comparison LessThanInteger destination left right state)
      else
        Left
          ("Unsupported checked named call in DEX Int32 subset: " ++ show name)
  lower_to destination (ALet _ nested_destination value body) state = do
    target <- lookup_register "Let destination" nested_destination state
    after_value <- lower_to target value state
    lower_to destination body after_value
  lower_to destination (AConCase _ (ALocal scrutinee) alternatives fallback) state =
    lower_boolean_case destination scrutinee alternatives fallback state
  lower_to destination (AConstCase _ (ALocal scrutinee) alternatives fallback) state =
    lower_boolean_constant_case destination scrutinee alternatives fallback state
  lower_to destination expression state =
    Left ("Unsupported checked ANF in DEX Int32 subset: " ++ show expression)

  private
  lower_boolean_case :
    Register -> Int -> List AConAlt -> Maybe ANF -> LowerState ->
    Either String LowerState
  lower_boolean_case destination scrutinee_variable alternatives fallback state = do
    scrutinee <- lookup_register "Boolean case scrutinee" scrutinee_variable state
    false_body <- find_constructor_tag 0 alternatives fallback
    true_body <- find_constructor_tag 1 alternatives fallback
    let (false_label, after_false_label) = fresh_label state
    let (done_label, after_done_label) = fresh_label after_false_label
    let with_zero = emit (IntegerConstant destination 0) after_done_label
    let with_branch =
          emit (IntegerBranch EqualInteger scrutinee destination false_label) with_zero
    after_true <- lower_to destination true_body with_branch
    let with_goto = emit (Goto done_label) after_true
    let at_false = emit (Mark false_label) with_goto
    after_false <- lower_to destination false_body at_false
    Right (emit (Mark done_label) after_false)

  private
  lower_boolean_constant_case :
    Register -> Int -> List AConstAlt -> Maybe ANF -> LowerState ->
    Either String LowerState
  lower_boolean_constant_case destination scrutinee_variable alternatives fallback state = do
    scrutinee <- lookup_register "Boolean case scrutinee" scrutinee_variable state
    false_body <- find_constant_tag 0 alternatives fallback
    true_body <- find_constant_tag 1 alternatives fallback
    let (false_label, after_false_label) = fresh_label state
    let (done_label, after_done_label) = fresh_label after_false_label
    let with_zero = emit (IntegerConstant destination 0) after_done_label
    let with_branch =
          emit (IntegerBranch EqualInteger scrutinee destination false_label) with_zero
    after_true <- lower_to destination true_body with_branch
    let with_goto = emit (Goto done_label) after_true
    let at_false = emit (Mark false_label) with_goto
    after_false <- lower_to destination false_body at_false
    Right (emit (Mark done_label) after_false)

  private
  constant_tag : Constant -> Maybe Int
  constant_tag (I8 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (I16 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (I32 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (I64 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (I value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (BI value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (B8 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (B16 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (B32 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag (B64 value) = if value == 0 || value == 1 then Just (cast value) else Nothing
  constant_tag constant = Nothing

  private
  find_constant_tag :
    Int -> List AConstAlt -> Maybe ANF -> Either String ANF
  find_constant_tag requested [] Nothing =
    Left
      ("DEX Boolean constant case has no tag " ++ show requested ++
       " and no fallback")
  find_constant_tag requested [] (Just fallback) = Right fallback
  find_constant_tag requested (MkAConstAlt constant body :: rest) fallback =
    case constant_tag constant of
      Just tag =>
        if tag == requested
          then Right body
          else find_constant_tag requested rest fallback
      Nothing =>
        Left
          ("DEX Boolean case has a non-Boolean constant alternative: " ++
           show constant)

  private
  find_constructor_tag :
    Int -> List AConAlt -> Maybe ANF -> Either String ANF
  find_constructor_tag requested [] Nothing =
    Left
      ("DEX Boolean case has no constructor tag " ++ show requested ++
       " and no fallback")
  find_constructor_tag requested [] (Just fallback) = Right fallback
  find_constructor_tag requested
    (MkAConAlt _ _ (Just tag) arguments body :: rest) fallback =
      if tag == requested
        then if null arguments
          then Right body
          else Left "DEX Boolean alternatives must be nullary"
        else find_constructor_tag requested rest fallback
  find_constructor_tag requested (MkAConAlt name _ Nothing _ _ :: rest) fallback =
    Left "DEX Boolean alternative has no constructor tag"

private
finish_method : ANF -> LowerState -> Either String (List Instruction)
finish_method body state = do
  lowered <- lower_to state.result_register body state
  Right (reverse (ReturnInteger lowered.result_register :: lowered.instructions_reversed))

private
is_ascii_letter : Char -> Bool
is_ascii_letter character =
  (character >= 'A' && character <= 'Z') ||
  (character >= 'a' && character <= 'z')

private
is_ascii_digit : Char -> Bool
is_ascii_digit character = character >= '0' && character <= '9'

public export
validate_method_name : String -> Either String String
validate_method_name name =
  case unpack name of
    [] => Left "A DEX method name cannot be empty"
    first :: rest =>
      if (is_ascii_letter first || first == '_') &&
         all (\character =>
           is_ascii_letter character || is_ascii_digit character || character == '_') rest
        then Right name
        else Left ("Unsupported DEX method name `" ++ name ++ "`")

||| Lower an already checked ANF function. Idriç checking and source ABI
||| classification happen before this function; this pass owns only dense DEX
||| virtual-register placement and target instruction planning.
public export
lower_method : Name -> String -> String -> ANFDef -> Either String MethodPlan
lower_method integer_less_name source_name requested_method (MkAFun arguments body) = do
  method_name <- validate_method_name requested_method
  let discovered = collect_variables body
  let local_variables = filter (\variable => not (elem variable arguments)) discovered
  let local_registers = number_registers_from 0 local_variables
  let local_count : Int = cast (length local_variables)
  let result_register = MkRegister local_count
  let parameter_start = local_count + 1
  let argument_registers = number_registers_from parameter_start arguments
  let mapping = local_registers ++ argument_registers
  let parameter_count : Int = cast (length arguments)
  let register_count = parameter_start + parameter_count
  instructions <-
    finish_method body
      (MkLowerState integer_less_name mapping result_register 0 [])
  Right
    (MkMethodPlan source_name method_name parameter_count
      register_count instructions)
lower_method integer_less_name source_name requested_method definition =
  Left
    ("DEX export `" ++ source_name ++ "` is not a checked function: " ++
     show definition)
