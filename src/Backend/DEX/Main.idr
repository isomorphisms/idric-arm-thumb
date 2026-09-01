module Backend.DEX.Main

import Backend.ARMThumb.Codegen as ARMThumb
import Backend.DEX.Codegen as DEX
import Compiler.Common
import Idris.Driver

main : IO ()
main =
  mainWithCodegens
    [ (ARMThumb.backend_name, ARMThumb.arm_thumb_codegen)
    , (DEX.backend_name, DEX.dex_codegen)
    ]
