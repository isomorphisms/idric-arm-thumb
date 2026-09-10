module Backend.DEX.Main

import Backend.DEX.Codegen as DEX
import Compiler.Common
import Idris.Driver

main : IO ()
main =
  mainWithCodegens
    [(DEX.backend_name, DEX.dex_codegen)]
