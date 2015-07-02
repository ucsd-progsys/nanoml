{
{-# OPTIONS_GHC -fno-warn-tabs #-}
module NanoML.Lexer where

import Data.Char

import Debug.Trace
}

%wrapper "monad"

$digit = 0-9
$alpha = [a-zA-Z]
$lower = [a-z]
$upper = [A-Z]
$symbol = [\! \$ \% \& \* \+ \- \. \/ \: \< \= \> \? \@ \^ \| \~]

-- copied from Alex's sample Haskell lexer
$whitechar = [ \t\n\r\f\v]
$special   = [\(\)\,\;\[\]\`\{\}]
$graphic   = [$lower $upper $symbol $digit $special \_\:\"\']

@decimal     = $digit+

$cntrl   = [$upper \@\[\\\]\^\_]
@ascii   = \^ $cntrl | NUL | SOH | STX | ETX | EOT | ENQ | ACK
	 | BEL | BS | HT | LF | VT | FF | CR | SO | SI | DLE
	 | DC1 | DC2 | DC3 | DC4 | NAK | SYN | ETB | CAN | EM
	 | SUB | ESC | FS | GS | RS | US | SP | DEL
$charesc = [abfnrtv\\\"\'\&]
@escape  = \\ ($charesc | @ascii | @decimal)
@gap     = $whitechar+
@string  = $graphic # [\"\\] | " " | @escape | @gap

tokens :-
  $white+       ;
  $digit+       { tokS TokInt }
  $digit+ [eE] [\-\+]? $digit+ { tokS TokFloat }
  $digit+ \. $digit* { tokS (TokFloat . (++"0")) }
  $digit+ \. $digit* [eE] [\-\+]? $digit+ { tokS (TokFloat . mkExp) }


 "(*"           { nested_comment }

  \(            { tok TokLParen }
  \)            { tok TokRParen }
  \{            { tok TokLBrace }
  \}            { tok TokRBrace }
  \[            { tok TokLBrack }
  \]            { tok TokRBrack }
  \-\>          { tok TokArrow }
  \<\-          { tok TokBackArrow }
  \:            { tok TokColon }
  \:=           { tok TokColonEq }
  \:\:          { tok TokCons }
  \;            { tok TokSemi }
  \;\;          { tok TokSemiSemi }

  \=            { tok TokEq }
  \*            { tok TokStar }
  \'            { tok TokTick }
  \+            { tok TokPlus }
  \+\.          { tok TokPlusDot }
  \-            { tok TokMinus }
  \-\.          { tok TokMinusDot }
  \!            { tok TokBang }

  \_            { tok TokUnderscore }
  \,            { tok TokComma }

  \&\&          { tok TokLAnd }
  \|\|          { tok TokLOr }
  \|            { tok TokPipe }
  \.            { tok TokDot }
  \.\.          { tok TokDotDot }

  "and"         { tok TokAnd }
  "as"          { tok TokAs }
  "begin"       { tok TokBegin }
  "else"        { tok TokElse }
  "end"         { tok TokEnd }
  "exception"   { tok TokException }
  "false"       { tok TokFalse }
  "fun"         { tok TokFun }
  "function"    { tok TokFunction }
  "if"          { tok TokIf }
  "in"          { tok TokIn }
  "let"         { tok TokLet }
  "match"       { tok TokMatch }
  "of"          { tok TokOf }
  "or"          { tok TokOr }
  "rec"         { tok TokRec }
  "then"        { tok TokThen }
  "true"        { tok TokTrue }
  "try"         { tok TokTry }
  "type"        { tok TokType }
  "when"        { tok TokWhen }
  "with"        { tok TokWith }

  [\= \< \> \| \& \$] $symbol* { tokS TokInfixOp0 }
  \!\=                         { tokS TokInfixOp0 }
  [\@ \^]             $symbol* { tokS TokInfixOp1 }
  [\+ \-]             $symbol* { tokS TokInfixOp2 }
  [\* \/ \%]          $symbol* { tokS TokInfixOp3 }
  "mod"                        { tokS TokInfixOp3 }
  \*\*                $symbol* { tokS TokInfixOp4 }


  ($lower | \_) [$alpha $digit \_ \']* { tokS TokId }
  ($upper | \_) [$alpha $digit \_ \']* { tokS TokCon }
 
  \" @string* \"            { tokS TokString }
  \' ($printable # [\']) \' { tokS TokChar }

{
tok :: Token -> AlexInput -> Int -> Alex Token
tok t _ _ = return t

tokS :: (String -> Token) -> AlexInput -> Int -> Alex Token
tokS t (_, _, _, str) len = return (t (take len str))

mkExp :: String -> String
mkExp s = let (d,f) = break (=='.') s in d ++ ".0" ++ drop 1 f

data Token
  = TokId String
  | TokCon String
  | TokString String
  | TokChar String
  | TokInt String
  | TokFloat String

  | TokLParen
  | TokRParen
  | TokLBrace
  | TokRBrace
  | TokLBrack
  | TokRBrack

  | TokAnd
  | TokAs
  | TokBegin
  | TokElse
  | TokEnd
  | TokException
  | TokFalse
  | TokFun
  | TokFunction
  | TokIf
  | TokIn
  | TokLet
  | TokMatch
  | TokOf
  | TokOr
  | TokRec
  | TokThen
  | TokTrue
  | TokTry
  | TokType
  | TokWhen
  | TokWith 

  | TokLAnd
  | TokLOr
  | TokTick
  | TokStar
  | TokPlus
  | TokPlusDot
  | TokMinus
  | TokMinusDot
  | TokArrow
  | TokBackArrow
  | TokBang
  | TokDot
  | TokDotLBrack
  | TokDotLParen
  | TokDotDot
  | TokColon
  | TokColonEq
  | TokComma
  | TokSemi
  | TokSemiSemi
  | TokEq
  | TokNe
  | TokLt
  | TokGt
  | TokLe
  | TokGe
  | TokUnderscore
  | TokPipe
  | TokCons

  | TokInfixOp0 String
  | TokInfixOp1 String
  | TokInfixOp2 String
  | TokInfixOp3 String
  | TokInfixOp4 String

  | TokEOF
  deriving (Eq,Show)

nested_comment :: AlexInput -> Int -> Alex Token
nested_comment _ _ = do
  input <- alexGetInput
  go 1 input
  where go 0 input = do alexSetInput input; alexMonadScan
	go n input = do
          case alexGetByte input of
	    Nothing  -> err input
	    Just (c,input) -> do
              case chr (fromIntegral c) of
	    	'*' -> do
                  case alexGetByte input of
		    Nothing  -> err input
                    Just (c,input') | c == fromIntegral (ord ')') -> go (n-1) input'
                    Just (c,input')   -> go n input
	     	'(' -> do
                  case alexGetByte input of
		    Nothing  -> err input
                    Just (c,input') | c == fromIntegral (ord '*') -> go (n+1) input'
		    Just (c,input')   -> go n input
	    	c -> go n input
        err input = do alexSetInput input; lexError "error in nested comment"  

getPos :: AlexPosn -> (Int, Int)
getPos (AlexPn _ line column) = (line, column)

getPosition :: Alex (Int, Int)
getPosition = Alex $ \s -> Right (s, getPos . alex_pos $ s)

lexWrap :: (Token -> Alex a) -> Alex a
lexWrap cont = do
    tok <- alexMonadScan
    cont tok

lexError s = do
  (p,c,_,input) <- alexGetInput
  alexError (showPosn p ++ ": " ++ s ++
		   (if (not (null input))
		     then " before " ++ show (head input)
		     else " at end of file"))

alexEOF = return TokEOF

showPosn (AlexPn _ line col) = show line ++ ':' : show col

alexScanTokens :: String -> Either String [Token]
alexScanTokens input = runAlex input gather
  where
  gather = do
    t <- alexMonadScan
    case t of
      TokEOF -> return [TokEOF]
      _      -> return . (t :) =<< gather
}
