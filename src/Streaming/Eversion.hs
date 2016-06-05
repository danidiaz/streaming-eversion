{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion (
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

import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl
import           Streaming (Stream,Of)
import qualified Streaming as Streaming
import           Streaming.Prelude (yield)

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF

-----------------------------------------------------------------------------------------

data Feed a = Input a | EOF

-- What type could go here for efficiency?
type Iteratee a = Free ((->) a)  

evertedProducer :: forall a. Stream (Of a) (Iteratee (Feed a)) ()
evertedProducer = do
    r <- lift (liftF id)
    case r of
        Input a -> do
            yield a
            evertedProducer
        EOF -> return ()

type IterateeT a m = TF.FreeT ((->) a) m 

evertedProducer' :: forall a m. Monad m => Stream (Of a) (IterateeT (Feed a) m) ()
evertedProducer' = do
    r <- lift (liftF id)
    case r of
        Input a -> do
            yield a
            evertedProducer'
        EOF -> return ()

-----------------------------------------------------------------------------------------

newtype StreamConsumer a x = 
        StreamConsumer { consume :: forall m r. Monad m 
                                 => Stream (Of a) m r 
                                 -> m (x,r) 
                       } 

evert :: StreamConsumer a x -> Fold a x
evert (StreamConsumer consumer) = Fold step begin done
    where
    begin = consumer evertedProducer
    step s a = case s of
        Pure _ -> error "should never happen - unexpected stopped state"
        Free f -> case f (Input a) of 
           Pure _ -> error "should never happen - stopped after Input" 
           Free x -> Free x
    done s = case s of
        Pure _ -> error "should never happen - unexpected stopped state"
        Free f -> case f EOF of
            Pure (a,()) -> a
            Free _ -> error "should never happen - continuing after EOF"

newtype StreamConsumerM m a x = 
        StreamConsumerM { consumeM :: forall t r. MonadTrans t 
                                   => Stream (Of a) (t m) r 
                                   -> t m (x,r) 
                        }

evertM :: Monad m => StreamConsumerM m a x -> FoldM m a x
evertM (StreamConsumerM consumer) = FoldM step begin done
    where
    begin = return (consumer evertedProducer')
    step = undefined
    done = undefined

newtype StreamConsumerIO m a x = 
        StreamConsumerIO { consumeIO :: (forall t r. (MonadTrans t, MonadIO (t m)) 
                                     => Stream (Of a) (t m) r 
                                     -> t m (x,r)) 
                         }

evertIO :: MonadIO m => StreamConsumerIO m a x -> FoldM m a x 
evertIO = undefined

newtype StreamTransducer a b = 
        StreamTransducer { transform :: forall m r. Monad m 
                                     => Stream (Of a) m r 
                                     -> Stream (Of b) m r 
                         }

transduce :: StreamTransducer b a 
          -> (forall x. FoldM Identity a x -> FoldM Identity b x)
transduce = undefined

newtype StreamTransducerM m a b = 
        StreamTransducerM { transformM :: forall t r. (MonadTrans t) 
                                       => Stream (Of b) (t m) r 
                                       -> Stream (Of a) (t m) r 
                          }

transduceM :: Monad m 
           => StreamTransducerM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transduceM = undefined

newtype StreamTransducerIO m a b = 
        StreamTransducerIO { transformIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                         => Stream (Of b) (t m) r 
                                         -> Stream (Of a) (t m) r 
                           }

transduceIO :: Monad m 
            => StreamTransducerIO m b a 
            -> (forall x . FoldM m a x -> FoldM m b x)
transduceIO = undefined
