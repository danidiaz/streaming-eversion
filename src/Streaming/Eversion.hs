{-# LANGUAGE RankNTypes #-}


{-| Most pull-to-push transformations in this module require functions that are 
    polymorphic over a monad transformer.  
    
    Because of this, some of the type signatures look scary, but actually many
    (suitably polymorphic) operations on 'Stream's will unify with them.
   
    To get "interruptible" operations that can exit early with an error, put a
    'ExceptT' transformer just below the polymorphic monad transformer. See
    'throwE1' and 'throwE2'.
   
    Inspired by http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
-}

module Streaming.Eversion (
        -- * Stream folds 
        Eversible
    ,   eversible
    ,   evert
    ,   EversibleM
    ,   eversibleM
    ,   eversibleM_
    ,   evertM
    ,   EversibleMIO
    ,   eversibleMIO
    ,   eversibleMIO_
    ,   evertMIO
        -- * Stream transformations 
    ,   Transvertible
    ,   transvertible
    ,   transvert
    ,   TransvertibleM
    ,   transvertibleM
    ,   runTransvertibleM
    ,   transvertM
    ,   TransvertibleMIO
    ,   transvertibleMIO
    ,   runTransvertibleMIO
    ,   transvertMIO
        -- * Throwing errors
        -- $errors
    ,   throwE1
    ,   throwE2
    ,   hoistEither1
    ,   hoistEither2
    ) where

import           Prelude hiding ((.),id)
import           Data.Bifunctor
import           Data.Profunctor

import           Control.Category
import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl
import           Streaming (Stream,Of(..),hoist,distribute)
import           Streaming.Prelude (yield,next)
import qualified Streaming.Prelude as S

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Identity
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
>>> import           Streaming.Prelude (yield,next,for)
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

-- | A stream-folding function that can be turned into a pure, push-based fold. 
newtype Eversible a x = 
        Eversible (forall m r. Monad m => Stream (Of a) m r -> m (Of x r))  

instance Functor (Eversible a) where
    fmap f (Eversible somefold) = Eversible (fmap (first f) . somefold) 

instance Profunctor Eversible where
    lmap f (Eversible somefold) = Eversible (somefold . S.map f)
    rmap = fmap

stoppedBeforeEOF :: String
stoppedBeforeEOF = "Stopped before receiving EOF."

continuedAfterEOF :: String
continuedAfterEOF = "Continued after receiving EOF."

eversible :: (forall m r. Monad m => Stream (Of a) m r -> m (Of x r)) -> Eversible a x
eversible = Eversible


evert :: Eversible a x -> Fold a x
evert (Eversible consumer) = Fold step begin done
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


{- | Like 'Eversible', but gives the stream-folding function access to a base monad.
   
>>> :{
    let consume stream = lift (putStrLn "x") >> S.effects stream
    in  L.foldM (evertM (eversibleM_ consume)) ["a","b","c"]
    :}
x

    Note however that control operations can't be lifted through the transformer.
-}
newtype EversibleM m a x = 
        EversibleM (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 

instance Functor (EversibleM m a) where
    fmap f (EversibleM somefold) = EversibleM (fmap (first f) . somefold) 

instance Profunctor (EversibleM m) where
    lmap f (EversibleM somefold) = EversibleM (somefold . S.map f)
    rmap = fmap

eversibleM ::(forall t r . (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
            -> EversibleM m a x
eversibleM = EversibleM                                                      

eversibleM_ :: (forall t r . (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m r) -- ^
            -> EversibleM m a ()
eversibleM_ f = EversibleM (fmap (fmap ((:>) ())) f)

evertM :: Monad m => EversibleM m a x -> FoldM m a x
evertM (EversibleM consumer) = FoldM step begin done
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

{-| Like 'EversibleM', but gives the stream-consuming function the ability to use 'liftIO'.
 
>>> L.foldM (evertMIO (eversibleMIO_ S.print)) ["a","b","c"]
"a"
"b"
"c"

-}
newtype EversibleMIO m a x = 
        EversibleMIO (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 

instance Functor (EversibleMIO m a) where
    fmap f (EversibleMIO somefold) = EversibleMIO (fmap (first f) . somefold) 

instance Profunctor (EversibleMIO m) where
    lmap f (EversibleMIO somefold) = EversibleMIO (somefold . S.map f)
    rmap = fmap

eversibleMIO ::(forall t r . (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
            -> EversibleMIO m a x
eversibleMIO = EversibleMIO                                                      

eversibleMIO_ :: (forall t r . (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m r) -- ^
              -> EversibleMIO m a ()
eversibleMIO_ f = EversibleMIO (fmap (fmap ((:>) ())) f)

evertMIO :: MonadIO m => EversibleMIO m a x -> FoldM m a x 
evertMIO (EversibleMIO consumer) = FoldM step begin done
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

-- | A stream-transforming function that can be turned into fold-transforming function.
newtype Transvertible a b = 
        Transvertible (forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r)

instance Functor (Transvertible a) where
    fmap f (Transvertible transducer) = Transvertible (S.map f . transducer) 

instance Profunctor Transvertible where
    lmap f (Transvertible somefold) = Transvertible (somefold . S.map f)
    rmap = fmap

instance Category Transvertible where
    id = Transvertible id
    (.) = \(Transvertible t1) (Transvertible t2) -> Transvertible (t1 . t2)

data Pair a b = Pair !a !b

data StreamState a b = Pristine (Stream (Of b) (Iteratee (Feed a)) ())
                     | Waiting  (Feed a -> Iteratee (Feed a) (Either () (b, Stream (Of b) (Iteratee (Feed a)) ())))


transvertible :: (forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r) -- ^
                 -> Transvertible a b
transvertible = Transvertible

transvert :: Transvertible b a 
          -> (forall x. Fold a x -> Fold b x)
transvert (Transvertible transducer) somefold = Fold step begin done
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

-- | Like 'Transvertible', but gives the stream-transforming function access to a base monad.
--   
--   Note however that control operations can't be lifted through the transformer.
--
newtype TransvertibleM m a b = 
        TransvertibleM (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)

transvertibleM :: (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r) -- ^
                  -> TransvertibleM m a b 
transvertibleM = TransvertibleM

instance Category (TransvertibleM m) where
    id = TransvertibleM id
    (.) = \(TransvertibleM t1) (TransvertibleM t2) -> TransvertibleM (t1 . t2)

-- | Recover the stored function, discarding the transformer.
--   
runTransvertibleM :: TransvertibleM m a b -- ^
                  -> (forall r. Monad  m => Stream (Of a) m r -> Stream (Of b)  m r) 
runTransvertibleM  (TransvertibleM t) = \stream -> runIdentityT (distribute (t (hoist lift stream)))

instance Functor (TransvertibleM m a) where
    fmap f (TransvertibleM transducer) = TransvertibleM (S.map f . transducer) 

instance Profunctor (TransvertibleM m) where
    lmap f (TransvertibleM somefold) = TransvertibleM (somefold . S.map f)
    rmap = fmap

transvertM :: Monad m 
           => TransvertibleM m b a 
           -> (forall x . FoldM m a x -> FoldM m b x)
transvertM (TransvertibleM transducer) somefold = FoldM step begin done
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


-- | Like 'TransvertibleM', but gives the stream-transforming function the ability to use 'liftIO'.
--   
newtype TransvertibleMIO m a b = 
        TransvertibleMIO (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)

instance Category (TransvertibleMIO m) where
    id = TransvertibleMIO id
    (.) = \(TransvertibleMIO t1) (TransvertibleMIO t2) -> TransvertibleMIO (t1 . t2)

instance Functor (TransvertibleMIO m a) where
    fmap f (TransvertibleMIO transducer) = TransvertibleMIO (S.map f . transducer) 

instance Profunctor (TransvertibleMIO m) where
    lmap f (TransvertibleMIO somefold) = TransvertibleMIO (somefold . S.map f)
    rmap = fmap

transvertibleMIO :: (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r) -- ^
                  -> TransvertibleMIO m a b 
transvertibleMIO = TransvertibleMIO

runTransvertibleMIO :: TransvertibleMIO m a b -- ^
                    -> (forall r. MonadIO m => Stream (Of a) m r -> Stream (Of b)  m r) 
runTransvertibleMIO  (TransvertibleMIO t) = \stream -> runIdentityT (distribute (t (hoist lift stream)))

transvertMIO :: (MonadIO m) 
             => TransvertibleMIO m b a -- ^
             -> (forall x . FoldM m a x -> FoldM m b x)

transvertMIO (TransvertibleMIO transducer) somefold = FoldM step begin done
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

{- $errors

   foo 
-}

{-| Throws error in an 'ExceptT' sitting one layer below the topmost layer. 

@
throwE1 = lift . throwE
@

Often useful with 'evertM':

>>> runExceptT $ L.foldM (evertM (eversibleM (\_ -> throwE1 ()))) [1..10]
Left ()

-} 
throwE1 :: (MonadTrans t, Monad m) 
        => e -> t (ExceptT e m) a -- ^
throwE1 = lift . throwE

{-| Throws error in an 'ExceptT' sitting two layers below the topmost layer.
 
@
throwE2 = lift . lift . throwE
@

Often useful with 'tansvertibleM':

>>> :{ 
    runExceptT $ L.foldM (transvertM (transvertibleM (\stream -> for stream (\_ -> throwE2 ()))) 
                                     (L.generalize L.list)) 
                         [1..10]
    :}
Left ()

-}
throwE2 :: (MonadTrans stream, MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
        => e -> stream (t (ExceptT e m)) a -- ^
throwE2 = lift . lift . throwE

-- | Hoists an 'Either' to an 'ExceptT' sitting below the topmost layer.
hoistEither1 :: (MonadTrans t, Monad m) 
             => Either e a -> t (ExceptT e m) a -- ^
hoistEither1 = lift . ExceptT . return

-- | Hoists an 'Either' to an 'ExceptT' sitting two layers below the topmost layer.
hoistEither2 :: (MonadTrans stream, MonadTrans t, Monad m, Monad (t (ExceptT e m))) 
             => Either e a -> (stream (t (ExceptT e m))) a -- ^ 
hoistEither2 = lift . lift . ExceptT . return

