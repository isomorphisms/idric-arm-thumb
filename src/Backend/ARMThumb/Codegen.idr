module Backend.ARMThumb.Codegen

import Backend.ARMThumb.Emit
import Backend.ARMThumb.IR
import Backend.ARMThumb.Lower
import Compiler.ANF
import Compiler.Common
import Core.Context
import Core.Env
import Core.Normalise
import Core.TT
import Data.String
import Idris.Syntax
import Libraries.Utils.Path

%default covering

public export
backend_name : String
backend_name = "arm-thumb"

private
record ExportABI where
  constructor MkExportABI
  internal_name : Name
  external_symbol : String
  argument_representations : List Representation
  result_representation : Representation

private
renderer_type_name : String -> Name
renderer_type_name leaf =
  NS (mkNamespace "RendererPrimitives") (UN (Basic leaf))

private
print_ascii_main_name : Name
print_ascii_main_name =
  NS (mkNamespace "PrintASCII") (UN (Basic "main"))

private
put_char_name : Name
put_char_name =
  NS (mkNamespace "Prelude.IO") (UN (Basic "prim__putChar"))

private
classify_abi_type : Term variables -> Either String Representation
classify_abi_type (PrimVal _ (PrT Int32Type)) = Right Word32
classify_abi_type (PrimVal _ (PrT primitive_type)) =
  Left ("unsupported source primitive type `" ++ show primitive_type ++ "`")
classify_abi_type (Ref _ (TyCon 0) name) =
  if name == renderer_type_name "Float32"
    then Right Float32
    else if name == renderer_type_name "Float32Buffer"
      then Right Float32Pointer
      else Left ("unsupported source type `" ++ show name ++ "`")
classify_abi_type type = Left "unsupported source type"

private
parse_source_signature :
  Term variables -> Either String (List Representation, Representation)
parse_source_signature
  (Bind _ argument_name (Pi _ multiplicity Explicit argument_type) scope) = do
    if isErased multiplicity
      then
        Left
          ("erased argument `" ++ show argument_name ++
           "` cannot cross the ARM C ABI")
      else do
        argument_representation <- classify_abi_type argument_type
        (more_arguments, result_representation) <- parse_source_signature scope
        Right (argument_representation :: more_arguments, result_representation)
parse_source_signature (Bind _ argument_name (Pi _ _ _ argument_type) scope) =
  Left
    ("implicit argument `" ++ show argument_name ++
     "` is not supported by the ARM C ABI")
parse_source_signature result_type = do
  result_representation <- classify_abi_type result_type
  Right ([], result_representation)

private
resolve_export_abi :
  {auto c : Ref Ctxt Defs} -> (Name, String) -> Core ExportABI
resolve_export_abi (internal_name, external_symbol) = do
  definitions <- get Ctxt
  source_type <-
    case !(lookupTyExact internal_name (gamma definitions)) of
      Nothing =>
        throw
          (UserError
            ("Could not find source type of exported function `" ++
             show internal_name ++ "`"))
      Just found => pure found
  normalised_type <- normalise definitions Env.empty source_type
  full_type <- toFullNames normalised_type
  case parse_source_signature full_type of
    Left explanation =>
      throw
        (UserError
          ("arm-thumb rejected source ABI for `" ++ show internal_name ++
           "`: " ++ explanation ++
           ". Supported arguments are RendererPrimitives.Float32, " ++
           "RendererPrimitives.Float32Buffer, and Int32; the result must " ++
           "be RendererPrimitives.Float32."))
    Right (arguments, result) =>
      if result /= Float32
        then
          throw
            (UserError
              ("arm-thumb rejected source ABI for `" ++ show internal_name ++
               "`: result must be RendererPrimitives.Float32, not " ++
               show result ++ "."))
        else if length arguments > 4
          then
            throw
              (UserError
                ("arm-thumb rejected source ABI for `" ++ show internal_name ++
                 "`: more than four one-word arguments."))
          else pure (MkExportABI internal_name external_symbol arguments result)

private
lookup_anf_definition : Name -> List (Name, ANFDef) -> Maybe ANFDef
lookup_anf_definition requested [] = Nothing
lookup_anf_definition requested ((name, definition) :: rest) =
  if requested == name then Just definition else lookup_anf_definition requested rest

mutual
  private
  character_literals : ANF -> List Char
  character_literals (APrimVal _ (Ch character)) = [character]
  character_literals (ALet _ _ value body) =
    character_literals value ++ character_literals body
  character_literals (AConCase _ _ alternatives fallback) =
    character_literals_con_alternatives alternatives ++
    character_literals_optional fallback
  character_literals (AConstCase _ _ alternatives fallback) =
    character_literals_const_alternatives alternatives ++
    character_literals_optional fallback
  character_literals _ = []

  private
  character_literals_con_alternatives : List AConAlt -> List Char
  character_literals_con_alternatives [] = []
  character_literals_con_alternatives
    (MkAConAlt _ _ _ _ body :: rest) =
      character_literals body ++ character_literals_con_alternatives rest

  private
  character_literals_const_alternatives : List AConstAlt -> List Char
  character_literals_const_alternatives [] = []
  character_literals_const_alternatives
    (MkAConstAlt constant body :: rest) =
      (case constant of
         Ch character => [character]
         _ => []) ++
      character_literals body ++
      character_literals_const_alternatives rest

  private
  character_literals_optional : Maybe ANF -> List Char
  character_literals_optional Nothing = []
  character_literals_optional (Just body) = character_literals body

