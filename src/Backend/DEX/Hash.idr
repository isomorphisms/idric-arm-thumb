module Backend.DEX.Hash

import Data.Bits
import Data.List

%default covering

private
word_modulus : Integer
word_modulus = 4294967296

private
mask32 : Integer -> Integer
mask32 value = value `mod` word_modulus

private
rotate_left32 : Integer -> Nat -> Integer
rotate_left32 value shift =
  mask32
    ((mask32 value `shiftL` shift) .|.
     (mask32 value `shiftR` (32 `minus` shift)))

private
byte_at : Int -> List Int -> Int
byte_at requested bytes = fromMaybe 0 (index' requested bytes)
  where
    index' : Int -> List Int -> Maybe Int
    index' index [] = Nothing
    index' index (byte :: rest) =
      if index <= 0 then Just byte else index' (index - 1) rest

private
word_from_big_endian : List Int -> Int -> Integer
word_from_big_endian bytes offset =
  (cast (byte_at offset bytes) `shiftL` 24) .|.
  (cast (byte_at (offset + 1) bytes) `shiftL` 16) .|.
  (cast (byte_at (offset + 2) bytes) `shiftL` 8) .|.
  cast (byte_at (offset + 3) bytes)

private
word_at : Int -> List Integer -> Integer
word_at requested words = fromMaybe 0 (index' requested words)
  where
    index' : Int -> List Integer -> Maybe Integer
    index' index [] = Nothing
    index' index (word :: rest) =
      if index <= 0 then Just word else index' (index - 1) rest

private
extend_words : Int -> List Integer -> List Integer
extend_words next words =
  if next >= 80
    then words
    else
      let expanded =
            rotate_left32
              (word_at (next - 3) words `xor`
               word_at (next - 8) words `xor`
               word_at (next - 14) words `xor`
               word_at (next - 16) words) 1
      in extend_words (next + 1) (words ++ [expanded])

private
initial_words : List Int -> List Integer
initial_words block = map (word_from_big_endian block) [0, 4 .. 60]

private
record SHAState where
  constructor MkSHAState
  a : Integer
  b : Integer
  c : Integer
  d : Integer
  e : Integer

private
round_values : Int -> SHAState -> (Integer, Integer)
round_values index state =
  if index < 20
    then ((state.b .&. state.c) .|. ((mask32 (state.b `xor` 0xffffffff)) .&. state.d),
          0x5a827999)
    else if index < 40
      then (state.b `xor` state.c `xor` state.d, 0x6ed9eba1)
      else if index < 60
        then ((state.b .&. state.c) .|. (state.b .&. state.d) .|. (state.c .&. state.d),
              0x8f1bbcdc)
        else (state.b `xor` state.c `xor` state.d, 0xca62c1d6)

private
sha_round : List Integer -> SHAState -> Int -> SHAState
sha_round words state index =
  let (choice, constant) = round_values index state
      temporary =
        mask32
          (rotate_left32 state.a 5 + choice + state.e + constant +
           word_at index words)
  in MkSHAState temporary state.a (rotate_left32 state.b 30) state.c state.d

private
sha_rounds : List Integer -> Int -> SHAState -> SHAState
sha_rounds words index state =
  if index >= 80
    then state
    else sha_rounds words (index + 1) (sha_round words state index)

private
compress : SHAState -> List Int -> SHAState
compress hash block =
  let words = extend_words 16 (initial_words block)
      result = sha_rounds words 0 hash
  in MkSHAState
       (mask32 (hash.a + result.a))
       (mask32 (hash.b + result.b))
       (mask32 (hash.c + result.c))
       (mask32 (hash.d + result.d))
       (mask32 (hash.e + result.e))

private
compress_blocks : SHAState -> List Int -> SHAState
compress_blocks state [] = state
compress_blocks state bytes =
  let block = take 64 bytes
      rest = drop 64 bytes
  in compress_blocks (compress state block) rest

private
big_endian_bytes : Int -> Integer -> List Int
big_endian_bytes width value =
  reverse (little_endian width value)
  where
    little_endian : Int -> Integer -> List Int
    little_endian remaining current =
      if remaining <= 0
        then []
        else cast (current `mod` 256) :: little_endian (remaining - 1) (current `div` 256)

private
padding_zeros : Int -> Int
padding_zeros message_size =
  let occupied = (message_size + 1) `mod` 64
  in if occupied <= 56 then 56 - occupied else 120 - occupied

||| Pure SHA-1 used to fill the DEX header signature. The encoder does not
||| delegate its structural integrity fields to an assembler or postprocessor.
public export
sha1 : List Int -> List Int
sha1 bytes =
  let padded =
        bytes ++ [0x80] ++
        replicate (cast (padding_zeros (cast (length bytes)))) 0 ++
        big_endian_bytes 8 (cast (length bytes) * 8)
      initial = MkSHAState 0x67452301 0xefcdab89 0x98badcfe 0x10325476 0xc3d2e1f0
      result = compress_blocks initial padded
  in big_endian_bytes 4 result.a ++
     big_endian_bytes 4 result.b ++
     big_endian_bytes 4 result.c ++
     big_endian_bytes 4 result.d ++
     big_endian_bytes 4 result.e

private
adler_step : (Integer, Integer) -> Int -> (Integer, Integer)
adler_step (a, b) byte =
  let next_a = (a + cast byte) `mod` 65521
  in (next_a, (b + next_a) `mod` 65521)

||| Adler-32 used for the DEX checksum field.
public export
adler32 : List Int -> Integer
adler32 bytes =
  let (a, b) = foldl adler_step (1, 0) bytes
  in (b `shiftL` 16) .|. a
