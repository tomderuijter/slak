module Tokenizer where

import qualified Utility as U

import Data.List as List
import Data.Maybe as Maybe
import qualified Data.Char as C

type Reader = (String,Int)
type Token = (TokenEnum, U.Span)
type LexResult = Maybe [Token]
type LexFun = Reader -> (Reader, LexResult)

data TokenEnum =
	-- Literals
	  Number Int 
	| Id String
	| Boolean Bool
	| Comment String
	-- Other tokens	
	| Type TypeEnum
	| Op OperatorEnum
	| Field FieldEnum
	| Key KeywordEnum
	| Sep SeparatorEnum
	deriving (Show, Eq, Read)

data TypeEnum = 
	  Int
	| Void
	| Bool
	deriving (Show, Eq, Read)

data OperatorEnum = 
	-- Arithmetic
	  Plus
	| Min
	| Mult
	| Div
	| Mod
	-- Relative
	| Eq
	| Lt
	| Gt
	| Le
	| Ge
	| Neq
	-- Boolean
	| And
	| Or
	| Not
	-- List
	| Cons
	-- Assignment
	| As
	deriving (Show,Eq, Read)

data FieldEnum =
	  Head
	| Tail
	| First
	| Second
	deriving (Show, Eq, Read)

data KeywordEnum =
	  If
	| Then
	| Else
	| While
	| Return
	deriving (Show, Eq, Read)

data SeparatorEnum =
	  LBr
	| RBr
	| LAcc
	| RAcc
	| LPar
	| RPar
	| Comma
	| Pcomma
	deriving (Show, Eq, Read)

reservedSymbols :: [(String,TokenEnum)]
reservedSymbols =
	[	
		-- Operators
		-- Arithmetic
		("+",	Op Plus),
		("-",	Op Min),
		("*",	Op Mult),
		("/",	Op Div),
		("%",	Op Mod),
		-- Relative
		("==",	Op Eq),
		("<",	Op Lt),
		(">",	Op Gt),
		("<=",	Op Le),
		(">=",	Op Ge),
		("!=",	Op Neq),
		-- Boolean
		("&&",	Op And),
		("||",	Op Or),
		("!",	Op Not),
		-- List
		(":",	Op Cons),
		-- Assignment
		("=",	Op As),
	
		-- Fields
		(".hd",		Field Head),
		(".tl",		Field Tail),
		(".fst",	Field First),
		(".snd",	Field Second),
		
		-- Separators
		("[",	Sep LBr),
		("]",	Sep RBr),
		("{",	Sep LAcc),
		("}",	Sep RAcc),
		("(",	Sep LPar),
		(")",	Sep RPar),
		(",",	Sep Comma),
		(";",	Sep Pcomma)	
	]

reservedWords :: [(String,TokenEnum)]
reservedWords = 
	[	("if", 		Key If),
		("then", 	Key Then),
		("else", 	Key Else),
		("while",	Key While),
		("Int",		Type Int),
		("Void",	Type Void),
		("Bool",	Type Bool),
		("False",	Boolean False),
		("True",	Boolean True),
		("return",	Key Return)
	]

-- Lexes the whole program string
lexStr :: Reader -> LexResult
lexStr ([], start) 	= Nothing
lexStr (input, start) 	= if isJust result then Just (fromJust result ++ (fromMaybe [] (lexStr (rinput,rindex)))) else Nothing
	where ((rinput, rindex), result) = lexOneToken (input, start)

-- Lexes one token
-- TODO: At the moment chooses FIRST match, must go to LONGEST match
lexOneToken :: LexFun
lexOneToken = \(input,start) -> (lexWhitespace `andthen` lexComment `andthen` lexInteger `andthen` lexSymbol `andthen` lexKeyword) (input,start)

-- Combinator for lexer functions
andthen :: LexFun -> LexFun -> LexFun
andthen f g = \x -> 
	case (f x) of 
		(_, Nothing) 	-> g x
		output		-> output

