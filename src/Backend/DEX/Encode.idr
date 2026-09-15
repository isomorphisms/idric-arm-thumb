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
instruction_width (Move destination source) =
  if not (valid_register 65535 destination && valid_register 65535 source)
    then Left ("DEX move register exceeds v65535")
    else if valid_register 15 destination && valid_register 15 source
      then Right 1
      else if valid_register 255 destination
        then Right 2
        else Right 3
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
encode_instruction :
  List (Label, Int) -> Int -> Instruction -> Either String (List Int)
encode_instruction labels address (Mark label) = Right []
encode_instruction labels address instruction@(IntegerConstant destination value) = do
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
encode_instruction labels address instruction@(Move destination source) = do
  width <- instruction_width instruction
  let destination_number : Integer = cast destination.number
  let source_number : Integer = cast source.number
  case width of
    1 =>
      Right
        (u16le (0x01 + destination_number * 256 + source_number * 4096))
    2 =>
      Right (u16le (0x02 + destination_number * 256) ++ u16le source_number)
    _ => Right (u16le 0x03 ++ u16le destination_number ++ u16le source_number)
encode_instruction labels address instruction@(IntegerBinary operation destination left right) = do
  _ <- instruction_width instruction
  Right
    (u16le (binary_opcode operation + cast destination.number * 256) ++
     u16le (cast left.number + cast right.number * 256))
encode_instruction labels address instruction@(IntegerBranch condition left right target) = do
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
encode_instruction labels address instruction@(Goto target) = do
  _ <- instruction_width instruction
  target_address <- find_label target labels
  let offset = target_address - address
  if offset == 0 || offset < -128 || offset > 127
    then
      Left
        ("First DEX goto format 10t offset is zero or out of range at code unit " ++
         show address ++ ": " ++ show offset)
    else Right (u16le (0x28 + unsigned_mod (cast offset) 256 * 256))
encode_instruction labels address instruction@(ReturnInteger register) = do
  _ <- instruction_width instruction
  Right (u16le (0x0f + cast register.number * 256))

private
encode_instruction_stream :
  List (Label, Int) -> Int -> List Instruction -> Either String (List Int)
encode_instruction_stream labels address [] = Right []
encode_instruction_stream labels address (instruction :: rest) = do
  encoded <- encode_instruction labels address instruction
  width <- instruction_width instruction
  more <- encode_instruction_stream labels (address + width) rest
  Right (encoded ++ more)

private
encode_instructions : List Instruction -> Either String (List Int)
encode_instructions instructions = do
  labels <- label_addresses instructions
  encode_instruction_stream labels 0 instructions

private
method_before : MethodPlan -> MethodPlan -> Bool
method_before left right =
  case compare left.method_name right.method_name of
    LT => True
    GT => False
    EQ => left.parameter_count <= right.parameter_count

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
         candidate.parameter_count == method.parameter_count) rest
    then Just
      (method.method_name ++ "/" ++ show method.parameter_count)
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
             ("First DEX encoder accepts non-NUL ASCII metadata only: " ++
              show character)

private
shorty : Int -> String
shorty parameter_count =
  "I" ++ pack (replicate (cast parameter_count) 'I')

private
lookup_index : Eq value => String -> value -> List value -> Either String Int
lookup_index role requested values = find_from 0 values
  where
    find_from : Int -> List value -> Either String Int
    find_from index [] = Left ("Missing " ++ role ++ " index")
    find_from index (candidate :: rest) =
      if requested == candidate then Right index else find_from (index + 1) rest

private
unique_arities : List MethodPlan -> List Int
unique_arities methods = sort (nub (map parameter_count methods))

private
all_strings : String -> List MethodPlan -> List Int -> List String
all_strings descriptor methods arities =
  sort
    (nub
      (["I", descriptor, "Ljava/lang/Object;"] ++
       map method_name methods ++ map shorty arities))

