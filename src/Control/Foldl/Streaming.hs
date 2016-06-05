{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}

module Control.Foldl.Streaming (
) where

import           Data.Functor.Identity

import           Control.Foldl (FoldM)
import qualified Control.Foldl as Foldl
import           Streaming (Stream,Of)
import qualified Streaming as Streaming

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Free

-- -- | Workaround for the need of -XImpredicativeTypes.
-- newtype StreamOf a m r = StreamOf { getStream :: Stream (Of a) m r }  

-- evert :: forall x a . (forall m r. Monad m => StreamOf a m r -> m (x,r)) -> FoldM Identity a x
-- evert = undefined

evert :: (forall m r. Monad m => Stream (Of a) m r -> m (x,r)) -> FoldM Identity a x
evert = undefined

evertIO :: MonadIO m 
        => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (x,r)) 
        -> FoldM m a r
evertIO = undefined
