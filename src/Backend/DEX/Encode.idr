module Backend.DEX.Encode

import Backend.DEX.Hash
import Backend.DEX.IR
import Data.Buffer
import Data.List
import Data.Maybe
import System.File

%default covering

private
signed32_min : Int
signed32_min = -2147483648

private
signed32_max : Int
signed32_max = 2147483647

private
valid_register : Int -> Register -> Bool
valid_register maximum register =
  register.number >= 0 && register.number <= maximum

private
unsigned_mod : Integer -> Integer -> Integer
unsigned_mod value modulus =
  let reduced = value `mod` modulus
  in if reduced < 0 then reduced + modulus else reduced

private
u16le : Integer -> List Int
u16le value =
  let encoded = unsigned_mod value 65536
  in [cast (encoded `mod` 256), cast ((encoded `div` 256) `mod` 256)]

private
u32le : Integer -> List Int
u32le value =
  let encoded = unsigned_mod value 4294967296
  in [ cast (encoded `mod` 256)
     , cast ((encoded `div` 256) `mod` 256)
     , cast ((encoded `div` 65536) `mod` 256)
     , cast ((encoded `div` 16777216) `mod` 256)
     ]

private
uleb128 : Integer -> List Int
uleb128 value =
  if value < 0
    then []
    else
      let byte = value `mod` 128
          rest = value `div` 128
      in if rest == 0
           then [cast byte]
           else cast (byte + 128) :: uleb128 rest

private
align_up : Int -> Int -> Int
align_up offset alignment =
  let remainder = offset `mod` alignment
  in if remainder == 0 then offset else offset + alignment - remainder

private
padding : Int -> Int -> List Int
padding offset alignment =
  replicate (cast (align_up offset alignment - offset)) 0

private
move_width : Register -> Register -> Either String Int
move_width destination source =
  if not (valid_register 65535 destination && valid_register 65535 source)
    then Left "DEX move register exceeds v65535"
    else if valid_register 15 destination && valid_register 15 source
      then Right 1
      else if valid_register 255 destination
        then Right 2
        else Right 3

private
instruction_width : Instruction -> Either String Int
instruction_width (Mark label) = Right 0
instruction_width (IntegerConstant destination value) =
  if not (valid_register 255 destination)
    then Left ("DEX const destination exceeds v255: " ++ show destination)
    else if value < signed32_min || value > signed32_max
      then Left ("DEX Int32 constant is out of range: " ++ show value)
      else if valid_register 15 destination && value >= -8 && value <= 7
        then Right 1
        else if value >= -32768 && value <= 32767
          then Right 2
          else Right 3
instruction_width (TextConstant destination value) =
  if valid_register 255 destination
    then Right 2
    else Left "DEX const-string requires a destination in v0..v255"
instruction_width (Move destination source) = move_width destination source
instruction_width (MoveObject destination source) = move_width destination source
instruction_width (IntegerBinary _ destination left right) =
  if valid_register 255 destination &&
     valid_register 255 left && valid_register 255 right
    then Right 2
    else Left "DEX format 23x Int32 arithmetic requires registers v0..v255"
instruction_width (IntegerBranch _ left right target) =
  if valid_register 15 left && valid_register 15 right
    then Right 2
    else Left "DEX format 22t integer branches require registers v0..v15"
instruction_width (Goto target) = Right 1
instruction_width (ReturnInteger register) =
  if valid_register 255 register
    then Right 1
    else Left "DEX return requires a register in v0..v255"
instruction_width (ReturnObject register) =
  if valid_register 255 register
    then Right 1
    else Left "DEX return-object requires a register in v0..v255"

private
find_label : Label -> List (Label, Int) -> Either String Int
find_label requested [] = Left ("Undefined DEX label " ++ show requested)
find_label requested ((label, address) :: rest) =
  if requested == label then Right address else find_label requested rest

private
label_addresses_from :
  Int -> List (Label, Int) -> List Instruction ->
  Either String (List (Label, Int))
