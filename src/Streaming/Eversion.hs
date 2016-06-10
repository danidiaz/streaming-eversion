{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ViewPatterns #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion (
        StreamConsumer(..)
    ,   evert
    ,   StreamConsumerM(..)
    ,   evertM
    ,   StreamConsumerMIO(..)
    ,   evertMIO
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

evertedProducer :: forall a. Stream (Of a) (Iteratee (Feed a)) ()
evertedProducer = do
    r <- lift (liftF id)
    case r of
        Input a -> do
            yield a
            evertedProducer
        EOF -> return ()

type IterateeT a m = TF.FreeT ((->) a) m 

evertedProducer' :: forall a m. Monad m => Stream (Of a) (IterateeT (Feed a) m) ()
evertedProducer' = do
    r <- lift (TF.liftF id)
    case r of
        Input a -> do
            yield a
            evertedProducer'
        EOF -> return ()

-----------------------------------------------------------------------------------------

newtype StreamConsumer a x = 
        StreamConsumer { consume :: forall m r. Monad m 
                                 => Stream (Of a) m r 
                                 -> m (Of x r) 
                       } 

evert :: StreamConsumer a x -> Fold a x
evert (StreamConsumer consumer) = Fold step begin done
    where
    begin = consumer evertedProducer
    step s a = case s of
        Pure _ -> error "Should never happen - unexpected stop."
        Free f -> f (Input a)
    done s = case s of
        Pure _ -> error "Should never happen - unexpected stop."
        Free f -> case f EOF of
            Pure (a :> ()) -> a
            Free _ -> error "Should never happen: continue after EOF."

newtype StreamConsumerM m a x = 
        StreamConsumerM { consumeM :: forall t r. (MonadTrans t, Monad (t m)) 
                                   => Stream (Of a) (t m) r 
                                   -> t m (Of x r) 
                        }

evertM :: Monad m => StreamConsumerM m a x -> FoldM m a x
evertM (StreamConsumerM consumer) = FoldM step begin done
    where
    begin = return (consumer evertedProducer')
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

newtype StreamConsumerMIO m a x = 
        StreamConsumerMIO { consumeMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) 
                                       => Stream (Of a) (t m) r 
                                       -> t m (Of x r)) 
                         }

evertMIO :: MonadIO m => StreamConsumerMIO m a x -> FoldM m a x 
evertMIO (StreamConsumerMIO consumer) = FoldM step begin done
    where
    begin = return (consumer evertedProducer')
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

newtype StreamTransducer a b = 
        StreamTransducer { getTransducer :: forall m r. Monad m 
                                         => Stream (Of a) m r 
                                         -> Stream (Of b) m r 
                         }

data Pair a b = Pair !a !b

data StreamState a b = Pristine (Stream (Of b) (Iteratee (Feed a)) ())
                     | Started  (Feed a -> Iteratee (Feed a) (Either () (b, Stream (Of b) (Iteratee (Feed a)) ())))

transvert :: StreamTransducer b a 
          -> (forall x. Fold a x -> Fold b x)
transvert (StreamTransducer transvertr) somefold = Fold step' begin' done'
    where
    begin' = Pair somefold (Pristine (transvertr evertedProducer))
    step' (Pair innerfold (Pristine pris)) i = step' (advance innerfold pris) i
    step' (Pair innerfold (Started func)) i = 
        case func (Input i) of
            Pure (Left ()) -> error "should never happen 1"
            Pure (Right (a, nexx)) -> advance (Foldl.fold (duplicate innerfold) [a]) nexx
            Free f -> Pair innerfold (Started f)
    done' (Pair innerfold (Pristine pris)) = done' (advance innerfold pris) 
    done' (Pair innerfold (Started func)) =
        case func EOF of
            Pure (Left ()) -> extract innerfold
            Pure (Right (a, nexx)) -> extract (advancefinal (Foldl.fold (duplicate innerfold) [a]) nexx)
            Free _ -> error "should never happen 2"
    advance innerfold pris =  
        case next pris of
            Pure (Right (a,future)) -> advance (Foldl.fold (duplicate innerfold) [a]) future
            Pure (Left ()) -> error "should never happen 3"
            Free f -> Pair innerfold (Started f)
    advancefinal innerfold pris =  
        case next pris of
            Pure (Right (a,future)) -> advancefinal (Foldl.fold (duplicate innerfold) [a]) future
            Pure (Left ()) -> innerfold 
            Free _ -> error "should never happen 4"

data StreamStateM m a b = PristineM (Stream (Of b) (IterateeT (Feed a) m) ())
                        | StartedM  (Feed a -> IterateeT (Feed a) m (Either () (b, Stream (Of b) (IterateeT (Feed a) m) ())))

newtype StreamTransducerM m a b = 
        StreamTransducerM { getTransducerM :: forall t r. (MonadTrans t, Monad (t m)) 
                                           => Stream (Of b) (t m) r 
                                           -> Stream (Of a) (t m) r 
                          }

transvertM :: Monad m 
           => StreamTransducerM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transvertM (StreamTransducerM transvertr) somefold = FoldM step' begin' done'
    where
    begin' = return (Pair somefold (PristineM (transvertr evertedProducer')))
    step' (Pair innerfold (PristineM pris)) i = 
        undefined
--            step' (advance innerfold pris) i
    step' (Pair innerfold (StartedM func)) i = 
        undefined
--        case func (Input i) of
--            Pure (Left ()) -> error "should never happen 1"
--            Pure (Right (a, nexx)) -> advance (Foldl.fold (duplicate innerfold) [a]) nexx
--            Free f -> Pair innerfold (StartedM f)
    done' (Pair innerfold (PristineM pris)) = 
        undefined
--       done' (advance innerfold pris) 
    done' (Pair innerfold (StartedM func)) = 
        undefined
--        case func EOF of
--            Pure (Left ()) -> extract innerfold
--            Pure (Right (a, nexx)) -> extract (advancefinal (Foldl.fold (duplicate innerfold) [a]) nexx)
--            Free _ -> error "should never happen 2"
    advance innerfold pris = do 
        r <- next pris
        case r of
            TF.Pure (Right (a,future)) -> do
                step1 <- Foldl.foldM (duplicateM innerfold) [a]
                advance step1 future
            TF.Pure (Left ()) -> error "should never happen 3"
            TF.Free f -> return (Pair innerfold (StartedM f))
--    advancefinal innerfold pris =  
--        case next pris of
--            Pure (Right (a,future)) -> advancefinal (Foldl.fold (duplicate innerfold) [a]) future
--            Pure (Left ()) -> innerfold 
--            Free _ -> error "should never happen 4"

newtype StreamTransducerMIO m a b = 
        StreamTransducerMIO { getTransducerIO :: forall t r. (MonadTrans t, MonadIO (t m)) 
                                              => Stream (Of b) (t m) r 
                                              -> Stream (Of a) (t m) r 
                            }

transvertMIO :: Monad m 
             => StreamTransducerMIO m b a 
             -> (forall x . FoldM m a x -> FoldM m b x)
transvertMIO = undefined
