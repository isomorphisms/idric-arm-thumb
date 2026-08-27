-- Verbatim excerpt retained for provenance/reference; this is not a standalone module.
-- Upstream: https://github.com/ghc/ghc/blob/cd653714596108ebf47450202b6748c20bb53799/libraries/ghc-internal/src/GHC/Internal/Text/Read/Lex.hs
-- Upstream module: GHC.Internal.Text.Read.Lex
-- Original purpose: parse Haskell control-character escapes after "\\^".
-- Copyright: (c) The University of Glasgow 2002
-- License: BSD-style; see ../upstream-licenses/ghc-base.txt

  lexCntrlChar =
    do _ <- char '^'
       c <- get
       case c of
         '@'  -> return '\^@'
         'A'  -> return '\^A'
         'B'  -> return '\^B'
         'C'  -> return '\^C'
         'D'  -> return '\^D'
         'E'  -> return '\^E'
         'F'  -> return '\^F'
         'G'  -> return '\^G'
         'H'  -> return '\^H'
         'I'  -> return '\^I'
         'J'  -> return '\^J'
         'K'  -> return '\^K'
         'L'  -> return '\^L'
         'M'  -> return '\^M'
         'N'  -> return '\^N'
         'O'  -> return '\^O'
         'P'  -> return '\^P'
         'Q'  -> return '\^Q'
         'R'  -> return '\^R'
         'S'  -> return '\^S'
         'T'  -> return '\^T'
         'U'  -> return '\^U'
         'V'  -> return '\^V'
         'W'  -> return '\^W'
         'X'  -> return '\^X'
         'Y'  -> return '\^Y'
         'Z'  -> return '\^Z'
         '['  -> return '\^['
         '\\' -> return '\^\'
         ']'  -> return '\^]'
         '^'  -> return '\^^'
         '_'  -> return '\^_'
         _    -> pfail
