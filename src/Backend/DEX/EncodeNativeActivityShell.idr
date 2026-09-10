module Backend.DEX.EncodeNativeActivityShell

import Backend.DEX.Encode
import Backend.DEX.Hash
import Data.List
import Data.Maybe

%default covering

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
replace_range : Int -> List Int -> List Int -> List Int
replace_range offset replacement bytes =
  take (cast offset) bytes ++ replacement ++
  drop (cast (offset + cast (length replacement))) bytes

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
             ("NativeActivity DEX metadata must be non-NUL ASCII: " ++
              show character)

private
valid_activity_descriptor : String -> Bool
valid_activity_descriptor descriptor =
  isPrefixOf (unpack "Lorg/") (unpack descriptor) &&
  isSuffixOf (unpack ";") (unpack descriptor)

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
layout_strings start values =
  layout_strings_from start values [] [] Nothing

private
find_string_offset : String -> List (String, Int) -> Either String Int
find_string_offset requested [] =
  Left ("Missing NativeActivity DEX string data for " ++ requested)
find_string_offset requested ((value, offset) :: rest) =
  if requested == value
    then Right offset
    else find_string_offset requested rest

private
map_item : Integer -> Int -> Int -> List Int
map_item item_type count offset =
  u16le item_type ++ u16le 0 ++ u32le (cast count) ++ u32le (cast offset)

private
code_item : Int -> Int -> Int -> List Int -> List Int
code_item registers incoming outgoing instructions =
  u16le (cast registers) ++
  u16le (cast incoming) ++
  u16le (cast outgoing) ++
  u16le 0 ++
  u32le 0 ++
  u32le (cast (length instructions) `div` 2) ++
  instructions

private
shell_strings : String -> List String
shell_strings activity_descriptor =
  [ "<init>"
  , "Landroid/app/NativeActivity;"
  , "Landroid/os/Bundle;"
  , activity_descriptor
  , "V"
  , "VL"
  , "onCreate"
  ]

