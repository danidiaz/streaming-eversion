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
import           Control.Monad.Trans.Except

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
>>> import qualified Pipes.Text as T
>>> import qualified Pipes.Text.Encoding as TE
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
 
    Allows you to plug any of the "non-lens decoding functions" from "Pipes.Text.Encoding" into 'pipeTransvertibleM'. Just 
    compose the decoder with this function before passing it to 'pipeTransvertibleM'.

    The result will be a 'TransvertibleM' that works in 'ExceptT'. 

>>> :{ 
    let adapt = transvertM (pipeTransvertibleM (\producer -> do result <- TE.decode (TE.utf8 . TE.eof) producer 
                                                                hoistEither3 (first (const ()) result)))
    in  runExceptT $ L.foldM (adapt (L.generalize L.mconcat)) ["decode","this"]
    :}
Right "decodethis"

    If any undecodable bytes are found, the computation halts with the undecoded bytes as the error.

>>> :{ 
    let adapt = transvertM (pipeTransvertibleM (\producer -> do result <- TE.decode (TE.utf8 . TE.eof) producer 
                                                                lift (hoistEither2 =<< bimapM take1 return result)))
        take1 leftoverproducer = do
            e <- Pipes.next leftoverproducer
            return (case e of
                Left _ -> mempty
                Right (bytes,_) -> bytes)
    in  runExceptT $ L.foldM (adapt (L.generalize L.mconcat)) ["invalid \xc3\x28","sequence"]
    :}
Left "\195("

-}
