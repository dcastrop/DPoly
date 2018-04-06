{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE EmptyCase #-}
module Language.Poly.Type
  ( Poly (..)
  , Sing (..)
  , Type (..)
  , (:@:)
  , app
  ) where

import Data.Kind hiding ( Type )

import Data.Text.Prettyprint.Doc ( Pretty, pretty )
import qualified Data.Text.Prettyprint.Doc as Pretty
import Data.Text.Prettyprint.EDoc

import Data.Singletons
import Data.Singletons.Decide

data Poly ty =
    PId
  | PK (Type ty)
  | PProd (Poly ty) (Poly ty)
  | PSum (Poly ty) (Poly ty)
  deriving Eq

data instance Sing (p :: Poly ty) where
  SPId :: Sing 'PId
  SPK  :: Sing t -> Sing ('PK t)
  SPProd :: Sing p1 -> Sing p2 -> Sing ('PProd p1 p2)
  SPSum :: Sing p1 -> Sing p2 -> Sing ('PSum p1 p2)

injSPK :: 'PK t1 :~: 'PK t2 -> t1 :~: t2
injSPK Refl = Refl

injPProd :: 'PProd t1 t3 :~: 'PProd t2 t4 -> (t1 :~: t2, t3 :~: t4)
injPProd Refl = (Refl, Refl)

injPSum :: 'PSum t1 t3 :~: 'PSum t2 t4 -> (t1 :~: t2, t3 :~: t4)
injPSum Refl = (Refl, Refl)

instance SDecide ty => SDecide (Poly ty) where
  SPId %~ SPId = Proved Refl
  SPK t1 %~ SPK t2 = case t1 %~ t2 of
                        Proved Refl -> Proved Refl
                        Disproved f -> Disproved (\pr -> f (injSPK pr))
  SPProd t1 t3 %~ SPProd t2 t4 =
    case (t1 %~ t2, t3 %~ t4) of
      (Proved Refl, Proved Refl) -> Proved Refl
      (Disproved f, _)           -> Disproved (\pr -> f (fst $ injPProd pr))
      (_, Disproved f)           -> Disproved (\pr -> f (snd $ injPProd pr))
  SPSum t1 t3 %~ SPSum t2 t4 =
    case (t1 %~ t2, t3 %~ t4) of
      (Proved Refl, Proved Refl) -> Proved Refl
      (Disproved f, _)           -> Disproved (\pr -> f (fst $ injPSum pr))
      (_, Disproved f)           -> Disproved (\pr -> f (snd $ injPSum pr))
  _ %~ _ = Disproved (\pr -> case pr of {} ) -- Why no warning???


instance SingI 'PId where
  sing = SPId
instance SingI t => SingI ('PK t) where
  sing = SPK sing
instance (SingI p1, SingI p2) => SingI ('PProd p1 p2) where
  sing = SPProd sing sing
instance (SingI p1, SingI p2) => SingI ('PSum p1 p2) where
  sing = SPSum sing sing

instance SingKind ty => SingKind (Poly ty) where
  type DemoteRep (Poly ty) = Poly (DemoteRep ty)

  fromSing SPId = PId
  fromSing (SPK t) = PK (fromSing t)
  fromSing (SPProd p1 p2) = PProd (fromSing p1) (fromSing p2)
  fromSing (SPSum p1 p2) = PSum (fromSing p1) (fromSing p2)

  toSing PId = SomeSing SPId
  toSing (PK t) = case toSing t of
                    SomeSing k -> SomeSing (SPK k)
  toSing (PProd p1 p2) =
      case (toSing p1, toSing p2) of
        (SomeSing t1, SomeSing t2) -> SomeSing $ SPProd t1 t2
  toSing (PSum p1 p2) =
      case (toSing p1, toSing p2) of
          (SomeSing t1, SomeSing t2) -> SomeSing $ SPSum t1 t2

infixr 4 :->

data Type ty =
    TUnit
  | TPrim ty
  | TProd (Type ty) (Type ty)
  | TSum (Type ty) (Type ty)
  | TFix (Poly ty)
  | Type ty :-> Type ty
  deriving Eq

injPrim :: 'TPrim t1 :~: 'TPrim t2 -> t1 :~: t2
injPrim Refl = Refl

injSum :: 'TSum t1 t3 :~: 'TSum t2 t4 -> (t1 :~: t2, t3 :~: t4)
injSum Refl = (Refl, Refl)

injProd :: 'TProd t1 t3 :~: 'TProd t2 t4 -> (t1 :~: t2, t3 :~: t4)
injProd Refl = (Refl, Refl)

injFix :: 'TFix t1 :~: 'TFix t2 -> t1 :~: t2
injFix Refl = Refl

injArr :: (t1 ':-> t3) :~: (t2 ':-> t4) -> (t1 :~: t2, t3 :~: t4)
injArr Refl = (Refl, Refl)

data instance Sing (t :: Type ty) where
  STUnit :: Sing 'TUnit
  STPrim :: Sing t  -> Sing ('TPrim t)
  STProd :: Sing t1 -> Sing t2 -> Sing ('TProd t1 t2)
  STSum  :: Sing t1 -> Sing t2 -> Sing ('TSum  t1 t2)
  STFix  :: Sing p  -> Sing ('TFix p)
  STArr  :: Sing t1 -> Sing t2 -> Sing (t1 ':-> t2)

instance SDecide ty => SDecide (Type ty) where
  STUnit     %~ STUnit     = Proved Refl
  STPrim a   %~ STPrim c   =
    case a %~ c of
      Proved Refl -> Proved Refl
      Disproved f -> Disproved (\pr -> f (injPrim pr))
  STProd a b %~ STProd c d =
    case (a %~ c, b %~ d) of
      (Proved Refl, Proved Refl) -> Proved Refl
      (Disproved f, _)           -> Disproved (\pr -> f (fst $ injProd pr))
      (_, Disproved f)           -> Disproved (\pr -> f (snd $ injProd pr))
  STSum  a b %~ STSum  c d =
    case (a %~ c, b %~ d) of
      (Proved Refl, Proved Refl) -> Proved Refl
      (Disproved f, _)           -> Disproved (\pr -> f (fst $ injSum pr))
      (_, Disproved f)           -> Disproved (\pr -> f (snd $ injSum pr))
  STFix  a   %~ STFix  c =
    case a %~ c of
      Proved Refl -> Proved Refl
      Disproved f -> Disproved (\pr -> f (injFix pr))
  STArr  a b %~ STArr  c d =
    case (a %~ c, b %~ d) of
      (Proved Refl, Proved Refl) -> Proved Refl
      (Disproved f, _)           -> Disproved (\pr -> f (fst $ injArr pr))
      (_, Disproved f)           -> Disproved (\pr -> f (snd $ injArr pr))
  _ %~ _ = Disproved (\pr -> case pr of {}) -- HACK AGAIN! Need to list all cases





instance SingI 'TUnit where
  sing = STUnit
instance SingI t => SingI ('TPrim t) where
  sing = STPrim sing
instance (SingI p1, SingI p2) => SingI ('TProd p1 p2) where
  sing = STProd sing sing
instance (SingI p1, SingI p2) => SingI ('TSum p1 p2) where
  sing = STSum sing sing
instance SingI p1 => SingI ('TFix p1) where
  sing = STFix sing
instance (SingI p1, SingI p2) => SingI (p1 ':-> p2) where
  sing = STArr sing sing

instance SingKind ty => SingKind (Type ty) where
  type DemoteRep (Type ty) = Type (DemoteRep ty)

  fromSing STUnit = TUnit
  fromSing (STPrim t) = TPrim $ fromSing t
  fromSing (STProd t1 t2) = TProd (fromSing t1) (fromSing t2)
  fromSing (STSum t1 t2) = TSum (fromSing t1) (fromSing t2)
  fromSing (STFix p) = TFix (fromSing p)
  fromSing (STArr t1 t2) = fromSing t1 :-> fromSing t2

  toSing TUnit = SomeSing STUnit
  toSing (TPrim (toSing -> SomeSing t)) = SomeSing $ STPrim t
  toSing (TProd (toSing -> SomeSing t1) (toSing -> SomeSing t2)) =
      SomeSing $ STProd t1 t2
  toSing (TSum (toSing -> SomeSing t1) (toSing -> SomeSing t2)) =
      SomeSing $ STSum t1 t2
  toSing (TFix (toSing -> SomeSing p)) = SomeSing $ STFix p
  toSing ((toSing -> SomeSing t1) :-> (toSing -> SomeSing t2)) =
      SomeSing $ STArr t1 t2

infixl 5 :@:

type family (:@:) (p :: Poly ty) (t :: Type ty) :: Type ty where
  'PK c :@: t = c
  'PId :@: t = t
  'PProd p1 p2 :@: t = 'TProd (p1 :@: t) (p2 :@: t)
  'PSum p1 p2 :@: t = 'TSum (p1 :@: t) (p2 :@: t)

app :: forall (ty :: *) (p :: Poly ty) (t :: Type ty). Sing p -> Sing t -> Sing (p :@: t)
app SPId           t = t
app (SPK c)       _t = c
app (SPProd p1 p2) t = STProd (p1 `app` t) (p2 `app` t)
app (SPSum p1 p2)  t = STSum  (p1 `app` t) (p2 `app` t)

--------------------------------------------------------------------------
-- Pretty printing instances

-- Precedences: XXX fix quoted-prettyprinter to handle these cases without so
-- much boilerplate. Ideally, a predicate would be enough!
newtype ParK p = ParK (Type p)
instance Pretty p => Pretty (ParK p)
  where
    pretty (ParK p@TUnit) = pretty p
    pretty (ParK p      ) = Pretty.parens (pretty p)

newtype ParPPL p = ParPPL (Poly p)
instance Pretty p => Pretty (ParPPL p)
  where
    pretty (ParPPL p@PSum{}) = Pretty.parens (pretty p)
    pretty (ParPPL p) = pretty p

newtype ParPId p = ParPId (Poly p)
instance Pretty p => Pretty (ParPId p)
  where
    pretty (ParPId p@PId) = pretty p
    pretty (ParPId p    ) = Pretty.parens (pretty p)

newtype ParPPR p = ParPPR (Poly p)
instance Pretty p => Pretty (ParPPR p)
  where
    pretty (ParPPR p@PId) = pretty p
    pretty (ParPPR p@PK{}) = pretty p
    pretty (ParPPR p    ) = Pretty.parens (pretty p)

newtype ParSPL p = ParSPL (Poly p)
instance Pretty p => Pretty (ParSPL p)
  where
    pretty (ParSPL p) = pretty p

newtype ParSPR p = ParSPR (Poly p)
instance Pretty p => Pretty (ParSPR p)
  where
    pretty (ParSPR p@PSum{}    ) = Pretty.parens (pretty p)
    pretty (ParSPR p) = pretty p

newtype ParFunL ty = PFL (Type ty)
instance Pretty ty => Pretty (ParFunL ty)
  where
    pretty (PFL t@(_t1 :-> _t2)) = Pretty.parens [ppr| t |]
    pretty (PFL t)               = [ppr| t |]

newtype ParPL p = ParPL (Type p)
instance Pretty p => Pretty (ParPL p)
  where
    pretty (ParPL p@(_t1 :-> _t2)) = Pretty.parens [ppr| p |]
    pretty (ParPL p@TSum{}) = Pretty.parens [ppr| p |]
    pretty (ParPL p) = [ppr| p |]

newtype ParPR p = ParPR (Type p)
instance Pretty p => Pretty (ParPR p)
  where
    pretty (ParPR p@(_t1 :-> _t2)) = Pretty.parens [ppr| p |]
    pretty (ParPR p@TSum{}) = Pretty.parens [ppr| p |]
    pretty (ParPR p@TProd{}) = Pretty.parens [ppr| p |]
    pretty (ParPR p) = [ppr| p |]

newtype ParSL p = ParSL (Type p)
instance Pretty p => Pretty (ParSL p)
  where
    pretty (ParSL p@(_t1 :-> _t2)) = Pretty.parens [ppr| p |]
    pretty (ParSL p) = [ppr| p |]

newtype ParSR p = ParSR (Type p)
instance Pretty p => Pretty (ParSR p)
  where
    pretty (ParSR p@(_t1 :-> _t2)) = Pretty.parens [ppr| p |]
    pretty (ParSR p@TSum{}) = Pretty.parens [ppr| p |]
    pretty (ParSR p) = [ppr| p |]
-- end precedences

instance Pretty ty => Pretty (Poly ty)
  where
    pretty PId           = [ppr| "I" |]
    pretty (PK p)        = [ppr| "K" > ParK p |]
    pretty (PProd p1 p2) = [ppr| ParPPL p1 + ":*:" + ParPPR p2 |]
    pretty (PSum p1 p2)  = [ppr| ParSPL p1 + ":+:" + ParSPR p2 |]

instance Pretty ty => Pretty (Type ty)
  where
    pretty TUnit         = [ppr| "unit" |]
    pretty (TPrim t)     = pretty t
    pretty (TProd t1 t2) = [ppr| ParPL t1 + "*" + ParPR t2 |]
    pretty (TSum  t1 t2) = [ppr| ParSL t1 + "+" + ParSR t2 |]
    pretty (TFix  p)     = [ppr| "fix" + ParPId p |]
    pretty (t1 :-> t2)   = [ppr| PFL t1 + "->" + t2|]
