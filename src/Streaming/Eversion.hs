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
        StreamFold(..)
    ,   evert
    ,   withFold
    ,   StreamFoldM(..)
    ,   evertM
    ,   withFoldM
    ,   StreamFoldMIO(..)
    ,   evertMIO
    ,   withFoldMIO
        -- * Stream transducers
    ,   StreamTransducer(..)
    ,   transvert
    ,   StreamTransducerM(..)
    ,   transvertM
    ,   StreamTransducerMIO(..)
    ,   transvertMIO
        -- * Utility functions
    ,   haltedE
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
>>  import           Control.Foldl (Fold(..),FoldM(..))
>>  import qualified Control.Foldl as L
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

newtype StreamFold a x = 
        StreamFold { consume :: forall m r. Monad m 
                             => Stream (Of a) m r 
                             -> m (Of x r) 
                   } 

instance Functor (StreamFold a) where
    fmap f (StreamFold somefold) = StreamFold (fmap (first f) . somefold) 

instance Profunctor StreamFold where
    lmap f (StreamFold somefold) = StreamFold (somefold . S.map f)
    rmap = fmap

stoppedBeforeEOF :: String
stoppedBeforeEOF = "Stopped before receiving EOF."

continuedAfterEOF :: String
continuedAfterEOF = "Continued after receiving EOF."

withFold :: Fold a x -> StreamFold a x  
withFold sf = StreamFold (Foldl.purely S.fold sf) 

evert :: StreamFold a x -> Fold a x
evert (StreamFold consumer) = Fold step begin done
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


newtype StreamFoldM m a x = 
        StreamFoldM { consumeM :: forall t r. (MonadTrans t, Monad (t m)) 
                               => Stream (Of a) (t m) r 
                               -> t m (Of x r) 
                    }

instance Functor (StreamFoldM m a) where
    fmap f (StreamFoldM somefold) = StreamFoldM (fmap (first f) . somefold) 

instance Profunctor (StreamFoldM m) where
    lmap f (StreamFoldM somefold) = StreamFoldM (somefold . S.map f)
    rmap = fmap

withFoldM :: Monad m => FoldM m a x -> StreamFoldM m a x  
withFoldM sfm = StreamFoldM (Foldl.impurely S.foldM (Foldl.hoists lift sfm))

evertM :: Monad m => StreamFoldM m a x -> FoldM m a x
evertM (StreamFoldM consumer) = FoldM step begin done
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

newtype StreamFoldMIO m a x = 
        StreamFoldMIO { consumeMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) 
                                   => Stream (Of a) (t m) r 
                                   -> t m (Of x r)) 
                      }

instance Functor (StreamFoldMIO m a) where
    fmap f (StreamFoldMIO somefold) = StreamFoldMIO (fmap (first f) . somefold) 

instance Profunctor (StreamFoldMIO m) where
    lmap f (StreamFoldMIO somefold) = StreamFoldMIO (somefold . S.map f)
    rmap = fmap

evertMIO :: MonadIO m => StreamFoldMIO m a x -> FoldM m a x 
evertMIO (StreamFoldMIO consumer) = FoldM step begin done
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

withFoldMIO :: MonadIO m => FoldM m a x -> StreamFoldM m a x  
withFoldMIO sfm = StreamFoldM (Foldl.impurely S.foldM (Foldl.hoists lift sfm))

newtype StreamTransducer a b = 
        StreamTransducer { transduce :: forall m r. Monad m 
                                     => Stream (Of a) m r 
                                     -> Stream (Of b) m r 
                         } 

instance Functor (StreamTransducer a) where
    fmap f (StreamTransducer transducer) = StreamTransducer (S.map f . transducer) 

instance Profunctor StreamTransducer where
    lmap f (StreamTransducer somefold) = StreamTransducer (somefold . S.map f)
    rmap = fmap

data Pair a b = Pair !a !b

data StreamState a b = Pristine (Stream (Of b) (Iteratee (Feed a)) ())
                     | Waiting  (Feed a -> Iteratee (Feed a) (Either () (b, Stream (Of b) (Iteratee (Feed a)) ())))

transvert :: StreamTransducer b a 
          -> (forall x. Fold a x -> Fold b x)
transvert (StreamTransducer transducer) somefold = Fold step begin done
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

newtype StreamTransducerM m a b = 
        StreamTransducerM { transduceM :: forall t r. (MonadTrans t, Monad (t m)) 
                                       => Stream (Of a) (t m) r 
                                       -> Stream (Of b) (t m) r 
                          }

instance Functor (StreamTransducerM m a) where
    fmap f (StreamTransducerM transducer) = StreamTransducerM (S.map f . transducer) 

instance Profunctor (StreamTransducerM m) where
    lmap f (StreamTransducerM somefold) = StreamTransducerM (somefold . S.map f)
    rmap = fmap

transvertM :: Monad m 
           => StreamTransducerM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transvertM (StreamTransducerM transducer) somefold = FoldM step begin done
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


newtype StreamTransducerMIO m a b = 
        StreamTransducerMIO { transduceMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                           => Stream (Of a) (t m) r 
                                           -> Stream (Of b) (t m) r 
                            }

instance Functor (StreamTransducerMIO m a) where
    fmap f (StreamTransducerMIO transducer) = StreamTransducerMIO (S.map f . transducer) 

instance Profunctor (StreamTransducerMIO m) where
    lmap f (StreamTransducerMIO somefold) = StreamTransducerMIO (somefold . S.map f)
    rmap = fmap

transvertMIO :: (MonadIO m) 
             => StreamTransducerMIO m b a 
             -> (forall x . FoldM m a x -> FoldM m b x)
transvertMIO (StreamTransducerMIO transducer) somefold = FoldM step begin done
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

haltedE :: (MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
        => t (ExceptT e m) (Either e r)  -- ^
        -> t (ExceptT e m) r
haltedE action = action >>= lift . ExceptT . return

