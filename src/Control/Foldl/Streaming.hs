{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Control.Foldl.Streaming (
        StreamConsumer(..)
    ,   evert
    ,   StreamConsumerM(..)
    ,   evertM
    ,   StreamConsumerIO(..)
    ,   evertIO
    ,   StreamTransducer(..)
    ,   transduce
    ,   StreamTransducerM(..)
    ,   transduceM
    ,   StreamTransducerIO(..)
    ,   transduceIO
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

newtype StreamConsumer a x = StreamConsumer { consume :: forall m r. Monad m => Stream (Of a) m r -> m (x,r) } 

evert :: StreamConsumer a x -> FoldM Identity a x
evert = undefined

newtype StreamConsumerM m a x = StreamConsumerM { consumeM :: forall t r. MonadTrans t => Stream (Of a) (t m) r -> t m (x,r) }

evertM :: Monad m => StreamConsumerM m a x -> FoldM m a x
evertM = undefined

newtype StreamConsumerIO m a x = StreamConsumerIO { consumeIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (x,r)) }

evertIO :: MonadIO m => StreamConsumerIO m a x -> FoldM m a x 
evertIO = undefined

newtype StreamTransducer a b = StreamTransducer { transform :: forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r }

transduce :: StreamTransducer b a -> (forall x. FoldM Identity a x -> FoldM Identity b x)
transduce = undefined

newtype StreamTransducerM m a b = StreamTransducerM { transformM :: forall t r. (MonadTrans t) => Stream (Of b) (t m) r -> Stream (Of a) (t m) r }

transduceM :: Monad m => StreamTransducerM m b a -> (forall x . FoldM m a x -> FoldM m b x)
transduceM = undefined

newtype StreamTransducerIO m a b = StreamTransducerIO { transformIO :: forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of b) (t m) r -> Stream (Of a) (t m) r }

transduceIO :: Monad m => StreamTransducerIO m b a -> (forall x . FoldM m a x -> FoldM m b x)
transduceIO = undefined
