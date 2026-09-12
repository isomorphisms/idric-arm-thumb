module RedditCliDexGen

import Backend.DEX.EncodeRedditCli
import System

%default covering

private
fail : String -> IO a
fail explanation = do
  putStrLn ("FAIL: " ++ explanation)
  exitFailure

main : IO ()
main = do
  result <- write_reddit_cli_dex "build/exec/reddit/classes.dex"
  case result of
    Left explanation => fail explanation
    Right () => putStrLn "PASS: direct Reddit CLI classes.dex generated"
