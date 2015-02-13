module Main where

import Control.Monad.Reader (runReader)
import qualified Data.Map as Map
import System.Console.GetOpt
import System.Environment

import qualified MLexer
import Id
import Type
import MParser (parse)
import Typing
import KNormal (kNormal)
import Alpha (alpha)
import SSA
import SSAProp
import SSAFold
import SSAReduce
import SSASimpl
import SSAElim
import SSALiveness
import Closure (CVardef, CFundef(..), trans)
{-
import RegAlloc
import PhiElim
import Emit
-}

data Config = Config { threshold :: !Int, limit :: !Int, glib :: ![String] }

options :: [OptDescr (Config -> Config)]
options =
  [ Option [] ["inline"] (ReqArg (\s conf -> conf { threshold = read s }) "max size of inlining") "max size of inlined function"
  , Option [] ["iter"] (ReqArg (\s conf -> conf { limit = read s }) "opt iteration") "maximum number of optimizations iterated"
  , Option [] ["glib"] (ReqArg (\s conf -> conf { glib = s : glib conf }) "library") "ml libraries"
  ] 

parseOpt :: [String] -> (Config, [String])
parseOpt argv =
  let (dat, nonOpts, errs) = getOpt Permute options argv in
  if null errs then
    (foldl (.) id dat (Config 0 1000 []), nonOpts)
  else
    error ("error on parsing command line:" ++ show errs)

usage :: String
usage = "MinCaml on Haskell\n"
      ++ "usage: min-caml [--inline m] [--iter n] ...filenames without \".ml\"..."


extenv :: TypeEnv
extenv = Map.fromList
  [(Id "print_int", TFun [TInt] TUnit)
  ]

repl :: String -> IO ()
repl str = do
  let lexed = MLexer.lex str
  print lexed
  let syntax = parse lexed
  putStrLn "AST:"
  print syntax
  case syntax of
    Right syn -> do
　　　　　　let typed = either (error . show) id (typing extenv syn)
      putStrLn "Typed AST:"
      print typed
      let kn = kNormal extenv typed
      putStrLn "k-normal form:"
      print kn
      let al = alpha kn
      print al
      let (cexp, cfuns) = trans al
      putStrLn "closure transformed:"
      mapM_ print cfuns
      print cexp
      let ssa = runReader (runCounterT (ssaTrans cfuns cexp))
            (Map.fromList (map (\(CFundef {Closure.name = (VId n,ty)}) -> (Id n, ty)) cfuns) `Map.union` extenv)
      putStrLn "ssa:"
      print ssa
      putStrLn "**** optimized SSA ****"
      let optSSA = iterate (eliminate . simplify . reduce . constFold . propagate) ssa !! 10
      print optSSA
      mapM_ print (map analyzeLiveness optSSA)
{-
      putStrLn "**** register-allocated SSA ****"
      let regSSA = regAlloc optSSA
      print regSSA
      putStrLn "**** Phi-eliminated SSA ****"
      let peSSA = elimPhi regSSA
      print peSSA
      let insts = emit peSSA
      mapM_ print insts
-}
    Left x -> error x

processLib :: [String] -> IO (TypeEnv, [CVardef])
processLib = undefined


main :: IO ()
main = do
  argv <- getArgs
  let (_conf, files) = parseOpt argv
  if null files then do
    putStrLn usage
    str <- getContents
    repl str
  else
    print files
    
