{
module Parse where
import Common
import Data.Maybe
import Data.Char
}

%monad { P } { thenP } { returnP }
%name parseStmt Def
%name parseStmts Defs
%name term Exp

%tokentype { Token }
%lexer {lexer} {TEOF}

%token
    '='     { TEquals }
    ':'     { TColon }
    '\\'    { TAbs }
    '.'     { TDot }
    '('     { TOpen }
    ')'     { TClose }
    '['     { TOpenB }
    ']'     { TCloseB }
    ','     { TComma }
    '->'    { TArrow }
    VAR     { TVar $$ }
    NUM     { TNum $$ }
    TYPEE   { TTypeE }
    DEF     { TDef }
    LET     { TLet }
    IN      { TIn }
    R       { TR }
    SUC     { TSuc }
    NIL     { TNil }
    CONS    { TCons }

%left '=' 
%right '->'
%left 'cons'
%left 'R'
%left 'suc'
%right '\\' '.'

%%

Def     :  Defexp                      { $1 }
        |  Exp	                       { Eval $1 }
Defexp  : DEF VAR '=' Exp              { Def $2 $4 } 

Exp     :: { LamTerm }
        : '\\' VAR ':' Type '.' Exp    { LAbs $2 $4 $6 }
        | NAbs1                        { $1 }
        
NAbs1   :: { LamTerm }
        : R Exp Exp Exp                { LRec $2 $3 $4 }
        | NAbs2                        { $1 }

NAbs2   :: { LamTerm }
        : CONS Atom Atom               { LCons $2 $3 }
        | NAbs3                        { $1 }

NAbs3   :: { LamTerm }
        : SUC Exp                      { LSuc $2 }
        | NAbs4                        { $1 }

NAbs4   :: { LamTerm }
        : NAbs4 Atom                   { LApp $1 $2 }
        | Atom                         { $1 }

Atom    :: { LamTerm }
        : VAR                          { LVar $1 }  
        | '(' Exp ')'                  { $2 }
        | LET VAR '=' Exp IN Exp       { LLet $2 $4 $6 }
        | NIL                          { LNil }
        | '[' ']'                      { LNil }
        | '[' Ints ']'                 { makeListFromInts $2 }
        | NUM                          { makeNumTerm (read $1) }

Ints    :: { [Int] }
        : NUM                          { [ read $1 ] }
        | NUM ',' Ints                 { read $1 : $3 }

Type    : TYPEE                        { EmptyT }
        | Type '->' Type               { FunT $1 $3 }
        | '(' Type ')'                 { $2 }

Defs    : Defexp Defs                  { $1 : $2 }
        |                              { [] }
     
{

data ParseResult a = Ok a | Failed String
                     deriving Show                     
type LineNumber = Int
type P a = String -> LineNumber -> ParseResult a

getLineNo :: P LineNumber
getLineNo = \s l -> Ok l

thenP :: P a -> (a -> P b) -> P b
m `thenP` k = \s l-> case m s l of
                         Ok a     -> k a s l
                         Failed e -> Failed e
                         
returnP :: a -> P a
returnP a = \s l-> Ok a

failP :: String -> P a
failP err = \s l -> Failed err

catchP :: P a -> (String -> P a) -> P a
catchP m k = \s l -> case m s l of
                        Ok a     -> Ok a
                        Failed e -> k e s l

happyError :: P a
happyError = \ s i -> Failed $ "Línea "++(show (i::LineNumber))++": Error de parseo\n"++(s)

data Token = TVar String
               | TTypeE
               | TDef
               | TAbs
               | TDot
               | TOpen
               | TClose 
               | TColon
               | TArrow
               | TEquals
               | TLet
               | TIn
               | TEOF
               | TOpenB
               | TCloseB
               | TComma
               | TNum String
               | TR
               | TSuc
               | TNil
               | TCons
               deriving Show

----------------------------------
lexer cont s = case s of
                    [] -> cont TEOF []
                    ('\n':s)  ->  \line -> lexer cont s (line + 1)
                    (c:cs)
                          | isSpace c -> lexer cont cs
                          | isAlpha c -> lexVar (c:cs)
                          | isDigit c -> lexNum (c:cs)
                    ('-':('-':cs)) -> lexer cont $ dropWhile ((/=) '\n') cs
                    ('{':('-':cs)) -> consumirBK 0 0 cont cs	
                    ('-':('}':cs)) -> \ line -> Failed $ "Línea "++(show line)++": Comentario no abierto"
                    ('-':('>':cs)) -> cont TArrow cs
                    ('\\':cs)-> cont TAbs cs
                    ('.':cs) -> cont TDot cs
                    ('(':cs) -> cont TOpen cs
                    (')':cs) -> cont TClose cs
                    ('[':cs) -> cont TOpenB cs
                    (']':cs) -> cont TCloseB cs
                    (',':cs) -> cont TComma cs
                    (':':cs) -> cont TColon cs
                    ('=':cs) -> cont TEquals cs
                    unknown -> \line -> Failed $ 
                     "Línea "++(show line)++": No se puede reconocer "++(show $ take 10 unknown)++ "..."
                    where lexVar cs = case span isAlpha cs of
                              ("R",rest)    -> cont TR rest
                              ("E",rest)    -> cont TTypeE rest
                              ("def",rest)  -> cont TDef rest
                              ("let",rest)  -> cont TLet rest
                              ("in",rest)   -> cont TIn rest
                              ("suc",rest)  -> cont TSuc rest
                              ("nil",rest)  -> cont TNil rest
                              ("cons",rest) -> cont TCons rest
                              (var,rest)    -> cont (TVar var) rest
                          lexNum cs = case span isDigit cs of
                              (num,rest) -> cont (TNum num) rest
                          consumirBK anidado cl cont s = case s of
                              ('-':('-':cs)) -> consumirBK anidado cl cont $ dropWhile ((/=) '\n') cs
                              ('{':('-':cs)) -> consumirBK (anidado+1) cl cont cs	
                              ('-':('}':cs)) -> case anidado of
                                                  0 -> \line -> lexer cont cs (line+cl)
                                                  _ -> consumirBK (anidado-1) cl cont cs
                              ('\n':cs) -> consumirBK anidado (cl+1) cont cs
                              (_:cs) -> consumirBK anidado cl cont cs     

makeNumTerm :: Int -> LamTerm
makeNumTerm 0 = LZero
makeNumTerm n | n > 0 = LSuc (makeNumTerm (n-1))
makeNumTerm _ = LZero

makeListFromInts :: [Int] -> LamTerm
makeListFromInts [] = LNil
makeListFromInts (x:xs) = LCons (makeNumTerm x) (makeListFromInts xs)
                                           
stmts_parse s = parseStmts s 1
stmt_parse s = parseStmt s 1
term_parse s = term s 1
}