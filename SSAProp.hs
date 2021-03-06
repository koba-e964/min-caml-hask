{-# LANGUAGE OverloadedStrings, FlexibleContexts, TypeOperators #-}
module SSAProp where

import Id
import SSA
import Type
import Control.Monad (when)
import Control.Monad.State (MonadState, evalState, get, modify)
import Data.Map (Map)
import qualified Data.Map as Map

type ConstEnv = Map VId Operand


propFundef :: SSAFundef -> SSAFundef
propFundef = mapEndoBlocks constPropBlock

constPropBlock :: [Block] -> [Block]
constPropBlock blk = evalState (mapM cpb =<< mapM cpb blk) Map.empty -- Applies twice in order to propagate constants backwards.

cpb :: (MonadState ConstEnv m) => Block -> m Block
cpb (Block blkId phi insts term) = do
  newPhi <- propPhi phi
  newInsts <- mapM propInst insts
  newTerm <- propTerm term
  return $ Block blkId newPhi newInsts newTerm

propPhi :: (MonadState ConstEnv m) => Phi -> m Phi
propPhi (Phi vars cols) = do
  env <- get
  return $ Phi vars $ fmap (map $ prop env) cols


propInst :: (MonadState ConstEnv m) => Inst -> m Inst
propInst (Inst dest op) = do
  env <- get
  result <- case op of
    SId c -> do
      case dest of
        Nothing -> return ()
        Just dest' -> modify (Map.insert dest' c)
      return $ SId c
    SArithBin operator x y ->
      return $ SArithBin operator (prop env x) (prop env y)
    SCmpBin operator x y ->
      return $ SCmpBin operator (prop env x) (prop env y)
    SNeg x ->
      return $ SNeg (prop env x)
    SFNeg x ->
      return $ SFNeg (prop env x)
    SFloatBin operator x y ->
      return $ SFloatBin operator (prop env x) (prop env y)
    SCall lid operands x ->
      return $ SCall lid (map (prop env) operands) x
  when (typeOfOp op == TUnit) $ do
    case dest of
      Nothing -> return ()
      Just dest' -> modify (Map.insert dest' (OpConst UnitConst))
  return $ Inst dest result

propTerm :: (MonadState ConstEnv m) => Term -> m Term
propTerm (TRet x) = do
  env <- get
  return $ TRet (prop env x)
propTerm (TBr x blk1 blk2) = do
  env <- get
  return $ TBr (prop env x) blk1 blk2
propTerm t@(TJmp {}) = return t

{- @prop env op@ returns op itself or constant assigned to @op@. -}
prop :: ConstEnv -> Operand -> Operand
prop env op = case op of
  OpVar (vid :-: _) | Map.member vid env -> env Map.! vid
  _ -> op

{- Performs constant propagation and copy propagation. This continues until no changes happen. -}
propagate :: [SSAFundef] -> [SSAFundef]
propagate = map $ minFix propFundef