||| Encode the smallest ordinary Android class shell needed to host a native
||| application whose library is selected by android.app.lib_name in the
||| manifest.
|||
||| The encoded class:
|||   * is an Lorg/...; class extending android.app.NativeActivity;
|||   * has a public constructor delegating to NativeActivity.<init>;
|||   * overrides onCreate(Bundle) only to delegate to NativeActivity.onCreate.
|||
||| Library loading remains Android NativeActivity's manifest-defined job.
||| There is no Java source, javac, Kotlin compiler, Gradle, d8, smali, JNI
||| probe, or application-specific rendering code in this shell.
|||
||| The initial bounded encoder deliberately accepts Lorg/...; descriptors so
||| the fixed DEX string/type ordering below remains checked and explicit.
public export
encode_native_activity_shell_dex : String -> Either String (List Int)
encode_native_activity_shell_dex activity_descriptor = do
  if valid_activity_descriptor activity_descriptor
    then Right ()
    else Left
      ("NativeActivity shell requires an Lorg/...; descriptor, got " ++
       activity_descriptor)

  let strings = shell_strings activity_descriptor
  let string_ids_off = 112
  let type_ids_off = string_ids_off + 4 * cast (length strings)
  let proto_ids_off = type_ids_off + 4 * 4
  let method_ids_off = proto_ids_off + 12 * 2
  let class_defs_off = method_ids_off + 8 * 4
  let data_off = class_defs_off + 32

  -- One parameter list is needed for onCreate(Bundle).
  let bundle_type_list = u32le 1 ++ u16le 1
  let bundle_type_list_off = data_off
  let after_type_lists = data_off + cast (length bundle_type_list)

  -- Method ids are fixed by DEX sorting:
  -- 0 NativeActivity.<init>()V
  -- 1 NativeActivity.onCreate(Bundle)V
  -- 2 AppActivity.<init>()V
  -- 3 AppActivity.onCreate(Bundle)V
  let init_instructions =
        u16le 0x1070 ++ u16le 0 ++ u16le 0 ++
        u16le 0x000e
  let oncreate_instructions =
        u16le 0x206f ++ u16le 1 ++ u16le 0x0010 ++
        u16le 0x000e
  let init_code = code_item 1 1 1 init_instructions
  let oncreate_code = code_item 2 2 2 oncreate_instructions

  let init_code_off = align_up after_type_lists 4
  let after_init = init_code_off + cast (length init_code)
  let oncreate_code_off = align_up after_init 4
  let after_oncreate = oncreate_code_off + cast (length oncreate_code)
  let code_bytes =
        padding after_type_lists 4 ++ init_code ++
        padding after_init 4 ++ oncreate_code

  strings_layout <- layout_strings after_oncreate strings

  let class_data_bytes =
        uleb128 0 ++ uleb128 0 ++ uleb128 1 ++ uleb128 1 ++
        -- direct methods: constructor (absolute method id 2)
        uleb128 2 ++ uleb128 0x10001 ++ uleb128 (cast init_code_off) ++
        -- virtual methods: onCreate (absolute method id 3)
        uleb128 3 ++ uleb128 0x4 ++ uleb128 (cast oncreate_code_off)
  let class_data_off = strings_layout.next_offset
  let before_map = class_data_off + cast (length class_data_bytes)
  let map_off = align_up before_map 4
  let map_count = 11
  let map_bytes =
        u32le (cast map_count) ++ concat
          [ map_item 0x0000 1 0
          , map_item 0x0001 (cast (length strings)) string_ids_off
          , map_item 0x0002 4 type_ids_off
          , map_item 0x0003 2 proto_ids_off
          , map_item 0x0005 4 method_ids_off
          , map_item 0x0006 1 class_defs_off
          , map_item 0x1001 1 bundle_type_list_off
          , map_item 0x2001 2 init_code_off
          , map_item 0x2002 (cast (length strings)) strings_layout.first_offset
          , map_item 0x2000 1 class_data_off
          , map_item 0x1000 1 map_off
          ]
  let file_size = map_off + cast (length map_bytes)
  let data_size = file_size - data_off

  string_id_bytes <-
    traverse
      (\value => do
        offset <- find_string_offset value strings_layout.offsets
        Right (u32le (cast offset)))
      strings

  -- type_ids are sorted by descriptor string index:
  -- NativeActivity, Bundle, AppActivity, V.
  let type_id_bytes = map u32le [1, 2, 3, 4]

  -- proto_ids: ()V and (Bundle)V.
  let proto_id_bytes =
        [ u32le 4 ++ u32le 3 ++ u32le 0
        , u32le 5 ++ u32le 3 ++ u32le (cast bundle_type_list_off)
        ]

  let method_id_bytes =
        [ u16le 0 ++ u16le 0 ++ u32le 0
        , u16le 0 ++ u16le 1 ++ u32le 6
        , u16le 2 ++ u16le 0 ++ u32le 0
        , u16le 2 ++ u16le 1 ++ u32le 6
        ]

  let class_def_bytes =
        u32le 2 ++ u32le 0x1 ++
        u32le 0 ++ u32le 0 ++
        u32le 0xffffffff ++ u32le 0 ++
        u32le (cast class_data_off) ++ u32le 0

  let header =
        [100, 101, 120, 10, 48, 51, 53, 0] ++
        replicate 4 0 ++ replicate 20 0 ++
        u32le (cast file_size) ++ u32le 112 ++ u32le 0x12345678 ++
        u32le 0 ++ u32le 0 ++ u32le (cast map_off) ++
        u32le (cast (length strings)) ++ u32le (cast string_ids_off) ++
        u32le 4 ++ u32le (cast type_ids_off) ++
        u32le 2 ++ u32le (cast proto_ids_off) ++
        u32le 0 ++ u32le 0 ++
        u32le 4 ++ u32le (cast method_ids_off) ++
        u32le 1 ++ u32le (cast class_defs_off) ++
        u32le (cast data_size) ++ u32le (cast data_off)

  let unsigned_file =
        header ++ concat string_id_bytes ++ concat type_id_bytes ++
        concat proto_id_bytes ++ concat method_id_bytes ++ class_def_bytes ++
        bundle_type_list ++ code_bytes ++ strings_layout.bytes ++
        class_data_bytes ++ padding before_map 4 ++ map_bytes

  if cast (length unsigned_file) /= file_size
    then
      Left
        ("Internal NativeActivity shell DEX layout mismatch: planned " ++
         show file_size ++ " bytes, encoded " ++ show (length unsigned_file))
    else Right ()

  let signature = sha1 (drop 32 unsigned_file)
  if length signature /= 20
    then Left "Internal SHA-1 implementation did not return 20 bytes"
    else Right ()
  let signed_file = replace_range 12 signature unsigned_file
  let checksum = adler32 (drop 12 signed_file)
  Right (replace_range 8 (u32le checksum) signed_file)

||| Write a direct NativeActivity shell classes.dex candidate.
public export
write_native_activity_shell_dex : String -> String -> IO (Either String ())
write_native_activity_shell_dex activity_descriptor path =
  case encode_native_activity_shell_dex activity_descriptor of
    Left explanation => pure (Left explanation)
    Right bytes => write_dex path bytes