mutual
  private
  calls_name : Name -> ANF -> Bool
  calls_name requested (AAppName _ _ name _) = name == requested
  calls_name requested (AExtPrim _ _ name _) = name == requested
  calls_name requested (ALet _ _ value body) =
    calls_name requested value || calls_name requested body
  calls_name requested (AConCase _ _ alternatives fallback) =
    alternatives_call_name requested alternatives ||
    optional_calls_name requested fallback
  calls_name requested (AConstCase _ _ alternatives fallback) =
    const_alternatives_call_name requested alternatives ||
    optional_calls_name requested fallback
  calls_name requested _ = False

  private
  alternatives_call_name : Name -> List AConAlt -> Bool
  alternatives_call_name requested [] = False
  alternatives_call_name requested (MkAConAlt _ _ _ _ body :: rest) =
    calls_name requested body || alternatives_call_name requested rest

  private
  const_alternatives_call_name : Name -> List AConstAlt -> Bool
  const_alternatives_call_name requested [] = False
  const_alternatives_call_name requested (MkAConstAlt _ body :: rest) =
    calls_name requested body || const_alternatives_call_name requested rest

  private
  optional_calls_name : Name -> Maybe ANF -> Bool
  optional_calls_name requested Nothing = False
  optional_calls_name requested (Just body) = calls_name requested body

private
definition_calls_name : Name -> ANFDef -> Bool
definition_calls_name requested (MkAFun _ body) = calls_name requested body
definition_calls_name requested (MkAError body) = calls_name requested body
definition_calls_name requested _ = False

private
program_calls_name : Name -> List (Name, ANFDef) -> Bool
program_calls_name requested [] = False
program_calls_name requested ((_, definition) :: rest) =
  definition_calls_name requested definition || program_calls_name requested rest

private
definition_character_literals : ANFDef -> List Char
definition_character_literals (MkAFun _ body) = character_literals body
definition_character_literals (MkAError body) = character_literals body
definition_character_literals _ = []

private
program_character_literals : List (Name, ANFDef) -> List Char
program_character_literals [] = []
program_character_literals ((_, definition) :: rest) =
  definition_character_literals definition ++ program_character_literals rest

private
has_foreign_definition : Name -> String -> List (Name, ANFDef) -> Bool
has_foreign_definition requested calling_convention [] = False
has_foreign_definition requested calling_convention
  ((name, MkAForeign calling_conventions _ _) :: rest) =
    (name == requested && elem calling_convention calling_conventions) ||
    has_foreign_definition requested calling_convention rest
has_foreign_definition requested calling_convention (_ :: rest) =
  has_foreign_definition requested calling_convention rest

private
validate_print_ascii_program : List (Name, ANFDef) -> Either String ()
validate_print_ascii_program definitions = do
  case lookup_anf_definition print_ascii_main_name definitions of
    Just (MkAFun _ _) => Right ()
    Just _ => Left "PrintASCII.main did not lower to an ANF function"
    Nothing => Left "No ANF definition was produced for PrintASCII.main"
  let characters = program_character_literals definitions
  if not (elem 'x' characters)
    then Left "PrintASCII reachable ANF no longer contains the literal byte character 'x'"
    else Right ()
  if not (program_calls_name put_char_name definitions)
    then Left "PrintASCII reachable ANF no longer calls Prelude.IO.prim__putChar"
    else Right ()
  if not (has_foreign_definition put_char_name "C:putchar,libc 6" definitions)
    then Left "PrintASCII reachable program no longer contains the pinned putchar foreign definition"
    else Right ()

private
print_ascii_assembly : String
print_ascii_assembly =
  unlines
    [ ".syntax unified"
    , ".arch armv7-a"
    , ".thumb"
    , ".text"
    , ""
    , "@ First executable Idriç ARM/Thumb program."
    , "@ Source gate: PrintASCII.main = putChar 'x'."
    , "@ Runtime seam: Linux ARM EABI write(1, &x, 1), then exit(0)."
    , "        .p2align 2"
    , "        .global _start"
    , "        .type _start, %function"
    , "        .thumb_func"
    , "_start:"
    , "        movs    r0, #1"
    , "        ldr     r1, =.Lstdout_byte"
    , "        movs    r2, #1"
    , "        movs    r7, #4"
    , "        svc     #0"
    , "        movs    r0, #0"
    , "        movs    r7, #1"
    , "        svc     #0"
    , "        .size _start, .-_start"
    , ""
    , "        .section .rodata"
    , ".Lstdout_byte:"
    , "        .byte   0x78"
    , ""
    , ".section .note.GNU-stack,\"\",%progbits"
    ]

