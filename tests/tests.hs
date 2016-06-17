module Main where

import Data.Functor.Identity
import Data.IORef
import Test.Tasty
import Test.Tasty.HUnit
-- import Test.Tasty.QuickCheck

import qualified Control.Foldl           as Foldl
import Streaming
import qualified Streaming.Prelude       as S
import Streaming.Eversion

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "tests" 
    [ 
        testGroup "evert"
        [
            testCaseEq
            "empty"
            ([]::[Integer])
            (Foldl.fold (evert S.toList) [])
        ,   testCaseEq
            "toList"
            [1..10::Integer]
            (Foldl.fold (evert S.toList) [1..10])
        ]
    ,   testGroup "evertM"
        [
            testCaseEq
            "empty"
            ([]::[Integer])
            (runIdentity (Foldl.foldM (evertM S.toList) []))
        ,   testCaseEq
            "toList"
            [1..10::Integer]
            (runIdentity (Foldl.foldM (evertM S.toList) [1..10]))
        ,   testCaseEqIO
            "ref"
            (True,[1..10::Integer])
            (do ref <- newIORef False 
                res <- Foldl.foldM (evertM (\s -> S.toList s <* lift (writeIORef ref True))) [1..10]
                refval <- readIORef ref
                return (refval,res))
        ]
    ,   testGroup "evertMIO"
        [
            testCaseEqIO
            "empty"
            ([]::[Integer])
            (Foldl.foldM (evertMIO S.toList) [])
        ,   testCaseEqIO
            "toList"
            [1..10::Integer]
            (Foldl.foldM (evertMIO S.toList) [1..10])
        ,   testCaseEqIO
            "ref"
            (True,[1..10::Integer])
            (do ref <- newIORef False 
                res <- Foldl.foldM (evertMIO (\s -> S.toList s <* liftIO (writeIORef ref True))) [1..10]
                refval <- readIORef ref
                return (refval,res))
        ]
    ,   testGroup "transduce"
        [
            testCaseEq
            "empty"
            ([]::[Integer])
            (Foldl.fold (transvert id Foldl.list) [])
        ,   testCaseEq
            "notempty"
            ([1..5]::[Integer])
            (Foldl.fold (transvert id Foldl.list) [1..5])
        ,   testCaseEq
            "surroundempty"
            ([1,2,3,4]::[Integer])
            (Foldl.fold (transvert (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 3 <* S.yield 4) Foldl.list) [])
        ,   testCaseEq
            "surround"
            ([1,2,3,4,5,6]::[Integer])
            (Foldl.fold (transvert (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 5 <* S.yield 6) Foldl.list) [3,4])
        ,   testCaseEq
            "group"
            ([[1,1],[2,2,2],[3,3,3]]::[[Integer]])
            (Foldl.fold (transvert (mapped S.toList . S.group) Foldl.list) [1,1,2,2,2,3,3,3])
        ]
    ,   testGroup "transduceM"
        [
        testCaseEq  
            "empty"
            ([]::[Integer])
            (runIdentity (Foldl.foldM (transvertM id (Foldl.generalize Foldl.list)) []))
        ,   testCaseEq
            "notempty"
            ([1..5]::[Integer])
            (runIdentity (Foldl.foldM (transvertM id (Foldl.generalize Foldl.list)) [1..5]))
        ,   testCaseEq
            "surroundempty"
            ([1,2,3,4]::[Integer])
            (runIdentity (Foldl.foldM (transvertM (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 3 <* S.yield 4) (Foldl.generalize Foldl.list)) []))
        ,   testCaseEq
            "surround"
            ([1,2,3,4,5,6]::[Integer])
            (runIdentity (Foldl.foldM (transvertM (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 5 <* S.yield 6) (Foldl.generalize Foldl.list)) [3,4]))
        ,   testCaseEq
            "group"
            ([[1,1],[2,2,2],[3,3,3]]::[[Integer]])
            (runIdentity (Foldl.foldM (transvertM (mapped S.toList . S.group) (Foldl.generalize Foldl.list)) [1,1,2,2,2,3,3,3]))
        ,   testCaseEqIO
            "ref"
            (True,[1,2,3,4,5,6]::[Integer])
            (do ref <- newIORef False 
                res <- Foldl.foldM (transvertM (\s -> S.yield 1 *> S.yield 2 *> (lift (lift (writeIORef ref True))) *> s <* S.yield 5 <* S.yield 6) (Foldl.generalize Foldl.list)) [3,4]
                refval <- readIORef ref
                return (refval,res))
        ]
    ,   testGroup "transduceMIO"
        [
            testCaseEqIO
            "empty"
            ([]::[Integer])
            (Foldl.foldM (transvertMIO id (Foldl.generalize Foldl.list)) [])
        ,   testCaseEqIO
            "notempty"
            ([1..5]::[Integer])
            (Foldl.foldM (transvertMIO id (Foldl.generalize Foldl.list)) [1..5])
        ,   testCaseEqIO
            "surroundempty"
            ([1,2,3,4]::[Integer])
            (Foldl.foldM (transvertMIO (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 3 <* S.yield 4) (Foldl.generalize Foldl.list)) [])
        ,   testCaseEqIO
            "surround"
            ([1,2,3,4,5,6]::[Integer])
            (Foldl.foldM (transvertMIO (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 5 <* S.yield 6) (Foldl.generalize Foldl.list)) [3,4])
        ,   testCaseEqIO
            "group"
            ([[1,1],[2,2,2],[3,3,3]]::[[Integer]])
            (Foldl.foldM (transvertMIO (mapped S.toList . S.group) (Foldl.generalize Foldl.list)) [1,1,2,2,2,3,3,3])
        ,   testCaseEqIO
            "ref"
            (True,[1,2,3,4,5,6]::[Integer])
            (do ref <- newIORef False 
                res <- Foldl.foldM (transvertMIO (\s -> S.yield 1 *> S.yield 2 *> (liftIO (writeIORef ref True)) *> s <* S.yield 5 <* S.yield 6) (Foldl.generalize Foldl.list)) [3,4]
                refval <- readIORef ref
                return (refval,res))
        ]
    ]
    where
    testCaseEq :: (Eq a, Show a) => TestName -> a -> a -> TestTree
    testCaseEq name a1 a2 = testCase name (assertEqual "" a1 a2)
    testCaseEqIO :: (Eq a, Show a) => TestName -> a -> IO a -> TestTree
    testCaseEqIO name a1 action = testCase name (action >>= assertEqual "" a1)

