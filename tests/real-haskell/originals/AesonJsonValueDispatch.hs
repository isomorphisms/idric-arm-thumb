-- Verbatim excerpt retained for provenance/reference; this is not a standalone module.
-- Upstream: https://github.com/haskell/aeson/blob/51c4db6d9dbe5c6900e626bf6a58fd00e8ef9f09/attoparsec-aeson/src/Data/Aeson/Parser/Internal.hs
-- Upstream module: Data.Aeson.Parser.Internal
-- Original purpose: dispatch on the first non-space byte of a JSON value.
-- Copyright: (c) 2011-2016 Bryan O'Sullivan; (c) 2011 MailRank, Inc.
-- License: BSD3; see ../upstream-licenses/aeson.txt

jsonWith :: ([(Key, Value)] -> Either String Object) -> Parser Value
jsonWith mkObject = fix $ \value_ -> do
  skipSpace
  w <- A.peekWord8'
  case w of
    W8.DOUBLE_QUOTE  -> A.anyWord8 *> (String <$> jstring_)
    W8.LEFT_CURLY    -> A.anyWord8 *> object_ mkObject value_
    W8.LEFT_SQUARE   -> A.anyWord8 *> array_ value_
    W8.LOWER_F       -> string "false" $> Bool False
    W8.LOWER_T       -> string "true" $> Bool True
    W8.LOWER_N       -> string "null" $> Null
    _                 | w >= W8.DIGIT_0 && w <= W8.DIGIT_9 || w == W8.HYPHEN
                     -> Number <$> scientific
      | otherwise    -> fail "not a valid json value"
{-# INLINE jsonWith #-}