label_addresses_from address labels [] = Right labels
label_addresses_from address labels (Mark label :: rest) =
  if elem label (map fst labels)
    then Left ("Duplicate DEX label " ++ show label)
    else label_addresses_from address ((label, address) :: labels) rest
label_addresses_from address labels (instruction :: rest) = do
  width <- instruction_width instruction
  label_addresses_from (address + width) labels rest

private
label_addresses : List Instruction -> Either String (List (Label, Int))
label_addresses = label_addresses_from 0 []

private
binary_opcode : IntegerBinaryOperation -> Integer
binary_opcode AddInteger = 0x90
binary_opcode SubtractInteger = 0x91
binary_opcode MultiplyInteger = 0x92

private
branch_opcode : IntegerCondition -> Integer
branch_opcode EqualInteger = 0x32
branch_opcode NotEqualInteger = 0x33
branch_opcode LessThanInteger = 0x34
branch_opcode GreaterEqualInteger = 0x35
branch_opcode GreaterThanInteger = 0x36
branch_opcode LessEqualInteger = 0x37

private
lookup_index : Eq value => String -> value -> List value -> Either String Int
lookup_index role requested values = find_from 0 values
  where
    find_from : Int -> List value -> Either String Int
    find_from index [] = Left ("Missing " ++ role ++ " index")
    find_from index (candidate :: rest) =
      if requested == candidate then Right index else find_from (index + 1) rest

private
encode_move : Integer -> Integer -> Integer -> Register -> Register -> Either String (List Int)
encode_move narrow_opcode from16_opcode wide_opcode destination source = do
  width <- move_width destination source
  let destination_number : Integer = cast destination.number
  let source_number : Integer = cast source.number
  case width of
    1 =>
      Right
        (u16le
          (narrow_opcode + destination_number * 256 + source_number * 4096))
    2 =>
      Right
        (u16le (from16_opcode + destination_number * 256) ++
         u16le source_number)
    _ =>
      Right
        (u16le wide_opcode ++ u16le destination_number ++ u16le source_number)

private
encode_instruction :
  List String -> List (Label, Int) -> Int -> Instruction ->
  Either String (List Int)
encode_instruction strings labels address (Mark label) = Right []
encode_instruction strings labels address instruction@(IntegerConstant destination value) = do
  width <- instruction_width instruction
  let register = cast destination.number
  let literal : Integer = cast value
  case width of
    1 =>
      Right
        (u16le
          (0x12 + register * 256 + unsigned_mod literal 16 * 4096))
    2 => Right (u16le (0x13 + register * 256) ++ u16le literal)
    _ => Right (u16le (0x14 + register * 256) ++ u32le literal)
encode_instruction strings labels address instruction@(TextConstant destination value) = do
  _ <- instruction_width instruction
  string_index <- lookup_index "const-string" value strings
  if string_index > 65535
    then Left "DEX const-string/jumbo is not implemented in the checked Text slice"
    else
      Right
        (u16le (0x1a + cast destination.number * 256) ++
         u16le (cast string_index))
encode_instruction strings labels address (Move destination source) =
  encode_move 0x01 0x02 0x03 destination source
encode_instruction strings labels address (MoveObject destination source) =
  encode_move 0x07 0x08 0x09 destination source
encode_instruction strings labels address instruction@(IntegerBinary operation destination left right) = do
  _ <- instruction_width instruction
  Right
    (u16le (binary_opcode operation + cast destination.number * 256) ++
     u16le (cast left.number + cast right.number * 256))
encode_instruction strings labels address instruction@(IntegerBranch condition left right target) = do
  _ <- instruction_width instruction
  target_address <- find_label target labels
  let offset = target_address - address
  if offset == 0 || offset < -32768 || offset > 32767
    then
      Left
        ("DEX format 22t branch offset is zero or out of range at code unit " ++
         show address ++ ": " ++ show offset)
    else
      Right
        (u16le
          (branch_opcode condition + cast left.number * 256 +
           cast right.number * 4096) ++
         u16le (cast offset))
