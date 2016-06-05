module Main where

import Data.Char
import Data.Monoid
import Data.Bifunctor
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import qualified Control.Foldl           as Foldl
import qualified Control.Foldl.Streaming as Foldl
import Streaming
import Streaming.Prelude

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "tests" 
    [ 
    ]
