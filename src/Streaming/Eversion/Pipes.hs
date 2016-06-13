{-# LANGUAGE RankNTypes #-}

-- | Like "Streaming.Eversion", but for Producer folds and transformations.
-- 

module Streaming.Eversion.Pipes (
        -- * Producer folds turn into iteratees
        pipeEversible
    ,   evert
    ,   pipeEversibleM
    ,   pipeEversibleM_
    ,   evertM
    ,   pipeEversibleMIO
    ,   pipeEversibleMIO_
    ,   evertMIO
        -- * Producer transformations turn into transducers
    ,   pipeTransvertible
    ,   transvert
    ,   pipeTransvertibleM
    ,   transvertM
    ,   pipeTransvertibleMIO
    ,   transvertMIO
        -- * Auxiliary functions
    ,   pipeLeftoversE
    ,   pipeTransE
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

-- -- | Ignore the somewhat baroque type and just remember that you can plug any of the "non-lens decoding functions" from "Pipes.Text.Encoding" here.
-- --
-- -- The result is a 'TransvertibleM' that works in 'ExceptT'. If any undecodable bytes are found, the computation halts with the undecodable bytes as the error.
-- pipeDecoderTransvertibleE :: Monad m => (forall t r .(MonadTrans t, Monad (t (ExceptT bytes m))) => (Producer bytes (t (ExceptT bytes m)) r -> Producer text (t (ExceptT bytes m)) (Producer bytes (t (ExceptT bytes m)) r))) -- ^
--                          -> TransvertibleM (ExceptT bytes m) bytes text
-- pipeDecoderTransvertibleE decoder = pipeTransvertibleM (pipeLeftoversE . decoder)

pipeTransvertibleMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Producer a (t m) r -> Producer b (t m) r) -- ^
                  -> TransvertibleMIO m a b
pipeTransvertibleMIO pt = transvertibleMIO (\stream -> Streaming.Prelude.unfoldr Pipes.next (pt (Pipes.Prelude.unfoldr Streaming.Prelude.next stream)))

{-| Allows you to plug any of the "non-lens decoding functions" from "Pipes.Text.Encoding" into 'pipeTransvertibleM'. Just 
    compose the decoder with this function before passing it to 'pipeTransvertibleM'.

    The result will be a 'TransvertibleM' that works in 'ExceptT'. 

>>> :{ 
    let adapt = transvertM (pipeTransvertibleM (fails2 (first (\_ -> ())) . TE.decode (TE.utf8 . TE.eof)))
    in  runExceptT $ L.foldM (adapt (L.generalize L.mconcat)) ["decode","this"]
    :}
Right "decodethis"

    If any undecodable bytes are found, the computation halts with the undecoded bytes as the error.

>>> :{ 
    let adapt = transvertM (pipeTransvertibleM (fails2 (first (\_ -> ())) . TE.decode (TE.utf8 . TE.eof)))
    in  runExceptT $ L.foldM (adapt (L.generalize L.mconcat)) ["invalid \xc3\x28","sequence"]
    :}
Left ()

>>> :{ 
    let adapt = transvertM (pipeTransvertibleM (fails2M (bitraverse probe return) . TE.decode (TE.utf8 . TE.eof)))
        probe producer = do
            r <- Pipes.next producer
            case r of
                Left _ -> return mempty
                Right (bytes,_) -> return bytes
    in  runExceptT $ L.foldM (adapt (L.generalize L.mconcat)) ["invalid \xc3\x28","sequence"]
    :}
Left "\195("

-}
pipeLeftoversE :: (MonadTrans t, Monad m, Monad (t (ExceptT bytes m))) => Producer text (t (ExceptT bytes m)) (Producer bytes (t (ExceptT bytes m)) r) -- ^
              -> Producer text (t (ExceptT bytes m)) r
pipeLeftoversE decodedProducer = decodedProducer >>= \leftoversProducer -> do
        leftovers <- lift (next leftoversProducer)
        case leftovers of 
            Left r -> return r
            Right (firstleftover,_) -> lift (lift (throwE firstleftover))

{-| If your producer-transforming computation can fail early returning a 'Left',
    compose it with this function before passing it to 'transvertibleM'. 

    The result will be an 'TransvertibleM' that works on 'ExceptT'.
-}
pipeTransE :: (MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
           => Producer a (t (ExceptT e m)) (Either e r)  -- ^
           -> Producer a (t (ExceptT e m)) r
pipeTransE producer = producer >>= lift . lift . ExceptT . return

