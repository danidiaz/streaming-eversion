{-# LANGUAGE RankNTypes #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion.Pipes (
        PipeFold(..)
    ,   toStreamFold
    ,   toPipeFold
    ,   PipeFoldM(..)
    ,   toStreamFoldM
    ,   toPipeFoldM
    ,   PipeFoldMIO(..)
    ,   toStreamFoldMIO
    ,   toPipeFoldMIO
    ,   PipeTransducer(..)
    ,   toStreamTransducer 
    ,   toPipeTransducer
    ,   PipeTransducerM(..)
    ,   toStreamTransducerM 
    ,   toPipeTransducerM
    ,   PipeTransducerMIO(..)
    ,   toStreamTransducerMIO 
    ,   toPipeTransducerMIO
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
import           Streaming.Eversion
import qualified Streaming.Eversion as E
import           Pipes
import           Pipes.Prelude

-----------------------------------------------------------------------------------------

newtype PipeFold a x = 
        PipeFold { consumePipe :: forall m r. Monad m 
                               => Producer a m r 
                               -> m (x,r) 
                 } 

toStreamFold :: PipeFold a x -> StreamFold a x
toStreamFold (PipeFold f) = StreamFold (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFold :: StreamFold a x -> PipeFold a x
toPipeFold (StreamFold f) = PipeFold (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))

newtype PipeFoldM m a x = 
        PipeFoldM { consumePipeM :: forall t r. (MonadTrans t, Monad (t m)) 
                                 => Producer a (t m) r 
                                 -> t m (x,r) 
                  }

toStreamFoldM :: PipeFoldM m a x -> StreamFoldM m a x
toStreamFoldM (PipeFoldM f) = StreamFoldM (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFoldM :: StreamFoldM m a x -> PipeFoldM m a x
toPipeFoldM (StreamFoldM f) = PipeFoldM (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))

newtype PipeFoldMIO m a x = 
        PipeFoldMIO { consumePipeMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                     => Producer a (t m) r 
                                     -> t m (x,r) 
                    }

toStreamFoldMIO :: PipeFoldMIO m a x -> StreamFoldMIO m a x
toStreamFoldMIO (PipeFoldMIO f) = StreamFoldMIO (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeFoldMIO :: StreamFoldMIO m a x -> PipeFoldMIO m a x
toPipeFoldMIO (StreamFoldMIO f) = PipeFoldMIO (\producer -> fmap (\(x :> r) -> (x,r)) (f (Streaming.Prelude.unfoldr Pipes.next producer)))


newtype PipeTransducer a b = 
        PipeTransducer { transducePipe :: forall m r. Monad m 
                                       => Producer a m r 
                                       -> Producer b m r 
                       }

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

toStreamTransducerM :: PipeTransducerM m a b -> StreamTransducerM m a b
toStreamTransducerM (PipeTransducerM pt) = 
    StreamTransducerM (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeTransducerM :: StreamTransducerM m a b -> PipeTransducerM m a b
toPipeTransducerM (StreamTransducerM st)= 
    PipeTransducerM (\producer -> Pipes.Prelude.unfoldr Streaming.Prelude.next (st (Streaming.Prelude.unfoldr Pipes.next producer)))


newtype PipeTransducerMIO m a b = 
        PipeTransducerMIO { transduceMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                         => Producer a (t m) r 
                                         -> Producer b (t m) r 
                          }

toStreamTransducerMIO :: PipeTransducerMIO m a b -> StreamTransducerMIO m a b
toStreamTransducerMIO (PipeTransducerMIO pt) = 
    StreamTransducerMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

toPipeTransducerMIO :: StreamTransducerMIO m a b -> PipeTransducerMIO m a b
toPipeTransducerMIO (StreamTransducerMIO st)= 
    PipeTransducerMIO (\producer -> Pipes.Prelude.unfoldr Streaming.Prelude.next (st (Streaming.Prelude.unfoldr Pipes.next producer)))