encode_instruction strings labels address instruction@(Goto target) = do
  _ <- instruction_width instruction
  target_address <- find_label target labels
  let offset = target_address - address
  if offset == 0 || offset < -128 || offset > 127
    then
      Left
        ("First DEX goto format 10t offset is zero or out of range at code unit " ++
         show address ++ ": " ++ show offset)
    else Right (u16le (0x28 + unsigned_mod (cast offset) 256 * 256))
encode_instruction strings labels address instruction@(ReturnInteger register) = do
  _ <- instruction_width instruction
  Right (u16le (0x0f + cast register.number * 256))
encode_instruction strings labels address instruction@(ReturnObject register) = do
  _ <- instruction_width instruction
  Right (u16le (0x11 + cast register.number * 256))

private
encode_instruction_stream :
  List String -> List (Label, Int) -> Int -> List Instruction ->
  Either String (List Int)
encode_instruction_stream strings labels address [] = Right []
encode_instruction_stream strings labels address (instruction :: rest) = do
  encoded <- encode_instruction strings labels address instruction
  width <- instruction_width instruction
  more <- encode_instruction_stream strings labels (address + width) rest
  Right (encoded ++ more)

private
encode_instructions : List String -> List Instruction -> Either String (List Int)
encode_instructions strings instructions = do
  labels <- label_addresses instructions
  encode_instruction_stream strings labels 0 instructions

private
record Prototype where
  constructor MkPrototype
  parameter_types : List ValueType
  result_type : ValueType

private
Eq Prototype where
  left == right =
    left.parameter_types == right.parameter_types &&
    left.result_type == right.result_type

private
prototype_of : MethodPlan -> Prototype
prototype_of method = MkPrototype method.parameter_types method.result_type

private
compare_descriptors : List String -> List String -> Ordering
compare_descriptors [] [] = EQ
compare_descriptors [] (_ :: _) = LT
compare_descriptors (_ :: _) [] = GT
compare_descriptors (left :: left_rest) (right :: right_rest) =
  case compare left right of
    EQ => compare_descriptors left_rest right_rest
    ordering => ordering

private
compare_prototype : Prototype -> Prototype -> Ordering
compare_prototype left right =
  case compare
    (value_descriptor left.result_type)
    (value_descriptor right.result_type) of
      EQ =>
        compare_descriptors
          (map value_descriptor left.parameter_types)
          (map value_descriptor right.parameter_types)
      ordering => ordering

private
insert_prototype : Prototype -> List Prototype -> List Prototype
insert_prototype prototype [] = [prototype]
insert_prototype prototype (candidate :: rest) =
  case compare_prototype prototype candidate of
    LT => prototype :: candidate :: rest
    EQ => candidate :: rest
    GT => candidate :: insert_prototype prototype rest

private
unique_prototypes : List MethodPlan -> List Prototype
unique_prototypes methods =
  foldr (\method, values => insert_prototype (prototype_of method) values) [] methods

private
method_before : MethodPlan -> MethodPlan -> Bool
method_before left right =
  case compare left.method_name right.method_name of
    LT => True
    GT => False
    EQ => compare_prototype (prototype_of left) (prototype_of right) /= GT

private
insert_method : MethodPlan -> List MethodPlan -> List MethodPlan
insert_method method [] = [method]
insert_method method (candidate :: rest) =
  if method_before method candidate
    then method :: candidate :: rest
    else candidate :: insert_method method rest

private
sort_methods : List MethodPlan -> List MethodPlan
sort_methods = foldr insert_method []

private
find_duplicate_method : List MethodPlan -> Maybe String
find_duplicate_method [] = Nothing
find_duplicate_method (method :: rest) =
  if any
       (\candidate =>
         candidate.method_name == method.method_name &&
         prototype_of candidate == prototype_of method) rest
    then Just method.method_name
    else find_duplicate_method rest

