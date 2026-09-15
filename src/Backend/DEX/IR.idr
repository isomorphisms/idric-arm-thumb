module Backend.DEX.IR

import Data.String

%default total

||| A DEX virtual register. This is target placement, not an Idriç type.
public export
record Register where
  constructor MkRegister
  number : Int

public export
Eq Register where
  (MkRegister left) == (MkRegister right) = left == right

public export
Show Register where
  show register = "v" ++ show register.number

||| A symbolic code address resolved only after instruction-width selection.
public export
record Label where
  constructor MkLabel
  number : Int

public export
Eq Label where
  (MkLabel left) == (MkLabel right) = left == right

public export
Show Label where
  show label = ":label_" ++ show label.number

||| The first source-level value classes admitted at a DEX method boundary.
||| Text is an ART object reference; Int32 remains a one-register primitive.
public export
data ValueType
  = IntegerValue
  | TextValue

public export
Eq ValueType where
  IntegerValue == IntegerValue = True
  TextValue == TextValue = True
  _ == _ = False

public export
Show ValueType where
  show IntegerValue = "Int32"
  show TextValue = "Text"

public export
value_descriptor : ValueType -> String
value_descriptor IntegerValue = "I"
value_descriptor TextValue = "Ljava/lang/String;"

public export
shorty_character : ValueType -> Char
shorty_character IntegerValue = 'I'
shorty_character TextValue = 'L'

public export
data IntegerBinaryOperation
  = AddInteger
  | SubtractInteger
  | MultiplyInteger

public export
Show IntegerBinaryOperation where
  show AddInteger = "add-int"
  show SubtractInteger = "sub-int"
  show MultiplyInteger = "mul-int"

public export
data IntegerCondition
  = EqualInteger
  | NotEqualInteger
  | LessThanInteger
  | GreaterEqualInteger
  | GreaterThanInteger
  | LessEqualInteger

public export
Show IntegerCondition where
  show EqualInteger = "if-eq"
  show NotEqualInteger = "if-ne"
  show LessThanInteger = "if-lt"
  show GreaterEqualInteger = "if-ge"
  show GreaterThanInteger = "if-gt"
  show LessEqualInteger = "if-le"

||| Typed DEX planning instructions. Object/reference operations remain
||| separate from integer operations so the encoder cannot silently use the
||| wrong DEX register opcode family.
public export
data Instruction
  = Move Register Register
  | MoveObject Register Register
  | IntegerConstant Register Int
  | TextConstant Register String
  | IntegerBinary IntegerBinaryOperation Register Register Register
  | IntegerBranch IntegerCondition Register Register Label
  | Goto Label
  | Mark Label
  | ReturnInteger Register
  | ReturnObject Register

public export
Show Instruction where
  show (Move destination source) =
    "move " ++ show destination ++ ", " ++ show source
  show (MoveObject destination source) =
    "move-object " ++ show destination ++ ", " ++ show source
  show (IntegerConstant destination value) =
    "const " ++ show destination ++ ", " ++ show value
  show (TextConstant destination value) =
    "const-string " ++ show destination ++ ", " ++ show value
  show (IntegerBinary operation destination left right) =
    show operation ++ " " ++ show destination ++ ", " ++
    show left ++ ", " ++ show right
  show (IntegerBranch condition left right target) =
    show condition ++ " " ++ show left ++ ", " ++
    show right ++ ", " ++ show target
  show (Goto target) = "goto " ++ show target
  show (Mark label) = show label
  show (ReturnInteger register) = "return " ++ show register
  show (ReturnObject register) = "return-object " ++ show register

||| One checked Idriç export after deterministic DEX register placement.
public export
record MethodPlan where
  constructor MkMethodPlan
  source_name : String
  method_name : String
  parameter_count : Int
  parameter_types : List ValueType
  result_type : ValueType
  register_count : Int
  instructions : List Instruction

public export
render_method_plan : MethodPlan -> String
render_method_plan method =
  unlines
    ([ "method " ++ method.method_name
     , "source: " ++ method.source_name
     , "parameters: " ++ show method.parameter_types
     , "result: " ++ show method.result_type
     , "registers: " ++ show method.register_count
     ] ++ map (\instruction => "  " ++ show instruction) method.instructions)

||| A single generated utility class. The generic backend still owns no
||| Android UI, resource, manifest, or packaging semantics.
public export
record FilePlan where
  constructor MkFilePlan
  class_descriptor : String
  methods : List MethodPlan

public export
render_file_plan : FilePlan -> String
render_file_plan plan =
  "class " ++ plan.class_descriptor ++ "\n\n" ++
  concat (intersperse "\n" (map render_method_plan plan.methods))
