module SSALiveness where

import qualified Data.List as List
import qualified Data.Map as Map
import Data.Set (Set, union, unions)
import qualified Data.Set as Set

import Id
import Type
import SSA


genInst :: Inst -> Set VId
genInst (Inst _ o) = genOp o

genOp :: Op -> Set VId
genOp e = case e of
  SId o -> genOperand o
  SArithBin _ o1 o2 -> genOperand o1 `union` genOperand o2
  SFloatBin _ o1 o2 -> genOperand o1 `union` genOperand o2
  SCmpBin _ o1 o2 -> genOperand o1 `union` genOperand o2
  SNeg o -> genOperand o
  SFNeg o -> genOperand o
  SCall _ ls -> unions (map genOperand ls)
  SPhi ls -> unions $ map (\(_, o) -> genOperand o) ls

genOperand :: Operand -> Set VId
genOperand (OpVar (v :-: _)) = Set.singleton v
genOperand (OpConst _) = Set.empty

genTerm :: Term -> Set VId
genTerm (TRet o) = genOperand o
genTerm (TBr o _ _) = genOperand o
genTerm (TJmp _) = Set.empty

killInst :: Inst -> Set VId
killInst (Inst (Just v) _) = Set.singleton v
killInst (Inst Nothing _) = Set.empty

newtype LiveInfo = LiveInfo (Map.Map BlockID BlockLive) deriving (Eq)
data BlockLive = BlockLive ![InstLive] !TermLive deriving (Eq)
data InstLive = InstLive { liveIn :: !(Set VId), liveOut :: !(Set VId) } deriving (Eq)
type TermLive = InstLive

instance Show InstLive where
  show (InstLive i o) = "in=" ++ f i ++ ", out=" ++ f o where
    f liveset = show (Set.toList liveset)
instance Show BlockLive where
  show (BlockLive instl terml) = List.intercalate "\n" (map show $ instl ++ [terml])
instance Show LiveInfo where
  show (LiveInfo info) = List.intercalate "\n" (map (\i -> show i ++ "\n") $ Map.toList info)

nextOfTerm :: Term -> [BlockID]
nextOfTerm (TRet _) = []
nextOfTerm (TBr _ blk1 blk2) = [blk1, blk2]
nextOfTerm (TJmp blk) = [blk]

nextSets :: SSAFundef -> LiveInfo -> LiveInfo
nextSets (SSAFundef _ _ _ blks) (LiveInfo linfo) =
  LiveInfo $ Map.fromList $ map (g linfo) blks where
  g info (Block blk insts term) =
    let (BlockLive instl terml) = info Map.! blk in
    let len = length insts in
    let newIn i = (liveOut (instl !! i) `Set.difference` killInst (insts !! i)) `union` genInst (insts !! i) in
    let newOut i = liveIn ((instl ++ [terml]) !! (i + 1)) in
    let termIn = liveOut terml `union` genTerm term in
    let termOut = unions $ map (\blkID -> let BlockLive instl' terml' = info Map.! blkID in liveIn $ head $ instl' ++ [terml']) (nextOfTerm term) in
    (blk, BlockLive [InstLive (newIn i) (newOut i) | i <- [0 .. len - 1]] (InstLive termIn termOut))

minFix :: Eq q => (q -> q) -> q -> q
minFix f initVal = let e = f initVal in
  if e == initVal then initVal else minFix f e

analyzeLiveness :: SSAFundef -> LiveInfo
analyzeLiveness fundef@(SSAFundef _ _ _ blks) = minFix (nextSets fundef) w where
  w = LiveInfo $ Map.fromList $ map g blks where
  g (Block blk insts _) =
    let len = length insts in
    let emp = InstLive Set.empty Set.empty in
    let instl = replicate len emp in
    (blk, BlockLive instl emp)