private
ascii_bytes : String -> Either String (List Int)
ascii_bytes value = traverse encode_character (unpack value)
  where
    encode_character : Char -> Either String Int
    encode_character character =
      let code = ord character
      in if code >= 1 && code <= 127
           then Right code
           else Left
             ("Checked DEX metadata/Text constants currently admit non-NUL ASCII only: " ++
              show character)

private
shorty : Prototype -> String
shorty prototype =
  pack
    (shorty_character prototype.result_type ::
     map shorty_character prototype.parameter_types)

private
instruction_texts : Instruction -> List String
instruction_texts (TextConstant destination value) = [value]
instruction_texts instruction = []

private
method_texts : MethodPlan -> List String
method_texts method = concat (map instruction_texts method.instructions)

private
type_descriptors : String -> List MethodPlan -> List String
type_descriptors class_descriptor methods =
  sort
    (nub
      ([class_descriptor, "Ljava/lang/Object;"] ++
       concat
         (map
           (\method =>
             value_descriptor method.result_type ::
             map value_descriptor method.parameter_types)
           methods)))

private
all_strings :
  String -> List MethodPlan -> List Prototype -> List String -> List String
all_strings descriptor methods prototypes descriptors =
  sort
    (nub
      (descriptors ++
       map method_name methods ++
       map shorty prototypes ++
       concat (map method_texts methods)))

private
record TypeListLayout where
  constructor MkTypeListLayout
  bytes : List Int
  offsets : List (Prototype, Int)
  first_offset : Maybe Int
  next_offset : Int
  item_count : Int

private
encode_parameter_types :
  List String -> List ValueType -> Either String (List Int)
encode_parameter_types descriptors [] = Right []
encode_parameter_types descriptors (value_type :: rest) = do
  type_index <-
    lookup_index "parameter type" (value_descriptor value_type) descriptors
  more <- encode_parameter_types descriptors rest
  Right (u16le (cast type_index) ++ more)

private
layout_type_lists_from :
  List String -> Int -> List Prototype -> List Int ->
  List (Prototype, Int) -> Maybe Int -> Int -> Either String TypeListLayout
layout_type_lists_from descriptors current [] accumulated offsets first count =
  Right (MkTypeListLayout accumulated offsets first current count)
layout_type_lists_from descriptors current (prototype :: rest)
                       accumulated offsets first count =
  if null prototype.parameter_types
    then
      layout_type_lists_from descriptors current rest accumulated
        ((prototype, 0) :: offsets) first count
    else do
      encoded_types <- encode_parameter_types descriptors prototype.parameter_types
      let start = align_up current 4
      let pad = padding current 4
      let item =
            u32le (cast (length prototype.parameter_types)) ++ encoded_types
      let next = start + cast (length item)
      let next_first =
            case first of
              Nothing => Just start
              Just existing => Just existing
      layout_type_lists_from descriptors next rest
        (accumulated ++ pad ++ item) ((prototype, start) :: offsets)
        next_first (count + 1)

private
layout_type_lists :
  List String -> Int -> List Prototype -> Either String TypeListLayout
layout_type_lists descriptors start prototypes =
  layout_type_lists_from descriptors start prototypes [] [] Nothing 0

private
find_prototype_offset :
  Prototype -> List (Prototype, Int) -> Either String Int
find_prototype_offset requested [] = Left "Missing DEX prototype parameter list"
find_prototype_offset requested ((prototype, offset) :: rest) =
  if requested == prototype
    then Right offset
    else find_prototype_offset requested rest

private
record PreparedMethod where
  constructor MkPreparedMethod
  plan : MethodPlan
  method_index : Int
  prototype_index : Int
  instruction_bytes : List Int
  instruction_units : Int
  code_offset : Int

private
prepare_methods :
  List String -> List Prototype -> Int -> List MethodPlan ->
  Either String (List PreparedMethod)
