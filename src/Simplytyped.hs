module Simplytyped
  ( conversion
  ,    -- conversion a terminos localmente sin nombre
    eval
  ,          -- evaluador
    infer
  ,         -- inferidor de tipos
    quote          -- valores -> terminos
  )
where

import           Data.List
import           Data.Maybe
import           Prelude                 hiding ( (>>=) )
import           Text.PrettyPrint.HughesPJ      ( render )
import           PrettyPrinter
import           Common
import Common (LamTerm(LVar, LAbs))

-----------------------
-- conversion
-----------------------

-- conversion a términos localmente sin nombres
conversion :: LamTerm -> Term
conversion = conversionAux []

conversionAux :: [String] -> LamTerm -> Term
conversionAux xs (LApp t1 t2) = conversionAux xs t1 :@: conversionAux xs t2
conversionAux xs (LAbs var t term) = Lam t (conversionAux (var:xs) term)
conversionAux xs (LVar var) = case isBound var xs 0 of
                                Just i -> Bound i
                                Nothing -> Free (Global var)
conversionAux xs (LLet s t1 t) = Let (conversionAux xs t1) (conversionAux (s:xs) t)
conversionAux xs (LZero) = Zero
conversionAux xs (LSuc t) = Suc $ conversionAux xs t
conversionAux xs (LRec t1 t2 t3) = Rec (conversionAux xs t1) (conversionAux xs t2) (conversionAux xs t3)
conversionAux xs (LNil) = Nil 
conversionAux xs (LCons t u) = Cons (conversionAux xs t) (conversionAux xs u)

isBound :: String -> [String] -> Int -> Maybe Int
isBound var (v:vs) i = if var == v then Just i else isBound var vs (i+1)
isBound var [] _ = Nothing
----------------------------
--- evaluador de términos
----------------------------