lexComment :: LexFun
lexComment (input,start)
	| isPrefixOf "//" input	= lexLineComment (drop 2 input, start+2)
	| isPrefixOf "/*" input	= lexMultiComment (drop 2 input, start+2)
	| otherwise		= ((input, start), Nothing)
	where
		lexLineComment (input, start) 	= 	let	(comment, rest) = break (\x -> x == '\n' || x == '\r') input
								size = length comment
								end = start + size
							in	((rest, end), Just [(Comment comment, U.Span start end )])
							
		lexMultiComment (input, start) 	= 	if "*/" `isInfixOf` input 
							then 
								let	(comment,rest) = splitAtEndComment [] input
									size = length comment
									end = start + size
								in	((rest, end+2), Just [(Comment comment, U.Span start end)])
							else 	(("", start+length input), Nothing)
							-- One could possibly throw a lexer error here, for lack of closing bracket.

splitAtEndComment :: String -> String -> (String,String)
splitAtEndComment acc []		= (acc,[])
splitAtEndComment acc ('*':'/':xs)	= (acc,xs)
splitAtEndComment acc (x:xs)		= splitAtEndComment (acc ++ [x]) xs

-- Lexes (and discards) whitespace
lexWhitespace :: LexFun
lexWhitespace (input,index) =
	case input of 
		('\r':xs)	-> ((xs,index+1), empty)
		('\n':xs)	-> ((xs,index+1), empty)
		('\t':xs)	-> ((xs,index+1), empty)
		(' ':xs)	-> ((xs,index+1), empty)
		_		-> ((input,index), Nothing)
	where empty = Just []

lexInteger :: LexFun
lexInteger (input, start)
	| C.isDigit (head input)	= let
					(integer, rest) = splitAtInt [] input
					size = length integer
					end = start + size
					in ((rest, end), Just [ (Number (read integer :: Int), U.Span start end) ])
	| otherwise			= ((input, start), Nothing)
	where
	splitAtInt integer [] = (integer, "")
	splitAtInt integer (x:xs) = if C.isDigit x then splitAtInt (integer++[x]) xs else (integer, (x:xs))

-- Lexes special symbols such as operators
lexSymbol :: LexFun
lexSymbol (input, start)
	| C.isAlphaNum (head input)	= ((input, start), Nothing)
	| '.' == (head input)		= let
					(symbol, rest) = span C.isAlpha (tail input)
					field = matchField ('.' : symbol)
					size = if isJust field then length ('.' : symbol) + 1 else 0
					end = start + size
					token = if isJust field then Just [(fromJust field, U.Span start end)] else Nothing
					in ((rest, end), token)
	| otherwise			= let 
					(symbol, _) = span isWeirdSymbol input
					match = longestMatch symbol
					size = if isJust match then length (fst (fromJust match)) else 0
					rest = drop (size) input
					end = start + size
					token = if isJust match then Just [(snd (fromJust match), U.Span start end)] else Nothing
					in ((rest, end), token)
	where
		isWeirdSymbol s 		= C.isMark s || C.isSymbol s || C.isPunctuation s
		longestMatch []			= Nothing
		longestMatch symbols@(x:xs) 	= if isJust (lookup symbols reservedSymbols) then Just (symbols, fromJust (lookup symbols reservedSymbols)) else longestMatch xs
		matchField str			= lookup str reservedSymbols


-- Lexes keywords, fields and variable names
lexKeyword :: LexFun
lexKeyword ([], start) 	= (([], start), Nothing)
lexKeyword (input, start)
	| C.isAlpha (head input) =	let 
					(identifier, rest) = span (\ c -> C.isAlphaNum c || c == '_') input
					end = start + (length identifier)
					in 
					((rest, end), Just [(assignToken identifier, U.Span start end )])
	| otherwise		 =	((input, start), Nothing)
	where assignToken str 	 = 	if isJust (lookup str reservedWords) 
					then fromJust (lookup str reservedWords)
					else Id str