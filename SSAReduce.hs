module SSAReduce where

import Id
import SSA
import Type
import Syntax

reduceFundef :: SSAFundef -> SSAFundef
reduceFundef fundef@(SSAFundef {blocks = blks} ) =
  fundef { blocks = map (reduceBlock (map blkID blks)) blks }
  where blkID (Block x _ _) = x

reduceBlock :: [BlockID] -> Block -> Block
reduceBlock blkIDs (Block blkId insts term) = Block blkId (map g insts) (h term)
  where
    g (Inst dest op) = Inst dest $ case op of
      SArithBin Add x (OpConst (IntConst 0)) -> SId x
      SArithBin Sub x (OpConst (IntConst 0)) -> SId x
      SArithBin Mul x (OpConst (IntConst 0)) -> SId (OpConst (IntConst 0))
      SArithBin Mul x (OpConst (IntConst 1)) -> SId x
      SArithBin Mul x (OpConst (IntConst 2)) -> SArithBin Add x x
      SArithBin Add (OpConst t) (OpVar x) -> SArithBin Add (OpVar x) (OpConst t)
      SArithBin Mul (OpConst t) (OpVar x) -> SArithBin Mul (OpVar x) (OpConst t)
      SPhi ls ->
        let meanful = filter (\(x, _) -> elem x blkIDs) ls in
         if null meanful then error ("Phi node becomes null, original = " ++ show ls)
         else SPhi meanful 
      e -> e
    h (TBr _ blk1 blk2) | blk1 == blk2 = TJmp blk1
    h (TBr (OpConst (IntConst x)) blk1 blk2) = case x of
      1 -> TJmp blk1
      0 -> TJmp blk2
      _ -> error $ "condition must be 0 or 1, but got:" ++ show x
    h t = t


{- Performs operator strength reduction -}
reduce :: [SSAFundef] -> [SSAFundef]
reduce = map reduceFundef