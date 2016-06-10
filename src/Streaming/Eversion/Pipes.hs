{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ViewPatterns #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion.Pipes (
        pipeFold
    ,   consumePipe
    ) where

import           Data.Functor.Identity

import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF
import           Control.Comonad

import           Streaming(Of(..))
import qualified Streaming 
import qualified Streaming.Prelude
import           Streaming.Eversion(StreamFold(..))
import qualified Streaming.Eversion as E
import           Pipes
import           Pipes.Prelude

-----------------------------------------------------------------------------------------

pipeFold :: (forall m r. Monad m => Producer a m r -> m (x,r)) -> StreamFold a x
pipeFold f = StreamFold (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

consumePipe :: Monad m => StreamFold a x -> Producer a m r -> m (x,r)
consumePipe (StreamFold f) producer = fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer))

