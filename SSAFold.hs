module SSAFold where

import SSA
import Syntax

constFold :: [SSAFundef] -> [SSAFundef]
constFold = map cfFundef


cfFundef :: SSAFundef -> SSAFundef
cfFundef fundef@(SSAFundef { blocks = blk}) = 
  fundef { blocks = map f blk }
  where
    f (Block blkId insts term) = Block blkId (map g insts) term
    g (Inst dest op) = Inst dest $ case op of
      SNeg (OpConst (IntConst x)) -> SId (OpConst (IntConst (-x)))
      SArithBin operator (OpConst (IntConst x)) (OpConst (IntConst y)) ->
        SId $ OpConst $ IntConst $ case operator of
          Add -> x + y
          Sub -> x - y
          Mul -> x * y
          Div -> x `div` y

      SFNeg (OpConst (FloatConst x)) -> SId (OpConst (FloatConst (-x)))
      _ -> op

