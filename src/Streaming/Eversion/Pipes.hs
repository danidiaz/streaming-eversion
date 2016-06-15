{-# LANGUAGE RankNTypes #-}

-- | Like "Streaming.Eversion", but for Producer folds and transformations.
-- 

module Streaming.Eversion.Pipes (
        -- * Producer folds 
        pipeEversible
    ,   evert
    ,   pipeEversibleM
    ,   pipeEversibleM_
    ,   evertM
    ,   pipeEversibleMIO
    ,   pipeEversibleMIO_
    ,   evertMIO
        -- * Producer transformations 
    ,   pipeTransvertible
    ,   transvert
    ,   pipeTransvertibleM
    ,   transvertM
    ,   pipeTransvertibleMIO
    ,   transvertMIO
        -- * Examples
        -- $examples
    ) where

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class

import           Streaming(Of(..))
import qualified Streaming.Prelude
import           Streaming.Eversion
import           Pipes
import           Pipes.Prelude

{- $setup
>>> :set -XOverloadedStrings
>>> import           Data.Functor.Identity
>>> import           Data.Bifunctor
>>> import           Data.Bitraversable
>>> import           Control.Error
>>> import           Control.Monad
>>> import           Control.Monad.Trans.Except
>>> import           Control.Monad.Trans.Identity
>>> import           Control.Foldl (Fold(..),FoldM(..))
>>> import qualified Control.Foldl as L
>>> import           Streaming (Stream,Of(..))
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


pipeEversible :: (forall m r. Monad m => Producer a m r -> m (x,r)) -- ^
             -> Eversible a x
pipeEversible f = eversible (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversibleM :: (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> t m (x,r)) -- ^
              -> EversibleM m a x
pipeEversibleM f = eversibleM (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversibleM_ :: (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> t m r) -- ^
              -> EversibleM m a ()
pipeEversibleM_ f = eversibleM (\stream -> fmap (\r -> () :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversibleMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> t m (x,r)) -- ^
                -> EversibleMIO m a x
pipeEversibleMIO f = eversibleMIO (\stream -> fmap (\(x,r) -> x :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeEversibleMIO_ :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> t m r) -- ^
                -> EversibleMIO m a ()
pipeEversibleMIO_ f = eversibleMIO (\stream -> fmap (\r -> () :> r) (f (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeTransvertible :: (forall m r. Monad m => Producer a m r -> Producer b m r) -- ^
                 -> Transvertible a b
pipeTransvertible pt = transvertible (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

pipeTransvertibleM :: (forall t r. (MonadTrans t, Monad (t m)) => Producer a (t m) r -> Producer b (t m) r) -- ^
                  -> TransvertibleM m a b
pipeTransvertibleM pt = transvertibleM (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))


pipeTransvertibleMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> Producer b (t m) r) -- ^
                  -> TransvertibleMIO m a b
pipeTransvertibleMIO pt = transvertibleMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

{- $examples
 
    Creating a 'TransvertibleM' out a decoder from "Pipes.Text.Encoding". In
    case the decoding fails, part of the leftovers are read in order to build
    the error value.  

>>> :{ 
    let trans = transvertM (pipeTransvertibleM (\producer -> do result <- PT.decode (PT.utf8 . PT.eof) producer 
                                                                lift (case result of
                                                                        Left ls -> sample ls >>= lift . throwE
                                                                        Right r -> return r)))
        sample leftovers = L.purely P.fold L.mconcat (void (view (PB.splitAt 5) leftovers))
    in  runExceptT $ L.foldM (trans (L.generalize L.mconcat)) ["decode","this"]
    :}
Right "decodethis"

>>> :{ 
    let trans = transvertM (pipeTransvertibleM (\producer -> do result <- PT.decode (PT.utf8 . PT.eof) producer 
                                                                lift (case result of
                                                                        Left ls -> sample ls >>= lift . throwE
                                                                        Right r -> return r)))
        sample leftovers = L.purely P.fold L.mconcat (void (view (PB.splitAt 8) leftovers))
    in  runExceptT $ L.foldM (trans (L.generalize L.mconcat)) ["invalid \xc3\x28","sequence"]
    :}
Left "\195(sequen"

Note that the errors are thrown in an 'ExceptT' layer below the 'Pipes.Producer'
and the polymorphic transformer.

-}
