module WegertDexGen

import Backend.DEX.EncodeNativeActivity
import System

%default covering

private
fail : String -> IO a
fail explanation = do
  putStrLn ("FAIL: " ++ explanation)
  exitFailure

main : IO ()
main = do
  result <- write_wegert_activity_dex "build/exec/wegert/classes.dex"
  case result of
    Left explanation => fail explanation
    Right () => putStrLn "PASS: direct Wegert classes.dex generated"
