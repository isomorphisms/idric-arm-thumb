module NativeActivityShellGen

import Backend.DEX.EncodeNativeActivityShell
import System

%default covering

private
fail : String -> IO a
fail explanation = do
  putStrLn ("FAIL: " ++ explanation)
  exitFailure

private
write_shell : String -> String -> IO ()
write_shell descriptor path = do
  result <- write_native_activity_shell_dex descriptor path
  case result of
    Left explanation => fail explanation
    Right () => putStrLn ("PASS: direct NativeActivity shell generated: " ++ descriptor)

main : IO ()
main = do
  write_shell
    "Lorg/isomorphisms/wegert/WegertActivity;"
    "build/exec/native-shell/wegert/classes.dex"
  write_shell
    "Lorg/isomorphisms/analyticcontinuation/ExplorerActivity;"
    "build/exec/native-shell/analytic-continuation/classes.dex"
