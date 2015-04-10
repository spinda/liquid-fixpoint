{-# LANGUAGE PatternGuards #-}
module Language.Fixpoint.Solver.Solution
        ( -- * Solutions and Results
          Solution

          -- * Initial Solution
        , init
        )
where

import           Control.Applicative            ((<$>))
import qualified Data.HashMap.Strict            as M
import qualified Data.List                      as L
import           Data.Maybe                     (isNothing, fromMaybe)
import           Language.Fixpoint.Config
import           Language.Fixpoint.Solver.Monad
import           Language.Fixpoint.Sort
import           Language.Fixpoint.Misc
import qualified Language.Fixpoint.Types        as F
import           Prelude                        hiding (init)

---------------------------------------------------------------------
-- | Types ----------------------------------------------------------
---------------------------------------------------------------------
type Solution = Sol KBind
type Sol a    = M.HashMap F.KVar a
type KBind    = [EQual]

---------------------------------------------------------------------
-- | Expanded or Instantiated Qualifier -----------------------------
---------------------------------------------------------------------

data EQual = EQ { eqQual :: !F.Qualifier
                , eqPred :: !F.Pred
                , eqArgs :: ![F.Expr]
                }
               deriving (Eq, Ord, Show)

{-@ data EQual = EQ { eqQual :: F.Qualifier
                    , eqPred :: F.Pred
                    , eqArgs :: {v: [F.Expr] | len v = len (q_params eqQual)}
                    }
  @-}

eQual :: F.Qualifier -> [F.Symbol] -> EQual
eQual q xs = error "TODO:eQual"

--------------------------------------------------------------------
-- | Create Initial Solution from Qualifiers and WF constraints ----
--------------------------------------------------------------------
init :: Config -> F.FInfo a -> Solution
--------------------------------------------------------------------
init _ fi = L.foldl' (refine fi qs) s0 ws
  where
    s0    = M.empty
    qs    = F.quals fi
    ws    = F.ws    fi

--------------------------------------------------------------------
refine :: F.FInfo a
       -> [F.Qualifier]
       -> Solution
       -> F.WfC a
       -> Solution
--------------------------------------------------------------------
refine fi qs s w = refineK (wfEnv fi w) qs s (wfKvar w)


refineK :: F.SEnv F.SortedReft
        -> [F.Qualifier]
        -> Solution
        -> (F.Symbol, F.Sort, F.KVar)
        -> Solution
refineK env qs s (v, t, k) = M.insert k eqs' s
  where
    eqs' = case M.lookup k s of
             Nothing  -> instK env v t qs
             Just eqs -> [eq | eq <- eqs, okInst env v t eq]

--------------------------------------------------------------------
instK :: F.SEnv F.SortedReft
      -> F.Symbol
      -> F.Sort
      -> [F.Qualifier]
      -> [EQual]
--------------------------------------------------------------------
instK env v t = concatMap (instKQ env v t)

instKQ :: F.SEnv F.SortedReft
       -> F.Symbol
       -> F.Sort
       -> F.Qualifier
       -> [EQual]
instKQ env v t q
  = do (su0, v0) <- candidates [(v, t)] qt
       xs        <- match xts [v0] (apply su0 <$> qts)
       return     $ eQual q (reverse xs)
    where
       qt : qts   = snd <$> F.q_params q
       xts        = F.toListSEnv (F.sr_sort <$> env)

match :: [(F.Symbol, F.Sort)] -> [F.Symbol] -> [F.Sort] -> [[F.Symbol]]
match xts xs (t : ts)
  = do (su, x) <- candidates xts t
       match xts (x : xs) (apply su <$> ts)
match _   xs []
  = return xs


-----------------------------------------------------------------------
candidates :: [(F.Symbol, F.Sort)] -> F.Sort -> [(TVSubst, F.Symbol)]
-----------------------------------------------------------------------
candidates xts t'
  = [(su, x) | (x, t) <- xts, su <- maybeList $ unify t' t]

maybeList :: Maybe a -> [a]
maybeList (Just x)  = [x]
maybeList (Nothing) = []


-----------------------------------------------------------------------
wfKvar :: F.WfC a -> (F.Symbol, F.Sort, F.Symbol)
-----------------------------------------------------------------------
wfKvar w@(F.WfC {F.wrft = sr})
  | F.Reft (v, F.Refa (F.PKVar k su)) <- F.sr_reft sr
  , F.isEmptySubst su = (v, F.sr_sort sr, k)
  | otherwise         = errorstar $ "wfKvar: malformed wfC " ++ show w

wfEnv :: F.FInfo a -> F.WfC a -> F.SEnv F.SortedReft
wfEnv fi w  = F.fromListSEnv xts
  where
    wbinds  = F.elemsIBindEnv $ F.wenv w
    bm      = F.bs fi
    xts     = [ F.lookupBindEnv i bm | i <- wbinds]

-----------------------------------------------------------------------
okInst :: F.SEnv F.SortedReft -> F.Symbol -> F.Sort -> EQual -> Bool
-----------------------------------------------------------------------
okInst env v t eq = isNothing $ checkSortedReftFull env sr
  where
    sr            = F.RR t (F.Reft (v, F.Refa (eqPred eq)))
