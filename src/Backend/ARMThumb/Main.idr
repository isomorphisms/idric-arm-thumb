module Backend.ARMThumb.Main

import Backend.ARMThumb.Codegen
import Compiler.Common
import Idris.Driver

main : IO ()
main =
  mainWithCodegens
    [(backend_name, arm_thumb_codegen)]
