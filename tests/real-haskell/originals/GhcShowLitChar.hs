-- Verbatim excerpt retained for provenance/reference; this is not a standalone module.
-- Upstream: https://github.com/ghc/ghc/blob/cd653714596108ebf47450202b6748c20bb53799/libraries/ghc-internal/src/GHC/Internal/Show.hs
-- Upstream module: GHC.Internal.Show
-- Original purpose: render a Char with Haskell source-language escape conventions.
-- Copyright: (c) The University of Glasgow, 1992-2002
-- License: BSD-style; see ../upstream-licenses/ghc-base.txt

showLitChar                :: Char -> ShowS
showLitChar c s | c > '\DEL' =  showChar '\\' (protectEsc isDec (shows (ord c)) s)
showLitChar '\DEL'         s =  showString "\\DEL" s
showLitChar '\\'           s =  showString "\\\\" s
showLitChar c s | c >= ' '   =  showChar c s
showLitChar '\a'           s =  showString "\\a" s
showLitChar '\b'           s =  showString "\\b" s
showLitChar '\f'           s =  showString "\\f" s
showLitChar '\n'           s =  showString "\\n" s
showLitChar '\r'           s =  showString "\\r" s
showLitChar '\t'           s =  showString "\\t" s
showLitChar '\v'           s =  showString "\\v" s
showLitChar '\SO'          s =  protectEsc (== 'H') (showString "\\SO") s
showLitChar c              s =  showString ('\\' : asciiTab!!ord c) s
        -- I've done manual eta-expansion here, because otherwise it's
        -- impossible to stop (asciiTab!!ord) getting floated out as an MFE
