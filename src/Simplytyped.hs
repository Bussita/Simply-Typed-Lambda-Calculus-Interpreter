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
conversionAux xs (LRecL a b c) = RecL (conversionAux xs a) (conversionAux xs b) (conversionAux xs c)

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
sub i t (RecL t1 t2 t3)       = RecL (sub i t t1) (sub i t t2) (sub i t t3)

-- convierte un valor en el término equivalente
quote :: Value -> Term
quote (VLam t f) = Lam t f
quote (VNum n)  = quoteNat n
quote (VList xs) = quoteList xs

quoteNat :: NumVal -> Term
quoteNat NZero     = Zero
quoteNat (NSuc n) = Suc $ quoteNat n

quoteList :: ListVal -> Term
quoteList VNil          = Nil
quoteList (VCons n xs) = Cons (quoteNat n) (quoteList xs) 

-- evalúa un término en un entorno dado
eval :: NameEnv Value Type -> Term -> Value
eval _ (Bound j)        = error "[ERROR] Evaluacion de variable ligada."
eval env (Free x)       = case Prelude.lookup x env of
                            Just (v, t) -> v 
                            Nothing     -> error "[ERROR] Variable ausente en el entorno."

eval _ (Lam t f  )      = VLam t f

eval env (t1 :@: t2)    = let
                            (Lam t f) = quote (eval env t1)
                            t2'       = quote (eval env t2)
                            tsub      = sub 0 t2' f 
                          in eval env tsub

eval env (Let t1 t2)    = let
                            t1'  = quote (eval env t1)
                            tsub = sub 0 t1' t2
                          in
                            eval env tsub

eval _ Zero             = VNum NZero
eval env (Suc t)        = VNum (NSuc n) where (VNum n) = eval env t
eval env (Rec t1 t2 t3) = case eval env t3 of
                            VNum NZero     -> eval env t1
                            VNum (NSuc nv) -> eval env (t2 :@: Rec t1 t2 t :@: t) 
                                              where t = quoteNat nv

eval _ Nil              = VList VNil
eval env (Cons t1 t2)   = let
                            (VNum n)   = eval env t1
                            (VList lv) = eval env t2
                          in VList (VCons n lv)

eval env (RecL t1 t2 t3) = case eval env t3 of
                             VList VNil          -> eval env t1
                             VList (VCons nv lv) -> eval env (t2 :@: tn :@: tl :@: RecL t1 t2 tl)
                                                    where tn = quoteNat nv
                                                          tl = quoteList lv
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

notKArgError :: Type -> Int -> Either String Type
notKArgError t1 k = err $ render (printType t1) ++ " no puede ser aplicado " ++ show k ++ " veces."

notfoundError :: Name -> Either String Type
notfoundError n = err $ show n ++ " no está definida."

infer' :: Context -> NameEnv Value Type -> Term -> Either String Type
infer' c _ (Bound i)        = ret (c !! i)
infer' _ e (Free  n)        = case Prelude.lookup n e of 
                                Nothing     -> notfoundError n
                                Just (_, t) -> ret t
 
infer' c e (t :@: u)        = infer' c e t >>= \tt ->
                              infer' c e u >>= \tu ->
                              case tt of
                                FunT t1 t2 -> if (tu == t1)
                                              then ret t2
                                              else matchError t1 tu
                                _          -> notfunError tt

infer' c e (Lam t u)        = infer' (t : c) e u >>= \tu ->
                              ret $ FunT t tu

infer' c e (Let t1 t2)      = infer' c e t1 >>= \tt1 ->
                              infer' (tt1 : c) e t2  >>= \tt2 ->
                              ret tt2

infer' c e Zero             = ret NatT
infer' c e (Suc t)          = infer' c e t >>= \tt ->
                                case tt of 
                                  NatT -> ret NatT
                                  tt   -> matchError NatT tt


infer' c e (Rec t1 t2 t3)   = do
                              tt1 <- infer' c e t1
                              tt2 <- infer' c e t2
                              tt3 <- infer' c e t3
                              if (tt3 /= NatT)  then matchError NatT tt3  
                                                else case tt2 of 
                                                  (FunT  x (FunT y z)) -> if (x == tt1 && y == NatT && z == tt1)
                                                                          then ret tt1
                                                                          else matchError t tt2     
                                                                          where t = (FunT tt1 (FunT NatT tt1))
                                                  _                    -> notKArgError tt2 2

infer' c e Nil              = ret ListT
infer' c e (Cons t1 t2)     = do
                              tt1 <- infer' c e t1 
                              tt2 <- infer' c e t2
                              case tt1 of 
                                NatT -> if (tt2 == ListT)
                                        then ret tt2
                                        else matchError ListT tt2
                                _    -> matchError NatT tt1 

infer' c e (RecL t1 t2 t3)  = do
                              tt1 <- infer' c e t1 
                              tt2 <- infer' c e t2 
                              tt3 <- infer' c e t3  
                              if    (tt3 /= ListT)
                              then  matchError ListT tt3
                              else  case tt2 of
                                      (FunT x (FunT y (FunT z r)))  ->  if match
                                                                        then ret tt1
                                                                        else matchError t tt2
                                                                        where match = (x == NatT)  &&
                                                                                      (y == ListT) &&
                                                                                      (z == tt1)   &&
                                                                                      (r == tt1)
                                                                              t     = FunT NatT
                                                                                           (FunT ListT (FunT tt1 tt1))

                                      _                             ->  notKArgError tt2 3