prepare_methods strings prototypes next_index [] = Right []
prepare_methods strings prototypes next_index (method :: rest) = do
  if method.parameter_count < 0 ||
     method.parameter_count /= cast (length method.parameter_types) ||
     method.register_count < method.parameter_count ||
     method.register_count > 65535
    then Left ("Invalid DEX register/parameter counts for " ++ method.method_name)
    else Right ()
  prototype_index <- lookup_index "prototype" (prototype_of method) prototypes
  bytes <- encode_instructions strings method.instructions
  more <- prepare_methods strings prototypes (next_index + 1) rest
  Right
    (MkPreparedMethod method next_index prototype_index bytes
      (cast (length bytes) `div` 2) 0 :: more)

private
record CodeLayout where
  constructor MkCodeLayout
  bytes : List Int
  methods : List PreparedMethod
  first_offset : Int
  next_offset : Int

private
layout_code_from :
  Int -> List PreparedMethod -> List Int -> List PreparedMethod -> Maybe Int ->
  CodeLayout
layout_code_from current [] accumulated laid_out first =
  MkCodeLayout accumulated laid_out (fromMaybe current first) current
layout_code_from current (method :: rest) accumulated laid_out first =
  let start = align_up current 4
      pad = padding current 4
      header =
        u16le (cast method.plan.register_count) ++
        u16le (cast method.plan.parameter_count) ++
        u16le 0 ++ u16le 0 ++ u32le 0 ++
        u32le (cast method.instruction_units)
      item = header ++ method.instruction_bytes
      placed = { code_offset := start } method
      next_first =
        case first of
          Nothing => Just start
          Just existing => Just existing
  in layout_code_from (start + cast (length item)) rest
       (accumulated ++ pad ++ item) (laid_out ++ [placed]) next_first

private
layout_code : Int -> List PreparedMethod -> CodeLayout
layout_code start methods = layout_code_from start methods [] [] Nothing

private
record StringLayout where
  constructor MkStringLayout
  bytes : List Int
  offsets : List (String, Int)
  first_offset : Int
  next_offset : Int

private
layout_strings_from :
  Int -> List String -> List Int -> List (String, Int) -> Maybe Int ->
  Either String StringLayout
layout_strings_from current [] accumulated offsets first =
  Right (MkStringLayout accumulated offsets (fromMaybe current first) current)
layout_strings_from current (value :: rest) accumulated offsets first = do
  encoded <- ascii_bytes value
  let item = uleb128 (cast (length (unpack value))) ++ encoded ++ [0]
  let next_first =
        case first of
          Nothing => Just current
          Just existing => Just existing
  layout_strings_from (current + cast (length item)) rest
    (accumulated ++ item) (offsets ++ [(value, current)]) next_first

private
layout_strings : Int -> List String -> Either String StringLayout
layout_strings start strings = layout_strings_from start strings [] [] Nothing

private
find_string_offset : String -> List (String, Int) -> Either String Int
find_string_offset requested [] = Left ("Missing DEX string data for " ++ requested)
find_string_offset requested ((value, offset) :: rest) =
  if requested == value then Right offset else find_string_offset requested rest

private
encode_class_methods : Int -> List PreparedMethod -> List Int
encode_class_methods previous [] = []
encode_class_methods previous (method :: rest) =
  uleb128 (cast (method.method_index - previous)) ++
  uleb128 9 ++ uleb128 (cast method.code_offset) ++
  encode_class_methods method.method_index rest

private
class_data : List PreparedMethod -> List Int
class_data methods =
  uleb128 0 ++ uleb128 0 ++ uleb128 (cast (length methods)) ++ uleb128 0 ++
  encode_class_methods 0 methods

private
map_item : Integer -> Int -> Int -> List Int
map_item item_type count offset =
  u16le item_type ++ u16le 0 ++ u32le (cast count) ++ u32le (cast offset)

