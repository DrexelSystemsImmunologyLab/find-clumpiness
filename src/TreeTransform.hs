{- TreeTransform
By Gregory W. Schwartz

Collects functions pertaining to taking a Haskell tree of (Tree Label) and
converting it to a usable SuperNodeTree
-}

{-# LANGUAGE BangPatterns, ViewPatterns #-}

module TreeTransform
    ( convertToSuperTree
    , getPropertyMap
    , innerToLeaves
    , filterExclusiveTree
    , addUniqueNodeIDs
    ) where

-- Standard
import Control.Monad.State
import Data.Function (on)
import Data.Tree
import qualified Data.Foldable as F
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as Set

-- Cabal
import qualified Data.Text as T
import Math.TreeFun.Types
import Math.TreeFun.Tree
import TextShow (showt)

-- Local
import Types

-- | Convert the input tree to a SuperNodeTree
convertToSuperTree :: Tree NodeLabel -> Tree (SuperNode NodeLabel)
convertToSuperTree = toSuperNodeTree SuperRoot

-- | Convert inner nodes with labels to leaves
innerToLeaves :: Tree NodeLabel -> Tree NodeLabel
innerToLeaves n@(Node { subForest = [] }) = n
innerToLeaves n@( Node { rootLabel = NodeLabel { nodeLabels = (Seq.null -> True)
                                               }
                       }
                ) = n { subForest = map innerToLeaves . subForest $ n }
innerToLeaves n@( Node { rootLabel = NodeLabel { nodeID = x }
                       , subForest = xs
                       }
                ) =
    Node { rootLabel = NodeLabel {nodeID = T.cons 'S' x, nodeLabels = Seq.empty}
         , subForest = (n { subForest = [] }) : map innerToLeaves xs
         }

-- | Get the PropertyMap of a SuperNodeTree, ignoring nodes that have no
-- labels
getPropertyMap :: Tree (SuperNode NodeLabel) -> PropertyMap NodeLabel Label
getPropertyMap = Map.fromList
               . map (\ !x -> (myRootLabel x, nodeLabels . myRootLabel $ x))
               . filter (not . Seq.null . nodeLabels . myRootLabel)
               . leaves

-- | Change labels to be exclusive or not
filterExclusiveTree :: Exclusivity
                    -> Tree NodeLabel
                    -> Tree NodeLabel
filterExclusiveTree ex n =
    n { rootLabel = (rootLabel n) { nodeLabels = exclusiveLabel ex
                                               . nodeLabels
                                               . rootLabel
                                               $ n
                                  }
      , subForest = map (filterExclusiveTree ex) . subForest $ n
      }

-- | Transform the labels to be exclusive, non exclusive, or majority ruled
exclusiveLabel :: Exclusivity -> Labels -> Labels
exclusiveLabel _ (Seq.null -> True) = Seq.empty
exclusiveLabel AllExclusive xs      =
    Seq.fromList . Set.toList . Set.fromList . F.toList $ xs
exclusiveLabel Exclusive xs         =
    if Seq.length uniqueSeq > 1
        then Seq.empty
        else uniqueSeq
  where
    uniqueSeq = Seq.fromList . Set.toList . Set.fromList . F.toList $ xs
exclusiveLabel Majority xs          = Seq.singleton
                                    . fst
                                    . F.maximumBy (compare `on` snd)
                                    . Map.toList
                                    . Map.fromListWith (+)
                                    . flip zip [1,1..]
                                    . F.toList $ xs

-- | Add unique node IDs to a tree, replacing any previous node IDs.
addUniqueNodeIDs :: Tree NodeLabel -> Tree NodeLabel
addUniqueNodeIDs tree = fst . runState (go tree) $ 0
  where
    go :: Tree NodeLabel -> State Int (Tree NodeLabel)
    go tree = do
        newRootLabel <- updateRootLabel . rootLabel $ tree
        newSubForest <- mapM go . subForest $ tree
        return $ tree { rootLabel = newRootLabel
                      , subForest = newSubForest
                      }
    updateRootLabel :: NodeLabel -> State Int NodeLabel
    updateRootLabel n = do
        nId <- get
        modify (+ 1)
        return $ n { nodeID = showt nId }
