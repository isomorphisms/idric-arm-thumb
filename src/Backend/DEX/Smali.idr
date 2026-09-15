module Backend.DEX.Smali

import Backend.DEX.IR
import Data.String

%default total

private
render_constant : Register -> Int -> String
render_constant destination value =
  if destination.number <= 15 && value >= -8 && value <= 7
    then "const/4 " ++ show destination ++ ", " ++ show value
    else if value >= -32768 && value <= 32767
      then "const/16 " ++ show destination ++ ", " ++ show value
      else "const " ++ show destination ++ ", " ++ show value

private
render_move : Register -> Register -> String
render_move destination source =
  if destination.number <= 15 && source.number <= 15
    then "move " ++ show destination ++ ", " ++ show source
    else if destination.number <= 255
      then "move/from16 " ++ show destination ++ ", " ++ show source
      else "move/16 " ++ show destination ++ ", " ++ show source

private
render_instruction : Instruction -> String
render_instruction (Move destination source) = render_move destination source
render_instruction (IntegerConstant destination value) =
  render_constant destination value
render_instruction (IntegerBinary operation destination left right) =
  show operation ++ " " ++ show destination ++ ", " ++
  show left ++ ", " ++ show right
render_instruction (IntegerBranch condition left right target) =
  show condition ++ " " ++ show left ++ ", " ++ show right ++ ", " ++ show target
render_instruction (Goto target) = "goto " ++ show target
render_instruction (Mark label) = show label
render_instruction (ReturnInteger register) = "return " ++ show register

private
parameter_descriptor : Int -> String
parameter_descriptor count = pack (replicate (cast count) 'I')

private
render_method : MethodPlan -> String
render_method method =
  unlines
    ([ ".method public static " ++ method.method_name ++
       "(" ++ parameter_descriptor method.parameter_count ++ ")I"
     , "    .registers " ++ show method.register_count
     , ""
     ] ++
     map render_line method.instructions ++
     [ ".end method", "" ])
  where
    render_line : Instruction -> String
    render_line instruction@(Mark _) = render_instruction instruction
    render_line instruction = "    " ++ render_instruction instruction

||| Human-readable oracle generated from the same typed DEX plan as the
||| binary encoder. Smali is never consumed by the candidate path.
public export
render_smali : FilePlan -> String
render_smali plan =
  unlines
    [ ".class public final " ++ plan.class_descriptor
    , ".super Ljava/lang/Object;"
    , ""
    ] ++ concat (map render_method plan.methods)
