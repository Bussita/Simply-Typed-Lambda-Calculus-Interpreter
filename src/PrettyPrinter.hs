module PrettyPrinter
  ( printTerm  ,     -- pretty printer para terminos
    printType        -- pretty printer para tipos
  )
where

import  Common
import  Text.PrettyPrint.HughesPJ
import  Prelude hiding ((<>))

-- lista de posibles nombres para variables
vars :: [String]
vars =
  [ c : n
  | n <- "" : map show [(1 :: Integer) ..]
  , c <- ['x', 'y', 'z'] ++ ['a' .. 'w']
  ]

parensIf :: Bool -> Doc -> Doc
parensIf True  = parens
parensIf False = id

-- pretty-printer de términos

pp :: Int -> [String] -> Term -> Doc
pp ii vs (Bound k         ) = text (vs !! (ii - k - 1))
pp _  _  (Free  (Global s)) = text s
pp ii vs (i :@: c         ) = sep
  [ parensIf (isLam i || isLet i) (pp ii vs i)
  , nest 1 (parensIf (isLam c || isApp c) (pp ii vs c))
  ]
pp ii vs (Lam t c) =
  text "\\"
    <> text (vs !! ii)
    <> text ":"
    <> printType t
    <> text ". "
    <> pp (ii + 1) vs c
pp ii vs (Let t u) =
  sep
    [ text "let "
        <> text (vs !! ii)
        <> text " = "
        <> parens (pp ii vs t)
    , text " in "
        <> parens (pp (ii + 1) vs u)
    ]
pp ii vs Zero = text "0"
pp ii vs (Suc t) = text "suc " <> parensIf (isApp t || isLam t || isLet t) (pp ii vs t)
pp ii vs (Rec t1 t2 t3) =
  sep [ text "R"
      , nest 1 (pp ii vs t1)
      , nest 1 (pp ii vs t2)
      , nest 1 (pp ii vs t3)
      ]
pp ii vs Nil = text "[]"
pp ii vs (Cons t1 t2) =
  case termToListInts (Cons t1 t2) of
    Just xs ->
      brackets (hcat (punctuate (text ",") (map (text . show) xs)))
    Nothing ->
      sep
        [ text "cons "
            <> parens (pp ii vs t1)
        , parens (pp ii vs t2)
        ]

isLam :: Term -> Bool
isLam (Lam _ _) = True
isLam _         = False

isLet :: Term -> Bool
isLet (Let _ _) = True
isLet _         = False

isApp :: Term -> Bool
isApp (_ :@: _) = True
isApp _         = False

-- pretty-printer de tipos
printType :: Type -> Doc
printType EmptyT = text "E"
printType (FunT t1 t2) =
  sep [parensIf (isFun t1) (printType t1), text "->", printType t2]


isFun :: Type -> Bool
isFun (FunT _ _) = True
isFun _          = False

fv :: Term -> [String]
fv (Bound _         ) = []
fv (Free  (Global n)) = [n]
fv (t   :@: u       ) = fv t ++ fv u
fv (Lam _   u       ) = fv u
fv (Let t u         ) = fv t ++ fv u

---
printTerm :: Term -> Doc
printTerm t = pp 0 (filter (\v -> not $ elem v (fv t)) vars) t

-- Convierte un Term numeral (Zero / Suc ...) a Maybe Int
termToInt :: Term -> Maybe Int
termToInt Zero     = Just 0
termToInt (Suc t)  = fmap (+ 1) (termToInt t)
termToInt _        = Nothing

-- Convierte una lista construida con Cons/ Nil donde cada cabeza es numeral a Maybe [Int]
termToListInts :: Term -> Maybe [Int]
termToListInts Nil = Just []
termToListInts (Cons h t) = do
  n  <- termToInt h
  ns <- termToListInts t
  return (n : ns)
termToListInts _ = Nothing

