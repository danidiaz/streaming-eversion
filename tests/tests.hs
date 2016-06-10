module Main where

import Data.Functor.Identity
import Data.Char
import Data.Monoid
import Data.Bifunctor
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import           Control.Foldl           
import qualified Control.Foldl           as Foldl
import Streaming
import qualified Streaming.Prelude       as S
import Streaming.Eversion

main :: IO ()
main = defaultMain tests

-- runStream :: Monad m => Fold a b -> Stream (Of a) m r -> m (Of b r)
-- runStream = Foldl.purely S.fold
-- 
-- runStreamM :: Monad m => FoldM m a b -> Stream (Of a) m r -> m (Of b r)
-- runStreamM = Foldl.impurely S.foldM

tests :: TestTree
tests = testGroup "tests" 
    [ 
        testCaseEq
        "evert 01/empty"
        ([]::[Integer])
        (Foldl.fold (evert (StreamConsumer S.toList)) [])
    ,   testCaseEq
        "evert 02/toList"
        [1..10::Integer]
        (Foldl.fold (evert (StreamConsumer S.toList)) [1..10])
    ,   testCaseEq
        "evert 03/empty"
        ([]::[Integer])
        (runIdentity (Foldl.foldM (evertM (StreamConsumerM S.toList)) []))
    ,   testCaseEq
        "evert 04/toList"
        [1..10::Integer]
        (runIdentity (Foldl.foldM (evertM (StreamConsumerM S.toList)) [1..10]))
    ,   testCaseEq
        "transduce 01/empty"
        ([]::[Integer])
        (Foldl.fold (transduce (StreamTransducer id) Foldl.list) [])
    ,   testCaseEq
        "transduce 01b/notempty"
        ([1..5]::[Integer])
        (Foldl.fold (transduce (StreamTransducer id) Foldl.list) [1..5])
    ,   testCaseEq
        "transduce 02/surroundempty"
        ([1,2,3,4]::[Integer])
        (Foldl.fold (transduce (StreamTransducer (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 3 <* S.yield 4)) Foldl.list) [])
    ,   testCaseEq
        "transduce 03/surround"
        ([1,2,3,4,5,6]::[Integer])
        (Foldl.fold (transduce (StreamTransducer (\s -> S.yield 1 *> S.yield 2 *> s <* S.yield 5 <* S.yield 6)) Foldl.list) [3,4])
    ,   testCaseEq
        "transduce 04/group"
        ([[1,1],[2,2,2],[3,3,3]]::[[Integer]])
        (Foldl.fold (transduce (StreamTransducer (mapped S.toList . S.group)) Foldl.list) [1,1,2,2,2,3,3,3])
    ]
    where
    testCaseEq :: (Eq a, Show a) => TestName -> a -> a -> TestTree
    testCaseEq name a1 a2 = testCase name (assertEqual "" a1 a2)