private
replace_range : Int -> List Int -> List Int -> List Int
replace_range offset replacement bytes =
  take (cast offset) bytes ++ replacement ++
  drop (cast (offset + cast (length replacement))) bytes

private
validate_class_descriptor : String -> Either String ()
validate_class_descriptor descriptor =
  case unpack descriptor of
    'L' :: rest =>
      case reverse rest of
        ';' :: middle =>
          if not (null middle) &&
             all
               (\character =>
                 (character >= 'A' && character <= 'Z') ||
                 (character >= 'a' && character <= 'z') ||
                 (character >= '0' && character <= '9') ||
                 character == '/' || character == '_' || character == '$') middle
            then Right ()
            else Left ("Unsupported DEX class descriptor `" ++ descriptor ++ "`")
        _ => Left ("Invalid DEX class descriptor `" ++ descriptor ++ "`")
    _ => Left ("Invalid DEX class descriptor `" ++ descriptor ++ "`")

private
prototype_bytes :
  List String -> List String -> TypeListLayout -> Prototype ->
  Either String (List Int)
prototype_bytes strings descriptors type_lists prototype = do
  shorty_index <- lookup_index "shorty" (shorty prototype) strings
  return_type_index <-
    lookup_index "return type" (value_descriptor prototype.result_type) descriptors
  parameters_off <- find_prototype_offset prototype type_lists.offsets
  Right
    (u32le (cast shorty_index) ++ u32le (cast return_type_index) ++
     u32le (cast parameters_off))