private
is_print_ascii_export : (Name, String) -> Bool
is_print_ascii_export (internal_name, external_symbol) =
  internal_name == print_ascii_main_name && external_symbol == "main"

private
find_duplicate : List String -> Maybe String
find_duplicate [] = Nothing
find_duplicate (symbol :: rest) =
  if elem symbol rest then Just symbol else find_duplicate rest

private
validate_exports : List ExportABI -> Either String ()
validate_exports [] =
  Left
    ("No functions selected. Add %export \"arm-thumb:<c_symbol>\" " ++
     "to a runtime-free numerical leaf.")
validate_exports exports =
  case find_duplicate (map external_symbol exports) of
    Nothing => Right ()
    Just duplicate => Left ("Duplicate exported C symbol `" ++ duplicate ++ "`")

private
comment_each_line : String -> String
comment_each_line source =
  fastConcat (map (\line => "@   " ++ line ++ "\n") (lines source))

private
render_selected_export : ExportABI -> String
render_selected_export selected =
  "@ " ++ show selected.internal_name ++ " -> " ++ selected.external_symbol ++ "\n"

private
lower_exported_functions :
  List ExportABI -> List (Name, ANFDef) -> Either String String
lower_exported_functions [] definitions = Right ""
lower_exported_functions (selected :: rest) definitions = do
  definition <-
    case lookup_anf_definition selected.internal_name definitions of
      Nothing =>
        Left
          ("No ANF definition was produced for exported function `" ++
           show selected.internal_name ++ "`")
      Just found => Right found
  leaf <-
    lower_leaf selected.external_symbol
      selected.argument_representations selected.result_representation definition
  leaf_assembly <- emit_leaf leaf
  more <- lower_exported_functions rest definitions
  Right
    ("\n@ Validated Idriç leaf IR for " ++ selected.external_symbol ++ ":\n" ++
     comment_each_line (render_ir leaf) ++ leaf_assembly ++ more)

private
render_backend_assembly :
  List ExportABI -> List (Name, ANFDef) -> Either String String
render_backend_assembly exports definitions = do
  validate_exports exports
  lowered <- lower_exported_functions exports definitions
  Right
    (assembly_header ++
     "\n@ Selected Idriç exports:\n" ++
     fastConcat (map render_selected_export exports) ++
     lowered ++ assembly_footer)

private
fully_qualified_export :
  {auto c : Ref Ctxt Defs} -> (Name, String) -> Core (Name, String)
fully_qualified_export (internal_name, external_symbol) = do
  qualified_name <- toFullNames internal_name
  pure (qualified_name, external_symbol)

private
compile_numerical_exports :
  {auto c : Ref Ctxt Defs} ->
  List (Name, String) -> List (Name, ANFDef) -> Core String
compile_numerical_exports qualified_exports definitions = do
  export_abis <- traverse resolve_export_abi qualified_exports
  case render_backend_assembly export_abis definitions of
    Left explanation =>
      throw (UserError ("arm-thumb rejected reachable program: " ++ explanation))
    Right source => pure source

private
compile_arm_thumb :
  Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
  (temporary_directory : String) -> (output_directory : String) ->
  ClosedTerm -> (requested_output_name : String) -> Core (Maybe String)
compile_arm_thumb definitions syntax temporary_directory output_directory
                  term requested_output_name = do
  resolved_compile_data <- getCompileDataWith [backend_name] False ANF term
  qualified_exports <- traverse fully_qualified_export (exported resolved_compile_data)
  let anf_definitions = anf resolved_compile_data
  let assembly_file = output_directory </> (requested_output_name ++ ".arm-thumb.S")
  assembly_source <-
    case qualified_exports of
      [selected] =>
        if is_print_ascii_export selected
          then
            case validate_print_ascii_program anf_definitions of
              Left explanation =>
                throw (UserError ("arm-thumb rejected bootstrap PrintASCII program: " ++ explanation))
              Right () => pure print_ascii_assembly
          else compile_numerical_exports qualified_exports anf_definitions
      _ => compile_numerical_exports qualified_exports anf_definitions
  Core.writeFile assembly_file assembly_source
  pure (Just assembly_file)

private
execute_arm_thumb :
  Ref Ctxt Defs -> Ref Syn SyntaxInfo -> String -> ClosedTerm -> Core ()
execute_arm_thumb definitions syntax temporary_directory term =
  throw
    (UserError
      ("arm-thumb emits a .S translation unit; assemble it with an " ++
       "Android-target Clang."))

public export
arm_thumb_codegen : Codegen
arm_thumb_codegen = MkCG compile_arm_thumb execute_arm_thumb Nothing Nothing