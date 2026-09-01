module EncoderSelfTest

import Backend.DEX.Encode
import Backend.DEX.Hash
import Backend.DEX.IR
import Data.List
import System

%default covering

private
fail : String -> IO a
fail message = do
  putStrLn ("FAIL: " ++ message)
  exitFailure

private
expect_equal : Eq value => Show value => String -> value -> value -> IO ()
expect_equal label expected actual =
  if expected == actual
    then pure ()
    else fail (label ++ ": expected " ++ show expected ++ ", got " ++ show actual)

private
expect_left : String -> Either String value -> IO ()
expect_left label (Left explanation) = pure ()
expect_left label (Right value) = fail (label ++ ": malformed plan was accepted")

private
edge_method : MethodPlan
edge_method =
  MkMethodPlan "selftest" "edge_constants" 0 1
    [ IntegerConstant (MkRegister 0) (-2147483648)
    , IntegerConstant (MkRegister 0) 2147483647
    , ReturnInteger (MkRegister 0)
    ]

private
wide_move_method : MethodPlan
wide_move_method =
  MkMethodPlan "selftest" "wide_moves" 0 257
    [ IntegerConstant (MkRegister 255) 7
    , Move (MkRegister 256) (MkRegister 255)
    , Move (MkRegister 254) (MkRegister 256)
    , ReturnInteger (MkRegister 254)
    ]

private
bad_arithmetic_method : MethodPlan
bad_arithmetic_method =
  MkMethodPlan "selftest" "bad_arithmetic_register" 0 257
    [ IntegerBinary AddInteger (MkRegister 256) (MkRegister 0) (MkRegister 1)
    , ReturnInteger (MkRegister 0)
    ]

private
bad_branch_method : MethodPlan
bad_branch_method =
  MkMethodPlan "selftest" "bad_branch_register" 0 18
    [ IntegerBranch LessThanInteger (MkRegister 16) (MkRegister 17) (MkLabel 0)
    , IntegerConstant (MkRegister 0) 0
    , Mark (MkLabel 0)
    , ReturnInteger (MkRegister 0)
    ]

private
long_goto_method : MethodPlan
long_goto_method =
  MkMethodPlan "selftest" "long_goto" 0 1
    (Goto (MkLabel 0) ::
     replicate 128 (IntegerConstant (MkRegister 0) 0) ++
     [Mark (MkLabel 0), ReturnInteger (MkRegister 0)])

private
single_method_file : MethodPlan -> FilePlan
single_method_file method = MkFilePlan "LIdric/SelfTest;" [method]

main : IO ()
main = do
  expect_equal "SHA-1 abc"
    [169, 153, 62, 54, 71, 6, 129, 106, 186, 62,
     37, 113, 120, 80, 194, 108, 156, 208, 216, 157]
    (sha1 [97, 98, 99])
  expect_equal "Adler-32 Wikipedia" 0x11e60398
    (adler32 (map ord (unpack "Wikipedia")))
  let plan = MkFilePlan "LIdric/SelfTest;" [edge_method, wide_move_method]
  first <- case encode_dex plan of
    Left explanation => fail explanation
    Right bytes => pure bytes
  second <- case encode_dex plan of
    Left explanation => fail explanation
    Right bytes => pure bytes
  expect_equal "deterministic direct encoding" first second
  expect_equal "DEX 035 magic" [100, 101, 120, 10, 48, 51, 53, 0]
    (take 8 first)
  expect_left "format 23x register limit"
    (encode_dex (single_method_file bad_arithmetic_method))
  expect_left "format 22t register limit"
    (encode_dex (single_method_file bad_branch_method))
  expect_left "format 10t branch range"
    (encode_dex (single_method_file long_goto_method))
  putStrLn "PASS: DEX encoder self-test"
