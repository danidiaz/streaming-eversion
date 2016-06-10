{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ViewPatterns #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion (
        StreamFold(..)
    ,   evert
    ,   withFold
    ,   StreamFoldM(..)
    ,   evertM
    ,   withFoldM
    ,   StreamFoldMIO(..)
    ,   evertMIO
    ,   withFoldMIO
    ,   StreamTransducer(..)
    ,   transvert
    ,   StreamTransducerM(..)
    ,   transvertM
    ,   StreamTransducerMIO(..)
    ,   transvertMIO
    ) where

import           Data.Functor.Identity

import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl
import           Streaming (Stream,Of(..))
import           Streaming.Prelude (yield,fold,next)
import qualified Streaming.Prelude as S

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF
import           Control.Comonad

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

withFold :: Fold a x -> StreamFold a x  
withFold sf = StreamFold (Foldl.purely S.fold sf) 

evert :: StreamFold a x -> Fold a x
evert (StreamFold consumer) = Fold step begin done
    where
    begin = consumer evertedStream
    step s a = case s of
        Pure _ -> error "Should never happen - unexpected stop."
        Free f -> f (Input a)
    done s = case s of
        Pure _ -> error "Should never happen - unexpected stop."
        Free f -> case f EOF of
            Pure (a :> ()) -> a
            Free _ -> error "Should never happen - continue after EOF."


newtype StreamFoldM m a x = 
        StreamFoldM { consumeM :: forall t r. (MonadTrans t, Monad (t m)) 
                               => Stream (Of a) (t m) r 
                               -> t m (Of x r) 
                    }

withFoldM :: Monad m => FoldM m a x -> StreamFoldM m a x  
withFoldM sfm = StreamFoldM (Foldl.impurely S.foldM (Foldl.hoists lift sfm))

evertM :: Monad m => StreamFoldM m a x -> FoldM m a x
evertM (StreamFoldM consumer) = FoldM step begin done
    where
    begin = return (consumer evertedStreamM)
    step (TF.FreeT ms) i = do
        s <- ms
        case s of
            TF.Pure _ -> error "Should never happen - unexpected stop."
            TF.Free f -> return (f (Input i))
    done (TF.FreeT ms) = do
        s <- ms
        case s of 
            TF.Pure _ -> error "Should never happen - unexpected stop."
            TF.Free f -> do
                let TF.FreeT ms' = f EOF
                s' <- ms'
                case s' of
                    TF.Pure (a :> ()) -> return a
                    TF.Free _ -> error "Should never happen: continue after EOF."

newtype StreamFoldMIO m a x = 
        StreamFoldMIO { consumeMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) 
                                   => Stream (Of a) (t m) r 
                                   -> t m (Of x r)) 
                      }

evertMIO :: MonadIO m => StreamFoldMIO m a x -> FoldM m a x 
evertMIO (StreamFoldMIO consumer) = FoldM step begin done
    where
    begin = return (consumer evertedStreamM)
    step (TF.FreeT ms) i = do
        s <- ms
        case s of
            TF.Pure _ -> error "Should never happen - unexpected stop."
            TF.Free f -> return (f (Input i))
    done (TF.FreeT ms) = do
        s <- ms
        case s of 
            TF.Pure _ -> error "Should never happen - unexpected stop."
            TF.Free f -> do
                let TF.FreeT ms' = f EOF
                s' <- ms'
                case s' of
                    TF.Pure (a :> ()) -> return a
                    TF.Free _ -> error "Should never happen: continue after EOF."

withFoldMIO :: MonadIO m => FoldM m a x -> StreamFoldM m a x  
withFoldMIO sfm = StreamFoldM (Foldl.impurely S.foldM (Foldl.hoists lift sfm))

newtype StreamTransducer a b = 
        StreamTransducer { transduce :: forall m r. Monad m 
                                     => Stream (Of a) m r 
                                     -> Stream (Of b) m r 
                         }

data Pair a b = Pair !a !b

data StreamState a b = Pristine (Stream (Of b) (Iteratee (Feed a)) ())
                     | Waiting  (Feed a -> Iteratee (Feed a) (Either () (b, Stream (Of b) (Iteratee (Feed a)) ())))

transvert :: StreamTransducer b a 
          -> (forall x. Fold a x -> Fold b x)
