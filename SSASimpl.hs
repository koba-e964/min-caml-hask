module SSASimpl where

import Id
import SSA
import Type
import Syntax
import qualified Data.Map as Map
import Control.Monad.Reader

import Data.Maybe
import qualified Data.List as List

import Debug.Trace

type Snippet = ([Inst], Term)
type BlockEnv = Map.Map BlockID Snippet

type M = Reader BlockEnv

simplFundef :: SSAFundef -> SSAFundef
simplFundef fundef@(SSAFundef {blocks = blks} ) =
  fundef { blocks = simplBlocks blks }

simplBlocks :: [Block] -> [Block]
simplBlocks blocks = f where
  ok blk@(Block blkID insts term) =
    if length insts >= 2 then Nothing else
      case term of
        TRet {} -> Just (blkID, (insts, term))
        _       -> Nothing
  env = Map.fromList $ catMaybes $ map ok blocks
  f = map (replace env) blocks



append :: Snippet -> Block -> Block
append (inst, term) (Block blkId insts _) = Block blkId (insts ++ renamedInst) renamedTerm where
  f (Inst d op, i) = case d of
    Just (VId dd) -> [(VId dd, VId (dd ++ "." ++ blkId ++ "." ++ show i))]
    Nothing -> []
  novum = Map.fromList $ concatMap f (zip inst [0..])
  renamedInst = map (replaceInst novum . removePhi blkId) inst
  renamedTerm = replaceTerm novum term

removePhi blkId (Inst d op) = Inst d $ case op of
  SPhi ls -> SId $ List.head $ map snd $ filter (\(x,_) -> x == blkId) $ ls
  _ -> op

replaceVId :: Map.Map VId VId -> VId -> VId
replaceVId env x =
  if Map.member x env then
    env Map.! x
  else x

replaceOperand :: Map.Map VId VId -> Operand -> Operand
replaceOperand env x@(OpConst _) = x
replaceOperand env (OpVar (v :-: t)) = OpVar (replaceVId env v :-: t)

replaceInst :: Map.Map VId VId -> Inst -> Inst
replaceInst env (Inst a op1) = Inst b op2 where
  b = case a of
    Nothing -> Nothing
    Just x -> Just $ replaceVId env x
  op2 = replaceOp env op1

replaceOp :: Map.Map VId VId -> Op -> Op
replaceOp env op = case op of
  SId x -> SId $ replaceOperand env x
  SArithBin o x y -> SArithBin o (replaceOperand env x) (replaceOperand env y)
  SFloatBin o x y -> SFloatBin o (replaceOperand env x) (replaceOperand env y)
  SCmpBin o x y -> SCmpBin o (replaceOperand env x) (replaceOperand env y)
  SNeg x -> SNeg (replaceOperand env x)
  SFNeg x -> SFNeg (replaceOperand env x)
  SCall lid args -> SCall lid (map (replaceOperand env) args)
  SPhi ls -> SPhi (map (\(blkID, x) -> (blkID, replaceOperand env x)) ls) 

replaceTerm :: Map.Map VId VId -> Term -> Term
replaceTerm env term = case term of
  TRet x -> TRet $ replaceOperand env x
  TBr x b1 b2 -> TBr (replaceOperand env x) b1 b2
  TJmp b -> TJmp b


replace :: BlockEnv -> Block -> Block
replace env blk@(Block blkId insts term) =
  case term of
    TJmp dest | blkId /= dest {- to avoid recursion -} && Map.member dest env ->
      append (env Map.! dest) blk
    _ -> blk
  


{- Simplifies the CFG. -}
simplify :: [SSAFundef] -> [SSAFundef]
simplify = map simplFundef
