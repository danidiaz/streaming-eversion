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
    ]
    where
    testCaseEq :: (Eq a, Show a) => TestName -> a -> a -> TestTree
    testCaseEq name a1 a2 = testCase name (assertEqual "" a1 a2)