private
record TypeListLayout where
  constructor MkTypeListLayout
  bytes : List Int
  offsets : List (Int, Int)
  first_offset : Maybe Int
  next_offset : Int
  item_count : Int

private
layout_type_lists_from :
  Int -> Int -> List Int -> List Int -> List (Int, Int) -> Maybe Int -> Int ->
  TypeListLayout
layout_type_lists_from int_type_index current [] accumulated offsets first count =
  MkTypeListLayout accumulated offsets first current count
layout_type_lists_from int_type_index current (arity :: rest)
                       accumulated offsets first count =
  if arity == 0
    then
      layout_type_lists_from int_type_index current rest accumulated
        ((arity, 0) :: offsets) first count
    else
      let start = align_up current 4
          pad = padding current 4
          item =
            u32le (cast arity) ++
            concat (replicate (cast arity) (u16le (cast int_type_index)))
          next = start + cast (length item)
          next_first =
            case first of
              Nothing => Just start
              Just existing => Just existing
      in layout_type_lists_from int_type_index next rest
           (accumulated ++ pad ++ item) ((arity, start) :: offsets)
           next_first (count + 1)

private
layout_type_lists : Int -> Int -> List Int -> TypeListLayout
layout_type_lists int_type_index start arities =
  layout_type_lists_from int_type_index start arities [] [] Nothing 0

private
find_arity_offset : Int -> List (Int, Int) -> Either String Int
find_arity_offset requested [] = Left "Missing DEX prototype parameter list"
find_arity_offset requested ((arity, offset) :: rest) =
  if requested == arity then Right offset else find_arity_offset requested rest

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
  List Int -> Int -> List MethodPlan -> Either String (List PreparedMethod)
prepare_methods arities next_index [] = Right []
prepare_methods arities next_index (method :: rest) = do
  if method.parameter_count < 0 ||
     method.register_count < method.parameter_count ||
     method.register_count > 65535
    then Left ("Invalid DEX register/parameter counts for " ++ method.method_name)
    else Right ()
  prototype_index <- lookup_index "prototype" method.parameter_count arities
  bytes <- encode_instructions method.instructions
  more <- prepare_methods arities (next_index + 1) rest
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
  let arities = unique_arities methods
  let strings = all_strings file_plan.class_descriptor methods arities
  let string_ids_off = 112
  let type_ids_off = string_ids_off + 4 * cast (length strings)
  let proto_ids_off = type_ids_off + 12
  let method_ids_off = proto_ids_off + 12 * cast (length arities)
  let class_defs_off = method_ids_off + 8 * cast (length methods)
  let data_off = class_defs_off + 32
  int_string_index <- lookup_index "Int32 descriptor" "I" strings
  class_string_index <- lookup_index "generated class descriptor" file_plan.class_descriptor strings
  object_string_index <- lookup_index "Object descriptor" "Ljava/lang/Object;" strings
  let type_descriptor_indices = sort [int_string_index, class_string_index, object_string_index]
  int_type_index <- lookup_index "Int32 type" int_string_index type_descriptor_indices
  class_type_index <- lookup_index "generated class type" class_string_index type_descriptor_indices
  object_type_index <- lookup_index "Object type" object_string_index type_descriptor_indices
  let type_lists = layout_type_lists int_type_index data_off arities
  prepared <- prepare_methods arities 0 methods
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
  let type_id_bytes = map (\index => u32le (cast index)) type_descriptor_indices
  proto_id_bytes <-
    traverse
      (\arity => do shorty_index <- lookup_index "shorty" (shorty arity) strings
                    parameters_off <- find_arity_offset arity type_lists.offsets
                    Right
                      (u32le (cast shorty_index) ++ u32le (cast int_type_index) ++
                       u32le (cast parameters_off))) arities
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
        , map_item 0x0002 3 type_ids_off
        , map_item 0x0003 (cast (length arities)) proto_ids_off
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
        u32le 3 ++ u32le (cast type_ids_off) ++
        u32le (cast (length arities)) ++ u32le (cast proto_ids_off) ++
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