transvert (StreamTransducer transvertr) somefold = Fold step begin' done
    where
    begin' = Pair somefold (Pristine (transvertr evertedStream))
    step (Pair innerfold (Pristine pris)) i = step (advance innerfold pris) i
    step (Pair innerfold (Waiting func)) i = 
        case func (Input i) of
            Pure (Left ()) -> error "should never happen 1"
            Pure (Right (a, nexx)) -> advance (Foldl.fold (duplicate innerfold) [a]) nexx
            Free f -> Pair innerfold (Waiting f)
    advance innerfold pris =  
        case next pris of
            Pure (Left ()) -> error "should never happen 3"
            Pure (Right (a,future)) -> advance (Foldl.fold (duplicate innerfold) [a]) future
            Free f -> Pair innerfold (Waiting f)
    done (Pair innerfold (Pristine pris)) = done (advance innerfold pris) 
    done (Pair innerfold (Waiting func)) =
        case func EOF of
            Pure (Left ()) -> extract innerfold
            Pure (Right (a, nexx)) -> extract (advancefinal (Foldl.fold (duplicate innerfold) [a]) nexx)
            Free _ -> error "should never happen 2"
    advancefinal innerfold pris =  
        case next pris of
            Pure (Left ()) -> innerfold 
            Pure (Right (a,future)) -> advancefinal (Foldl.fold (duplicate innerfold) [a]) future
            Free _ -> error "should never happen 4"

data StreamStateM m a b = PristineM (Stream (Of b) (IterateeT (Feed a) m) ())
                        | WaitingM  (Feed a -> IterateeT (Feed a) m (Either () (b, Stream (Of b) (IterateeT (Feed a) m) ())))

newtype StreamTransducerM m a b = 
        StreamTransducerM { transduceM :: forall t r. (MonadTrans t, Monad (t m)) 
                                       => Stream (Of a) (t m) r 
                                       -> Stream (Of b) (t m) r 
                          }

transvertM :: Monad m 
           => StreamTransducerM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transvertM (StreamTransducerM transvertr) somefold = FoldM step begin' done
    where
    begin' = return (Pair somefold (PristineM (transvertr evertedStreamM)))
    step (Pair innerfold (PristineM pris)) i = do
        s <- advance innerfold pris 
        step s i
    step (Pair innerfold (WaitingM func)) i = do 
        s <- TF.runFreeT (func (Input i))
        case s of
            TF.Pure (Left ()) -> error "should never happen 1"
            TF.Pure (Right (a, nexx)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 nexx 
            TF.Free f -> return (Pair innerfold (WaitingM f))
    advance innerfold pris = do 
        r <- TF.runFreeT (next pris) 
        case r of
            TF.Pure (Left ()) -> error "should never happen 3"
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 future
            TF.Free f -> return (Pair innerfold (WaitingM f))
    done (Pair innerfold (PristineM pris)) = do
        s <- advance innerfold pris 
        done s
    done (Pair innerfold (WaitingM func)) = do
        s <- TF.runFreeT (func EOF)
        case s of
            TF.Pure (Left ()) -> do
                Foldl.foldM innerfold []
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                r <- advancefinal step1 future
                Foldl.foldM r []
            TF.Free _ -> error "should never happen 4"
    advancefinal innerfold pris = do
        r <- TF.runFreeT (next pris) 
        case r of
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advancefinal step1 future
            TF.Pure (Left ()) -> return innerfold
            TF.Free _ -> error "should never happen 4"


newtype StreamTransducerMIO m a b = 
        StreamTransducerMIO { transduceMIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                           => Stream (Of a) (t m) r 
                                           -> Stream (Of b) (t m) r 
                            }

transvertMIO :: (MonadIO m) 
             => StreamTransducerMIO m b a 
             -> (forall x . FoldM m a x -> FoldM m b x)
transvertMIO (StreamTransducerMIO transvertr) somefold = FoldM step begin' done
    where
    begin' = return (Pair somefold (PristineM (transvertr evertedStreamM)))
    step (Pair innerfold (PristineM pris)) i = do
        s <- advance innerfold pris 
        step s i
    step (Pair innerfold (WaitingM func)) i = do 
        s <- TF.runFreeT (func (Input i))
        case s of
            TF.Pure (Left ()) -> error "should never happen 1"
            TF.Pure (Right (a, nexx)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 nexx 
            TF.Free f -> return (Pair innerfold (WaitingM f))
    advance innerfold pris = do 
        r <- TF.runFreeT (next pris) 
        case r of
            TF.Pure (Left ()) -> error "should never happen 3"
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advance step1 future
            TF.Free f -> return (Pair innerfold (WaitingM f))
    done (Pair innerfold (PristineM pris)) = do
        s <- advance innerfold pris 
        done s
    done (Pair innerfold (WaitingM func)) = do
        s <- TF.runFreeT (func EOF)
        case s of
            TF.Pure (Left ()) -> do
                Foldl.foldM innerfold []
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                r <- advancefinal step1 future
                Foldl.foldM r []
            TF.Free _ -> error "should never happen 4"
    advancefinal innerfold pris = do
        r <- TF.runFreeT (next pris) 
        case r of
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (Foldl.duplicateM innerfold) [a]
                advancefinal step1 future
            TF.Pure (Left ()) -> return innerfold
            TF.Free _ -> error "should never happen 4"
