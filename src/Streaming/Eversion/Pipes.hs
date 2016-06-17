{-# LANGUAGE RankNTypes #-}

-- | Like "Streaming.Eversion", but for Producer folds and transformations.
-- 

module Streaming.Eversion.Pipes (
        -- * Producer folds 
        evert
    ,   evertM
    ,   evertM_
    ,   evertMIO
    ,   evertMIO_
    ,   evertMR
    ,   evertMR_
        -- * Producer transformations 
    ,   transvert
    ,   transvertM
    ,   transvertMIO
    ,   transvertMR
        -- * Examples
        -- $examples
    ) where

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class

import           Streaming(Of(..),MonadResource)
import qualified Streaming.Prelude
import qualified Streaming.Eversion
import           Pipes
import           Pipes.Prelude
import           Control.Foldl (Fold(..),FoldM(..))

{- $setup
>>> :set -XOverloadedStrings
>>> import           Control.Error
>>> import           Control.Monad
>>> import           Control.Monad.Trans.Except
>>> import           Control.Foldl (Fold(..),FoldM(..))
>>> import qualified Control.Foldl as L
>>> import           Streaming.Prelude (yield,next)
>>> import qualified Streaming.Prelude as S
>>> import           Pipes
>>> import qualified Pipes.Prelude as P
>>> import qualified Pipes.Text as PT
>>> import qualified Pipes.Text.Encoding as PT
>>> import qualified Pipes.ByteString as PB
>>> import           Lens.Micro.Extras
-}

-----------------------------------------------------------------------------------------

evert :: (forall m r. Monad m => Producer a m r -> m (x,r)) 
      -> Fold a x -- ^
evert phi = Streaming.Eversion.evert (\stream -> fmap (\(x,r) -> x :> r) (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

evertM :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> t m (x,r)) 
       -> FoldM m a x -- ^
evertM phi = Streaming.Eversion.evertM (\stream -> fmap (\(x,r) -> x :> r) (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

evertM_ :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> t m r) 
        -> FoldM m a () -- ^
evertM_ phi = Streaming.Eversion.evertM_ (\stream -> phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream))

evertMIO :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> t m (x,r)) 
         -> FoldM m a x -- ^
evertMIO phi = Streaming.Eversion.evertMIO (\stream -> fmap (\(x,r) -> x :> r) (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

evertMIO_ :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> t m r) 
          -> FoldM m a () -- ^
evertMIO_ phi = Streaming.Eversion.evertMIO_ (\stream -> phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream))

evertMR :: MonadResource m => (forall t r. (MonadTrans t, MonadResource (t m)) => Producer a (t m) r -> t m (x,r)) 
         -> FoldM m a x -- ^
evertMR phi = Streaming.Eversion.evertMR (\stream -> fmap (\(x,r) -> x :> r) (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

evertMR_ :: MonadResource m => (forall t r. (MonadTrans t, MonadResource (t m)) => Producer a (t m) r -> t m r) 
          -> FoldM m a () -- ^
evertMR_ phi = Streaming.Eversion.evertMR_ (\stream -> phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream))

transvert :: (forall m r. Monad m => Producer a m r -> Producer b m r)
          -> Fold b x -- ^
          -> Fold a x 
transvert phi = Streaming.Eversion.transvert (\stream -> Streaming.Prelude.unfoldr Pipes.next (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

transvertM :: Monad m 
           => (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> Producer b (t m) r)
           -> FoldM m b x -- ^
           -> FoldM m a x
transvertM phi = Streaming.Eversion.transvertM (\stream -> Streaming.Prelude.unfoldr Pipes.next (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

transvertMIO :: MonadIO m 
             => (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> Producer b (t m) r)
             -> FoldM m b x -- ^
             -> FoldM m a x
transvertMIO phi = Streaming.Eversion.transvertMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

transvertMR :: MonadResource m 
             => (forall t r. (MonadTrans t, MonadResource (t m)) => Producer a (t m) r -> Producer b (t m) r)
             -> FoldM m b x -- ^
             -> FoldM m a x
transvertMR phi = Streaming.Eversion.transvertMR (\stream -> Streaming.Prelude.unfoldr Pipes.next (phi (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))


{- $examples
 
    Applying a decoder from "Pipes.Text.Encoding" to the inputs of a Fold. In
    case the decoding fails, part of the leftovers are read in order to build the
    error value.  

>>> :{ 
    let trans = transvertM (\producer -> do result <- PT.decode (PT.utf8 . PT.eof) producer 
                                            lift (case result of
                                                    Left ls -> sample ls >>= lift . throwE
                                                    Right r -> return r))
        sample leftovers = L.purely P.fold L.mconcat (void (view (PB.splitAt 5) leftovers))
    in  runExceptT $ L.foldM (trans (L.generalize L.mconcat)) ["decode","this"]
    :}
Right "decodethis"

>>> :{ 
    let trans = transvertM (\producer -> do result <- PT.decode (PT.utf8 . PT.eof) producer 
                                            lift (case result of
                                                    Left ls -> sample ls >>= lift . throwE
                                                    Right r -> return r))
        sample leftovers = L.purely P.fold L.mconcat (void (view (PB.splitAt 8) leftovers))
    in  runExceptT $ L.foldM (trans (L.generalize L.mconcat)) ["invalid \xc3\x28","sequence"]
    :}
Left "\195(sequen"

Note that the errors are thrown in an 'ExceptT' layer below the 'Pipes.Producer'
and the polymorphic transformer.

-}