||| Encode a deliberately small but structurally complete DEX 035 file.
||| The result owns its header, identifiers, class/method/code/data items,
||| map, SHA-1 signature, and Adler-32 checksum directly.
public export
encode_dex : FilePlan -> Either String (List Int)
encode_dex file_plan = do
  validate_class_descriptor file_plan.class_descriptor
  if null file_plan.methods
    then Left "A DEX file must contain at least one checked Idriç method"
    else Right ()
  let methods = sort_methods file_plan.methods
  case find_duplicate_method methods of
    Just duplicate => Left ("Duplicate DEX method signature " ++ duplicate)
    Nothing => Right ()
  let prototypes = unique_prototypes methods
  let descriptors = type_descriptors file_plan.class_descriptor methods
  let strings = all_strings file_plan.class_descriptor methods prototypes descriptors
  let string_ids_off = 112
  let type_ids_off = string_ids_off + 4 * cast (length strings)
  let proto_ids_off = type_ids_off + 4 * cast (length descriptors)
  let method_ids_off = proto_ids_off + 12 * cast (length prototypes)
  let class_defs_off = method_ids_off + 8 * cast (length methods)
  let data_off = class_defs_off + 32
  class_type_index <-
    lookup_index "generated class type" file_plan.class_descriptor descriptors
  object_type_index <-
    lookup_index "Object type" "Ljava/lang/Object;" descriptors
  type_lists <- layout_type_lists descriptors data_off prototypes
  prepared <- prepare_methods strings prototypes 0 methods
  let code = layout_code type_lists.next_offset prepared
  strings_layout <- layout_strings code.next_offset strings
  let class_data_bytes = class_data code.methods
  let class_data_off = strings_layout.next_offset
  let before_map = class_data_off + cast (length class_data_bytes)
  let map_off = align_up before_map 4
  let has_type_lists = type_lists.item_count > 0
  let map_count = if has_type_lists then 11 else 10
  let file_size = map_off + 4 + 12 * map_count
  let data_size = file_size - data_off
  string_id_bytes <-
    traverse
      (\value => do offset <- find_string_offset value strings_layout.offsets
                    Right (u32le (cast offset))) strings
  type_id_bytes <-
    traverse
      (\descriptor => do index <- lookup_index "type descriptor" descriptor strings
                         Right (u32le (cast index))) descriptors
  proto_id_bytes <-
    traverse (prototype_bytes strings descriptors type_lists) prototypes
  method_id_bytes <-
    traverse
      (\method => do name_index <- lookup_index "method name" method.plan.method_name strings
                     Right
                       (u16le (cast class_type_index) ++
                        u16le (cast method.prototype_index) ++
                        u32le (cast name_index))) code.methods
  let class_def_bytes =
        u32le (cast class_type_index) ++ u32le 0x11 ++
        u32le (cast object_type_index) ++ u32le 0 ++
        u32le 0xffffffff ++ u32le 0 ++ u32le (cast class_data_off) ++ u32le 0
  let map_entries_before_optional =
        [ map_item 0x0000 1 0
        , map_item 0x0001 (cast (length strings)) string_ids_off
        , map_item 0x0002 (cast (length descriptors)) type_ids_off
        , map_item 0x0003 (cast (length prototypes)) proto_ids_off
        , map_item 0x0005 (cast (length methods)) method_ids_off
        , map_item 0x0006 1 class_defs_off
        ]
  let type_list_map =
        case type_lists.first_offset of
          Nothing => []
          Just offset => [map_item 0x1001 type_lists.item_count offset]
  let map_entries =
        map_entries_before_optional ++ type_list_map ++
        [ map_item 0x2001 (cast (length methods)) code.first_offset
        , map_item 0x2002 (cast (length strings)) strings_layout.first_offset
        , map_item 0x2000 1 class_data_off
        , map_item 0x1000 1 map_off
        ]
  let map_bytes = u32le (cast map_count) ++ concat map_entries
  let header =
        [100, 101, 120, 10, 48, 51, 53, 0] ++
        replicate 4 0 ++ replicate 20 0 ++
        u32le (cast file_size) ++ u32le 112 ++ u32le 0x12345678 ++
        u32le 0 ++ u32le 0 ++ u32le (cast map_off) ++
        u32le (cast (length strings)) ++ u32le (cast string_ids_off) ++
        u32le (cast (length descriptors)) ++ u32le (cast type_ids_off) ++
        u32le (cast (length prototypes)) ++ u32le (cast proto_ids_off) ++
        u32le 0 ++ u32le 0 ++
        u32le (cast (length methods)) ++ u32le (cast method_ids_off) ++
        u32le 1 ++ u32le (cast class_defs_off) ++
        u32le (cast data_size) ++ u32le (cast data_off)
  let unsigned_file =
        header ++ concat string_id_bytes ++ concat type_id_bytes ++
        concat proto_id_bytes ++ concat method_id_bytes ++ class_def_bytes ++
        type_lists.bytes ++ code.bytes ++ strings_layout.bytes ++
        class_data_bytes ++ padding before_map 4 ++ map_bytes
  if cast (length unsigned_file) /= file_size
    then
      Left
        ("Internal DEX layout mismatch: planned " ++ show file_size ++
         " bytes, encoded " ++ show (length unsigned_file))
    else Right ()
  let signature = sha1 (drop 32 unsigned_file)
  if length signature /= 20
    then Left "Internal SHA-1 implementation did not return 20 bytes"
    else Right ()
  let signed_file = replace_range 12 signature unsigned_file
  let checksum = adler32 (drop 12 signed_file)
  Right (replace_range 8 (u32le checksum) signed_file)

private
fill_buffer : Buffer -> Int -> List Int -> IO ()
fill_buffer buffer offset [] = pure ()
fill_buffer buffer offset (byte :: rest) = do
  setBits8 buffer offset (cast byte)
  fill_buffer buffer (offset + 1) rest

||| Persist an already encoded candidate artifact without invoking smali, d8,
||| javac, RefC, or a native backend.
public export
write_dex : String -> List Int -> IO (Either String ())
write_dex path bytes = do
  Just buffer <- newBuffer (cast (length bytes))
    | Nothing => pure (Left "Could not allocate DEX output buffer")
  fill_buffer buffer 0 bytes
  result <- writeBufferToFile path buffer (cast (length bytes))
  case result of
    Left error => pure (Left (show error))
    Right () => pure (Right ())