-- substituye una variable por un término en otro término
sub :: Int -> Term -> Term -> Term
sub i t (Bound j) | i == j    = t
sub _ _ (Bound j) | otherwise = Bound j
sub _ _ (Free n   )           = Free n
sub i t (u   :@: v)           = sub i t u :@: sub i t v
sub i t (Lam t'  u)           = Lam t' (sub (i + 1) t u)
sub i t (Let u v)             = Let (sub i t u) (sub (i + 1) t v)
sub i t Zero                  = Zero
sub i t (Suc u)               = Suc (sub i t u)
sub i t (Rec u v w)           = Rec (sub i t u) (sub i t v) (sub i t w)
sub i t Nil                   = Nil
sub i t (Cons u v)            = Cons (sub i t u) (sub i t v)
sub i t (RL u v w)            = RL (sub i t u) (sub i t v) (sub i t w)

-- convierte un valor en el término equivalente
quote :: Value -> Term
quote (VLam t f) = Lam t f
quote (VNum NZero) = Zero
quote (VNum (NSuc n)) = Suc (quote (VNum n))
quote (VList VNil) = Nil
quote (VList (VCons n xs)) = Cons (quote (VNum n)) (quote (VList xs))

-- evalúa un término en un entorno dado
eval :: NameEnv Value Type -> Term -> Value

-- Variables
eval env (Free x) =
  case lookup x env of
    Just (v, _) -> v
    Nothing -> error $ "Variable " ++ show x ++ " no definida"

-- Abstracción (ya es un valor)
eval env (Lam t body) = VLam t body

-- Let binding (E-Let y E-LetV)
eval env (Let t1 t2) = 
  let v = eval env t1 
  in eval env (sub 0 (quote v) t2)

-- Aplicación (E-App1, E-App2, E-AppAbs)
eval env (t1 :@: t2) =
  case eval env t1 of
    VLam _ body ->
      let v2 = eval env t2
      in eval env (sub 0 (quote v2) body)
    _ -> error "Aplicación a un no-lambda"

eval env Zero = VNum NZero

eval env (Suc t) = 
  case eval env t of
    VNum n -> VNum (NSuc n)
    _ -> error "suc aplicado a un no-natural"

eval env (Rec t1 t2 t3) = 
  case eval env t3 of
    VNum NZero -> eval env t1
    VNum (NSuc n) -> 
      let rec_val = eval env (Rec t1 t2 (quote (VNum n)))
      in eval env (t2 :@: quote rec_val :@: quote (VNum n))
    _ -> error "R aplicado a un no-natural"

eval env Nil = VList VNil

eval env (Cons t1 t2) = 
  case (eval env t1, eval env t2) of
    (VNum n, VList xs) -> VList (VCons n xs)
    (VNum _, _) -> error "cons: segundo argumento debe ser una lista"
    (_, _) -> error "cons: primer argumento debe ser un natural"

eval env (RL t1 t2 t3) = 
  case eval env t3 of
    VList VNil -> eval env t1
    VList (VCons n xs) -> 
      let rec_val = eval env (RL t1 t2 (quote (VList xs)))
      in eval env (t2 :@: quote (VNum n) :@: quote (VList xs) :@: quote rec_val)
    _ -> error "RL aplicado a una no-lista"

----------------------
--- type checker
-----------------------

-- infiere el tipo de un término
infer :: NameEnv Value Type -> Term -> Either String Type
infer = infer' []

-- definiciones auxiliares
ret :: Type -> Either String Type
ret = Right

err :: String -> Either String Type
err = Left

(>>=)
  :: Either String Type -> (Type -> Either String Type) -> Either String Type
(>>=) v f = either Left f v
-- fcs. de error

matchError :: Type -> Type -> Either String Type
matchError t1 t2 =
  err
    $  "se esperaba "
    ++ render (printType t1)
    ++ ", pero "
    ++ render (printType t2)
    ++ " fue inferido."

notfunError :: Type -> Either String Type
notfunError t1 = err $ render (printType t1) ++ " no puede ser aplicado."

notfoundError :: Name -> Either String Type
notfoundError n = err $ show n ++ " no está definida."

-- infiere el tipo de un término a partir de un entorno local de variables y un entorno global
infer' :: Context -> NameEnv Value Type -> Term -> Either String Type
infer' c _ (Bound i) = ret (c !! i)
infer' _ e (Free  n) = case lookup n e of
  Nothing     -> notfoundError n
  Just (_, t) -> ret t
infer' c e (t :@: u) = infer' c e t >>= \tt -> infer' c e u >>= \tu ->
  case tt of
    FunT t1 t2 -> if (tu == t1) then ret t2 else matchError t1 tu
    _          -> notfunError tt
infer' c e (Lam t u) = infer' (t : c) e u >>= \tu -> ret $ FunT t tu
infer' c e (Let t1 t) = infer' c e t1 >>= \tt1 -> infer' (tt1 : c) e t >>= \tt -> ret tt
infer' c e Zero = ret NatT
infer' c e (Suc t) = do
  tt <- infer' c e t
  if tt == NatT
    then ret NatT
    else matchError NatT tt
infer' c e (Rec t1 t2 t3) = do
                              type1 <- infer' c e t1
                              type2 <- infer' c e t2
                              type3 <- infer' c e t3
                              if type3 == NatT then 
                                if type2 == FunT type1 (FunT NatT type1)
                                  then ret type1 else matchError (FunT type1 (FunT NatT type1)) type2
                                else matchError NatT type3
infer' c e Nil = ret ListT 
infer' c e (Cons t1 t2) = do
  type1 <- infer' c e t1
  type2 <- infer' c e t2
  if type1 == NatT
    then if type2 == ListT
           then ret ListT
           else matchError ListT type2
    else matchError NatT type1

infer' c e (RL t1 t2 t3) = do
  type1 <- infer' c e t1
  type2 <- infer' c e t2
  type3 <- infer' c e t3
  let expected = FunT NatT (FunT ListT (FunT type1 type1))
  if type2 == expected
    then if type3 == ListT
           then ret type1
           else matchError ListT type3
    else matchError expected type2