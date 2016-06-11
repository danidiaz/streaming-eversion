module Main where

import Test.DocTest

main :: IO ()
main = doctest 
    [
        "src/Streaming/Eversion.hs",
        "src/Streaming/Eversion/Pipes.hs"
    ]
