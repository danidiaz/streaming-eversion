{-# LANGUAGE RankNTypes #-}

-- | This module contains newtype wrappers analogous to those in
-- 'Streaming.Eversion', but for pipes. 
--
-- Also included are conversion functions
-- that translate between the @streaming@ world and the @pipes@ world.
--
-- If you whish to evert a pipe function, first move it to the streaming world.

module Streaming.Eversion.Pipes (
        -- * Producer folds
        PipeFold(..)
    ,   toStreamFold
    ,   toPipeFold
    ,   PipeFoldM(..)
    ,   toStreamFoldM
    ,   toPipeFoldM
    ,   PipeFoldMIO(..)
    ,   toStreamFoldMIO
    ,   toPipeFoldMIO
        -- * Pipe transducers
    ,   PipeTransducer(..)
    ,   toStreamTransducer 
    ,   toPipeTransducer
    ,   PipeTransducerM(..)
    ,   toStreamTransducerM 
    ,   toPipeTransducerM
    ,   PipeTransducerMIO(..)
    ,   toStreamTransducerMIO 
    ,   toPipeTransducerMIO
        -- * Utility functions
    ,   pipeLeftoversE
    ,   pipeHaltedE
    ) where

import           Data.Bifunctor
import           Data.Profunctor

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Except

import           Streaming(Of(..))
import qualified Streaming.Prelude
import           Streaming.Eversion
import           Pipes
import           Pipes.Prelude

-----------------------------------------------------------------------------------------

newtype PipeFold a x = 
        PipeFold { consumePipe :: forall m r. Monad m 
                               => Producer a m r 
                               -> m (x,r) 
                 } 

instance Functor (PipeFold a) where
    fmap f (PipeFold somefold) = PipeFold (fmap (first f) . somefold) 

instance Profunctor PipeFold where
    lmap f (PipeFold somefold) = PipeFold (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamFold :: PipeFold a x -> StreamFold a x
toStreamFold (PipeFold f) = StreamFold (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFold :: StreamFold a x -> PipeFold a x
toPipeFold (StreamFold f) = PipeFold (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))

newtype PipeFoldM m a x = 
        PipeFoldM { consumePipeM :: forall t r. (MonadTrans t, Monad (t m)) 
                                 => Producer a (t m) r 
                                 -> t m (x,r) 
                  }

instance Functor (PipeFoldM m a) where
    fmap f (PipeFoldM somefold) = PipeFoldM (fmap (first f) . somefold) 

instance Profunctor (PipeFoldM m) where
    lmap f (PipeFoldM somefold) = PipeFoldM (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamFoldM :: PipeFoldM m a x -> StreamFoldM m a x
toStreamFoldM (PipeFoldM f) = StreamFoldM (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFoldM :: StreamFoldM m a x -> PipeFoldM m a x
toPipeFoldM (StreamFoldM f) = PipeFoldM (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))

newtype PipeFoldMIO m a x = 
        PipeFoldMIO { consumePipeMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                     => Producer a (t m) r 
                                     -> t m (x,r) 
                    }

instance Functor (PipeFoldMIO m a) where
    fmap f (PipeFoldMIO somefold) = PipeFoldMIO (fmap (first f) . somefold) 

instance Profunctor (PipeFoldMIO m) where
    lmap f (PipeFoldMIO somefold) = PipeFoldMIO (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamFoldMIO :: PipeFoldMIO m a x -> StreamFoldMIO m a x
toStreamFoldMIO (PipeFoldMIO f) = StreamFoldMIO (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFoldMIO :: StreamFoldMIO m a x -> PipeFoldMIO m a x
toPipeFoldMIO (StreamFoldMIO f) = PipeFoldMIO (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))


newtype PipeTransducer a b = 
        PipeTransducer { transducePipe :: forall m r. Monad m 
                                       => Producer a m r 
                                       -> Producer b m r 
                       }

instance Functor (PipeTransducer a) where
    fmap f (PipeTransducer transducer) = PipeTransducer ((\p -> p >-> Pipes.Prelude.map f) . transducer) 

instance Profunctor PipeTransducer where
    lmap f (PipeTransducer somefold) = PipeTransducer (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamTransducer :: PipeTransducer a b -> StreamTransducer a b
toStreamTransducer (PipeTransducer pt) = 
    StreamTransducer (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeTransducer :: StreamTransducer a b -> PipeTransducer a b
toPipeTransducer (StreamTransducer st)= 
    PipeTransducer (\producer -> Pipes.Prelude.unfoldr Streaming.Prelude.next (st (Streaming.Prelude.unfoldr Pipes.next producer)))

newtype PipeTransducerM m a b = 
        PipeTransducerM { transducePipeM :: forall t r. (MonadTrans t, Monad (t m)) 
                                         => Producer a (t m) r 
                                         -> Producer b (t m) r 
                        }

instance Functor (PipeTransducerM m a) where
    fmap f (PipeTransducerM transducer) = PipeTransducerM ((\p -> p >-> Pipes.Prelude.map f) . transducer) 

instance Profunctor (PipeTransducerM m) where
    lmap f (PipeTransducerM somefold) = PipeTransducerM (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamTransducerM :: PipeTransducerM m a b -> StreamTransducerM m a b
toStreamTransducerM (PipeTransducerM pt) = 
    StreamTransducerM (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeTransducerM :: StreamTransducerM m a b -> PipeTransducerM m a b
toPipeTransducerM (StreamTransducerM st) = 
    PipeTransducerM (\producer -> Pipes.Prelude.unfoldr Streaming.Prelude.next (st (Streaming.Prelude.unfoldr Pipes.next producer)))


newtype PipeTransducerMIO m a b = 
        PipeTransducerMIO { transducePipeMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                             => Producer a (t m) r 
                                             -> Producer b (t m) r 
                          }

instance Functor (PipeTransducerMIO m a) where
    fmap f (PipeTransducerMIO transducer) = PipeTransducerMIO ((\p -> p >-> Pipes.Prelude.map f) . transducer) 

instance Profunctor (PipeTransducerMIO m) where
    lmap f (PipeTransducerMIO somefold) = PipeTransducerMIO (somefold . (\producer -> producer >-> Pipes.Prelude.map f))
    rmap = fmap

toStreamTransducerMIO :: PipeTransducerMIO m a b -> StreamTransducerMIO m a b
toStreamTransducerMIO (PipeTransducerMIO pt) = 
    StreamTransducerMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeTransducerMIO :: StreamTransducerMIO m a b -> PipeTransducerMIO m a b
toPipeTransducerMIO (StreamTransducerMIO st)= 
    PipeTransducerMIO (\producer -> Pipes.Prelude.unfoldr Streaming.Prelude.next (st (Streaming.Prelude.unfoldr Pipes.next producer)))

    
pipeLeftoversE :: (MonadTrans t, Monad m, Monad (t (ExceptT leftover m))) 
               => Producer decoded (t (ExceptT leftover m)) (Producer leftover (t (ExceptT leftover m)) r) -- ^
               -> Producer decoded (t (ExceptT leftover m)) r
pipeLeftoversE decodedProducer = decodedProducer >>= \leftoversProducer -> do
        leftovers <- lift (next leftoversProducer)
        case leftovers of 
            Left r -> return r
            Right (firstleftover,_) -> lift (lift (throwE firstleftover))

pipeHaltedE :: (MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
            => Producer a (t (ExceptT e m)) (Either e r)  -- ^
            -> Producer a (t (ExceptT e m)) r
pipeHaltedE producer = producer >>= lift . lift . ExceptT . return

