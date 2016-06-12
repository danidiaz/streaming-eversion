{-# LANGUAGE RankNTypes #-}


{-| The pull-based-to-push-based transformations work on functions that are 
    polymorphic over a monad transformer.  
    
    Because of this, some of the type signatures in this
    module look scary, but actually many (suitably polymorphic) operations on
    'Stream's will unify with them.
   
    To get "interruptible" operations that can exit early with an error, put a
    'ExceptT' transformer just below the polymorphic monad transformer. 
   
    Inspired by http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
-}

module Streaming.Eversion (
        -- * Stream folds
        Eversion
    ,   eversion
    ,   evert
    ,   EversionM
    ,   eversionM
    ,   evertM
    ,   EversionMIO
    ,   eversionMIO
    ,   evertMIO
        -- * Stream transducers
    ,   Transversion
    ,   transversion
    ,   transvert
    ,   TransversionM
    ,   transversionM
    ,   transvertM
    ,   TransversionMIO
    ,   transversionMIO
    ,   transvertMIO
        -- * Utility functions
    ,   haltE
    ) where

import           Data.Bifunctor
import           Data.Profunctor

import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl
import           Streaming (Stream,Of(..))
import           Streaming.Prelude (yield,next)
import qualified Streaming.Prelude as S

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF
import           Control.Monad.Trans.Except
import           Control.Comonad

{- $setup
>>> import           Data.Functor.Identity
>>> import           Control.Monad.Trans.Except
>>> import           Control.Monad.Trans.Identity
>>> import           Control.Foldl (Fold(..),FoldM(..))
>>> import qualified Control.Foldl as L
>>> import           Streaming (Stream,Of(..))
>>> import           Streaming.Prelude (yield,next)
>>> import qualified Streaming.Prelude as S
-}

-----------------------------------------------------------------------------------------

data Feed a = Input a | EOF

-- What type could go here for efficiency?
type Iteratee a = Free ((->) a)  

evertedStream :: forall a. Stream (Of a) (Iteratee (Feed a)) ()
evertedStream = do
    r <- lift (liftF id)
    case r of
        Input a -> do
            yield a
            evertedStream
        EOF -> return ()

type IterateeT a m = TF.FreeT ((->) a) m 

evertedStreamM :: forall a m. Monad m => Stream (Of a) (IterateeT (Feed a) m) ()
evertedStreamM = do
    r <- lift (TF.liftF id)
    case r of
        Input a -> do
            yield a
            evertedStreamM
        EOF -> return ()

-----------------------------------------------------------------------------------------

newtype Eversion a x = 
        Eversion { consume :: forall m r. Monad m 
                             => Stream (Of a) m r 
                             -> m (Of x r) 
                   } 

instance Functor (Eversion a) where
    fmap f (Eversion somefold) = Eversion (fmap (first f) . somefold) 

instance Profunctor Eversion where
    lmap f (Eversion somefold) = Eversion (somefold . S.map f)
    rmap = fmap

stoppedBeforeEOF :: String
stoppedBeforeEOF = "Stopped before receiving EOF."

continuedAfterEOF :: String
continuedAfterEOF = "Continued after receiving EOF."

eversion :: (forall m r. Monad m => Stream (Of a) m r -> m (Of x r)) -> Eversion a x
eversion = Eversion

evert :: Eversion a x -> Fold a x
evert (Eversion consumer) = Fold step begin done
    where
    begin = consumer evertedStream
    step s a = case s of
        Pure _ -> error stoppedBeforeEOF
        Free f -> f (Input a)
    done s = case s of
        Pure _ -> error stoppedBeforeEOF
        Free f -> case f EOF of
            Pure (a :> ()) -> a
            Free _ -> error continuedAfterEOF


newtype EversionM m a x = 
        EversionM { consumeM :: forall t r. (MonadTrans t, Monad (t m)) 
                               => Stream (Of a) (t m) r 
                               -> t m (Of x r) 
                    }

instance Functor (EversionM m a) where
    fmap f (EversionM somefold) = EversionM (fmap (first f) . somefold) 

instance Profunctor (EversionM m) where
    lmap f (EversionM somefold) = EversionM (somefold . S.map f)
    rmap = fmap

eversionM ::(forall t r . (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
            -> EversionM m a x
eversionM = EversionM                                                      

evertM :: Monad m => EversionM m a x -> FoldM m a x
evertM (EversionM consumer) = FoldM step begin done
    where
    begin = return (consumer evertedStreamM)
    step (TF.FreeT ms) i = do
        s <- ms
        case s of
            TF.Pure _ -> error stoppedBeforeEOF
            TF.Free f -> return (f (Input i))
    done (TF.FreeT ms) = do
        s <- ms
        case s of 
            TF.Pure _ -> error stoppedBeforeEOF
            TF.Free f -> do
                let TF.FreeT ms' = f EOF
                s' <- ms'
                case s' of
                    TF.Pure (a :> ()) -> return a
                    TF.Free _ -> error continuedAfterEOF

newtype EversionMIO m a x = 
        EversionMIO { consumeMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) 
                                   => Stream (Of a) (t m) r 
                                   -> t m (Of x r)) 
                      }

instance Functor (EversionMIO m a) where
    fmap f (EversionMIO somefold) = EversionMIO (fmap (first f) . somefold) 

instance Profunctor (EversionMIO m) where
    lmap f (EversionMIO somefold) = EversionMIO (somefold . S.map f)
    rmap = fmap

eversionMIO ::(forall t r . (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
            -> EversionMIO m a x
eversionMIO = EversionMIO                                                      

evertMIO :: MonadIO m => EversionMIO m a x -> FoldM m a x 
evertMIO (EversionMIO consumer) = FoldM step begin done
    where
    begin = return (consumer evertedStreamM)
    step (TF.FreeT ms) i = do
        s <- ms
        case s of
            TF.Pure _ -> error stoppedBeforeEOF
            TF.Free f -> return (f (Input i))
    done (TF.FreeT ms) = do
        s <- ms
        case s of 
            TF.Pure _ -> error stoppedBeforeEOF
            TF.Free f -> do
                let TF.FreeT ms' = f EOF
                s' <- ms'
                case s' of
                    TF.Pure (a :> ()) -> return a
                    TF.Free _ -> error continuedAfterEOF

newtype Transversion a b = 
        Transversion { transduce :: forall m r. Monad m 
                                     => Stream (Of a) m r 
                                     -> Stream (Of b) m r 
                         } 

instance Functor (Transversion a) where
    fmap f (Transversion transducer) = Transversion (S.map f . transducer) 

instance Profunctor Transversion where
    lmap f (Transversion somefold) = Transversion (somefold . S.map f)
    rmap = fmap

data Pair a b = Pair !a !b

data StreamState a b = Pristine (Stream (Of b) (Iteratee (Feed a)) ())
                     | Waiting  (Feed a -> Iteratee (Feed a) (Either () (b, Stream (Of b) (Iteratee (Feed a)) ())))


transversion :: (forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r) -- ^
                 -> Transversion a b
transversion = Transversion

transvert :: Transversion b a 
          -> (forall x. Fold a x -> Fold b x)
transvert (Transversion transducer) somefold = Fold step begin done
    where
    begin = Pair somefold (Pristine (transducer evertedStream))
    step (Pair innerfold (Pristine pristine)) i = step (advance innerfold pristine) i
    step (Pair innerfold (Waiting waiting)) i = 
        case waiting (Input i) of
            Pure (Left ()) -> error stoppedBeforeEOF
            Pure (Right (a, stream)) -> advance (Foldl.fold (duplicate innerfold) [a]) stream
            Free f -> Pair innerfold (Waiting f)
    advance innerfold stream =  
        case next stream of
            Pure (Left ()) -> error stoppedBeforeEOF
            Pure (Right (a,future)) -> advance (Foldl.fold (duplicate innerfold) [a]) future
            Free f -> Pair innerfold (Waiting f)
    done (Pair innerfold (Pristine pristine)) = done (advance innerfold pristine) 
    done (Pair innerfold (Waiting waiting)) =
        case waiting EOF of
            Pure (Left ()) -> extract innerfold
            Pure (Right (a, stream)) -> extract (advancefinal (Foldl.fold (duplicate innerfold) [a]) stream)
            Free _ -> error continuedAfterEOF
    advancefinal innerfold stream =  
        case next stream of
            Pure (Left ()) -> innerfold 
            Pure (Right (a,future)) -> advancefinal (Foldl.fold (duplicate innerfold) [a]) future
            Free _ -> error continuedAfterEOF

data StreamStateM m a b = PristineM (Stream (Of b) (IterateeT (Feed a) m) ())
                        | WaitingM  (Feed a -> IterateeT (Feed a) m (Either () (b, Stream (Of b) (IterateeT (Feed a) m) ())))

newtype TransversionM m a b = 
        TransversionM { transduceM :: forall t r. (MonadTrans t, Monad (t m)) 
                                       => Stream (Of a) (t m) r 
                                       -> Stream (Of b) (t m) r 
                          }

transversionM :: (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
                  -> TransversionM m a b 
transversionM = TransversionM

instance Functor (TransversionM m a) where
    fmap f (TransversionM transducer) = TransversionM (S.map f . transducer) 

instance Profunctor (TransversionM m) where
    lmap f (TransversionM somefold) = TransversionM (somefold . S.map f)
    rmap = fmap

transvertM :: Monad m 
           => TransversionM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transvertM (TransversionM transducer) somefold = FoldM step begin done
    where
    begin = return (Pair somefold (PristineM (transducer evertedStreamM)))
    step (Pair innerfold (PristineM pristine)) i = do
        s <- advance innerfold pristine 
        step s i
    step (Pair innerfold (WaitingM waiting)) i = do 
        s <- TF.runFreeT (waiting (Input i))
        case s of
            TF.Pure (Left ()) -> error stoppedBeforeEOF
            TF.Pure (Right (a, nexx)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 nexx 
            TF.Free f -> return (Pair innerfold (WaitingM f))
    advance innerfold stream = do 
        r <- TF.runFreeT (next stream) 
        case r of
            TF.Pure (Left ()) -> error stoppedBeforeEOF
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 future
            TF.Free f -> return (Pair innerfold (WaitingM f))
    done (Pair innerfold (PristineM pristine)) = do
        s <- advance innerfold pristine 
        done s
    done (Pair innerfold (WaitingM waiting)) = do
        s <- TF.runFreeT (waiting EOF)
        case s of
            TF.Pure (Left ()) -> do
                Foldl.foldM innerfold []
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                r <- advancefinal step1 future
                Foldl.foldM r []
            TF.Free _ -> error continuedAfterEOF
    advancefinal innerfold stream = do
        r <- TF.runFreeT (next stream) 
        case r of
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advancefinal step1 future
            TF.Pure (Left ()) -> return innerfold
            TF.Free _ -> error continuedAfterEOF


newtype TransversionMIO m a b = 
        TransversionMIO { transduceMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                           => Stream (Of a) (t m) r 
                                           -> Stream (Of b) (t m) r 
                            }

instance Functor (TransversionMIO m a) where
    fmap f (TransversionMIO transducer) = TransversionMIO (S.map f . transducer) 

instance Profunctor (TransversionMIO m) where
    lmap f (TransversionMIO somefold) = TransversionMIO (somefold . S.map f)
    rmap = fmap

transversionMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
                  -> TransversionMIO m a b 
transversionMIO = TransversionMIO

transvertMIO :: (MonadIO m) 
             => TransversionMIO m b a 
             -> (forall x . FoldM m a x -> FoldM m b x)

transvertMIO (TransversionMIO transducer) somefold = FoldM step begin done
    where
    begin = return (Pair somefold (PristineM (transducer evertedStreamM)))
    step (Pair innerfold (PristineM pristine)) i = do
        s <- advance innerfold pristine 
        step s i
    step (Pair innerfold (WaitingM waiting)) i = do 
        s <- TF.runFreeT (waiting (Input i))
        case s of
            TF.Pure (Left ()) -> error stoppedBeforeEOF
            TF.Pure (Right (a, nexx)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 nexx 
            TF.Free f -> return (Pair innerfold (WaitingM f))
    advance innerfold stream = do 
        r <- TF.runFreeT (next stream) 
        case r of
            TF.Pure (Left ()) -> error stoppedBeforeEOF
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 future
            TF.Free f -> return (Pair innerfold (WaitingM f))
    done (Pair innerfold (PristineM pristine)) = do
        s <- advance innerfold pristine 
        done s
    done (Pair innerfold (WaitingM waiting)) = do
        s <- TF.runFreeT (waiting EOF)
        case s of
            TF.Pure (Left ()) -> do
                Foldl.foldM innerfold []
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                r <- advancefinal step1 future
                Foldl.foldM r []
            TF.Free _ -> error continuedAfterEOF
    advancefinal innerfold stream = do
        r <- TF.runFreeT (next stream) 
        case r of
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advancefinal step1 future
            TF.Pure (Left ()) -> return innerfold
            TF.Free _ -> error continuedAfterEOF

-- | If your stream-consuming computation can fail returning an 'Either',
-- compose it with this function before passing it to 'eversionM'.
-- 
-- >>> runIdentity . runExceptT $ L.foldM (evertM (eversionM (haltE . (\_ -> haltE (return (Left ())))))) [1..10]
-- Left ()
-- 
haltE :: (MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
        => t (ExceptT e m) (Either e r)  -- ^
        -> t (ExceptT e m) r
haltE action = action >>= lift . ExceptT . return

