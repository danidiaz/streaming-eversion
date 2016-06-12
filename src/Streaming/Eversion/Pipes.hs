{-# LANGUAGE RankNTypes #-}

-- | 
-- 

module Streaming.Eversion.Pipes (
        -- * Pipe eversions
        pipeEversion
    ,   evert
    ,   pipeEversionM
    ,   evertM
    ,   pipeEversionMIO
    ,   evertMIO
        -- * Pipe eversions
    ,   pipeTransversion
    ,   transvert
    ,   pipeTransversionM
    ,   pipeDecoderTransversionM
    ,   transvertM
    ,   pipeTransversionMIO
    ,   transvertMIO
        -- * Utility functions
    ,   pipeLeftoverE
    ,   pipeHaltE
    ) where

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Except

import           Streaming(Of(..))
import qualified Streaming.Prelude
import           Streaming.Eversion
import           Pipes
import           Pipes.Prelude

-----------------------------------------------------------------------------------------


pipeEversion :: (forall m r. Monad m => Producer a m r -> m (x,r)) -- ^
             -> Eversion a x
pipeEversion f = eversion (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversionM :: (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> t m (x,r)) -- ^
              -> EversionM m a x
pipeEversionM f = eversionM (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversionMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> t m (x,r)) -- ^
                -> EversionMIO m a x
pipeEversionMIO f = eversionMIO (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeTransversion :: (forall m r. Monad m => Producer a m r -> Producer b m r) -- ^
                 -> Transversion a b
pipeTransversion pt = transversion (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeTransversionM :: (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> Producer b (t m) r) -- ^
                  -> TransversionM m a b
pipeTransversionM pt = transversionM (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeDecoderTransversionM :: Monad m => (forall t r .(MonadTrans t, Monad (t (ExceptT bytes m))) => (Producer bytes (t (ExceptT bytes m)) r -> Producer text (t (ExceptT bytes m)) (Producer bytes (t (ExceptT bytes m)) r))) -- ^
                         -> TransversionM (ExceptT bytes m) bytes text
pipeDecoderTransversionM decoder = pipeTransversionM (pipeLeftoverE . decoder)

pipeTransversionMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> Producer b (t m) r) -- ^
                  -> TransversionMIO m a b
pipeTransversionMIO pt = transversionMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeLeftoverE :: (MonadTrans t, Monad m, Monad (t (ExceptT leftover m))) => Producer decoded (t (ExceptT leftover m)) (Producer leftover (t (ExceptT leftover m)) r) -- ^
              -> Producer decoded (t (ExceptT leftover m)) r
pipeLeftoverE decodedProducer = decodedProducer >>= \leftoversProducer -> do
        leftovers <- lift (next leftoversProducer)
        case leftovers of 
            Left r -> return r
            Right (firstleftover,_) -> lift (lift (throwE firstleftover))

pipeHaltE :: (MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
          => Producer a (t (ExceptT e m)) (Either e r)  -- ^
          -> Producer a (t (ExceptT e m)) r
pipeHaltE producer = producer >>= lift . lift . ExceptT . return

