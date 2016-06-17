{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}


{-| Most pull-to-push transformations in this module require functions that are 
    polymorphic over a monad transformer.  
    
    Because of this, some of the type signatures look internals, but actually many
    (suitably polymorphic) operations on 'Stream's will unify with them.
   
    To get "interruptible" operations that can exit early with an error, put a
    'ExceptT' transformer just below the polymorphic monad transformer. In
    practice, that means lifting functions like
    'Control.Monad.Trans.ExceptT.throwE' and 'Control.Error.Util.hoistEither' a
    number of times.
   
    Inspired by http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
-}

module Streaming.Eversion (
        -- * Stream folds 
        evert
    ,   evertM
    ,   evertM_
    ,   evertMIO
    ,   evertMIO_
        -- * Stream transformations 
    ,   transvert
    ,   transvertM
    ,   transvertMIO
        -- * Internals
    ,   Feed(..)
    ,   unsafeEvertM
    ,   unsafeTransvertM
    ) where

import           Prelude hiding ((.),id)
import           Data.Bifunctor
import           Data.Profunctor

import           Control.Category
import           Control.Foldl (Fold(..),FoldM(..),generalize,simplify)
import           Streaming (Stream,Of(..),yields,hoist,distribute,Sum(..),inspect,unseparate)
import           Streaming.Prelude (yield,next)
import           Streaming.Internal
import qualified Streaming.Prelude as S

import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Data.Functor.Identity
import           Control.Monad.Trans.Identity
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF

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

-- -- | A stream-folding function that can be turned into a pure, push-based fold. 
-- newtype Eversible a x = 
--         Eversible (forall m r. Monad m => Stream (Of a) m r -> m (Of x r))  
-- 
-- instance Functor (Eversible a) where
--     fmap f (Eversible somefold) = Eversible (fmap (first f) . somefold) 
-- 
-- instance Profunctor Eversible where
--     lmap f (Eversible somefold) = Eversible (somefold . S.map f)
--     rmap = fmap

stoppedBeforeEOF :: String
stoppedBeforeEOF = "Stopped before receiving EOF."

continuedAfterEOF :: String
continuedAfterEOF = "Continued after receiving EOF."

-- eversible :: (forall m r. Monad m => Stream (Of a) m r -> m (Of x r)) -> Eversible a x
-- eversible = Eversible
-- 
-- 
-- evert :: Eversible a x -> Fold a x
-- evert (Eversible consumer) = Fold step begin done
--     where
--     begin = consumer evertedStream
--     step s a = case s of
--         Pure _ -> error stoppedBeforeEOF
--         Free f -> f (Input a)
--     done s = case s of
--         Pure _ -> error stoppedBeforeEOF
--         Free f -> case f EOF of
--             Pure (a :> ()) -> a
--             Free _ -> error continuedAfterEOF


{- | Like 'Eversible', but gives the stream-folding function access to a base monad.
   
>>> :{
    let consume stream = lift (putStrLn "x") >> S.effects stream
    in  L.foldM (evertM (eversibleM_ consume)) ["a","b","c"]
    :}
x

    Note however that control operations can't be lifted through the transformer.
-}
-- newtype EversibleM m a x = 
--         EversibleM (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 
-- 
-- instance Functor (EversibleM m a) where
--     fmap f (EversibleM somefold) = EversibleM (fmap (first f) . somefold) 
-- 
-- instance Profunctor (EversibleM m) where
--     lmap f (EversibleM somefold) = EversibleM (somefold . S.map f)
--     rmap = fmap
-- 
-- eversibleM ::(forall t r . (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
--             -> EversibleM m a x
-- eversibleM = EversibleM                                                      
-- 
-- eversibleM_ :: (forall t r . (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m r) -- ^
--             -> EversibleM m a ()
-- eversibleM_ f = EversibleM (fmap (fmap ((:>) ())) f)
-- 
-- evertM :: Monad m => EversibleM m a x -> FoldM m a x
-- evertM (EversibleM consumer) = FoldM step begin done
--     where
--     begin = return (consumer evertedStreamM)
--     step (TF.FreeT ms) i = do
--         s <- ms
--         case s of
--             TF.Pure _ -> error stoppedBeforeEOF
--             TF.Free f -> return (f (Input i))
--     done (TF.FreeT ms) = do
--         s <- ms
--         case s of 
--             TF.Pure _ -> error stoppedBeforeEOF
--             TF.Free f -> do
--                 let TF.FreeT ms' = f EOF
--                 s' <- ms'
--                 case s' of
--                     TF.Pure (a :> ()) -> return a
--                     TF.Free _ -> error continuedAfterEOF
-- 
-- {-| Like 'EversibleM', but gives the stream-consuming function the ability to use 'liftIO'.
--  
-- >>> L.foldM (evertMIO (eversibleMIO_ S.print)) ["a","b","c"]
-- "a"
-- "b"
-- "c"
-- 
-- -}
-- newtype EversibleMIO m a x = 
--         EversibleMIO (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 
-- 
-- instance Functor (EversibleMIO m a) where
--     fmap f (EversibleMIO somefold) = EversibleMIO (fmap (first f) . somefold) 
-- 
-- instance Profunctor (EversibleMIO m) where
--     lmap f (EversibleMIO somefold) = EversibleMIO (somefold . S.map f)
--     rmap = fmap
-- 
-- eversibleMIO ::(forall t r . (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -- ^
--             -> EversibleMIO m a x
-- eversibleMIO = EversibleMIO                                                      
-- 
-- eversibleMIO_ :: (forall t r . (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m r) -- ^
--               -> EversibleMIO m a ()
-- eversibleMIO_ f = EversibleMIO (fmap (fmap ((:>) ())) f)
-- 
-- evertMIO :: MonadIO m => EversibleMIO m a x -> FoldM m a x 
-- evertMIO (EversibleMIO consumer) = FoldM step begin done
--     where
--     begin = return (consumer evertedStreamM)
--     step (TF.FreeT ms) i = do
--         s <- ms
--         case s of
--             TF.Pure _ -> error stoppedBeforeEOF
--             TF.Free f -> return (f (Input i))
--     done (TF.FreeT ms) = do
--         s <- ms
--         case s of 
--             TF.Pure _ -> error stoppedBeforeEOF
--             TF.Free f -> do
--                 let TF.FreeT ms' = f EOF
--                 s' <- ms'
--                 case s' of
--                     TF.Pure (a :> ()) -> return a
--                     TF.Free _ -> error continuedAfterEOF

internalsCat :: Monad m => Stream (Of a) (Stream ((->) (Feed a)) m) ()        
internalsCat = do
  r <- Effect (Step (Return . Return))
  case r of
      Input a -> Step (a :> internalsCat)
      EOF     -> Return ()  

-- cat :: Monad m => Stream (Of a) (Stream ((->) (Feed a)) m) ()
-- cat = do
--     r <- lift (yields id)
--     case r of
--         Input a -> do
--             yield a
--             cat
--         EOF -> return ()

evert :: (forall m r. Monad m => Stream (Of a) m r -> m (Of x r)) -> Fold a x
evert phi = simplify (unsafeEvertM phi)

evertM :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -> FoldM m a x
evertM phi = unsafeEvertM phi

evertM_ :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m r) -> FoldM m a ()
evertM_ phi = evertM (fmap (fmap ((:>) ())) phi)

evertMIO :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) -> FoldM m a x
evertMIO phi = unsafeEvertM phi

evertMIO_ :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m r) -> FoldM m a ()
evertMIO_ phi = evertMIO (fmap (fmap ((:>) ())) phi)

{-| A client with direct access to this function could supply a consumer that
    sneakily fed an EOF to the iteratee, trigerring an error. It's better to
    provide various wrapper functions that hide the iteratee transformer behind
    a polymorphic type variable.  
-}
unsafeEvertM :: (Monad m) 
            => (forall r. Stream (Of a) (Stream ((->) (Feed a)) m) r -> Stream ((->) (Feed a)) m (Of b r))
            -> FoldM m a b
unsafeEvertM consumer = FoldM step begin done
    where
    begin = return (consumer internalsCat)
    step str i = case str of       
      Return _ -> error stoppedBeforeEOF
      Step f   -> return (f (Input i))
      Effect m -> m >>= \str' -> step str' i
    done str = do
      e <- inspect str
      case e of
        Left _ -> error stoppedBeforeEOF
        Right f -> do
          e <- inspect (f EOF)
          case e of
            Left (a :> ()) -> return a
            Right _ -> error continuedAfterEOF 


transvert :: (forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r)
          -> Fold b x 
          -> Fold a x 
transvert phi = \somefold -> simplify ((unsafeTransvertM phi) (generalize somefold))

transvertM :: Monad m 
           => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
           -> FoldM m b x 
           -> FoldM m a x
transvertM phi = unsafeTransvertM phi

transvertMIO :: MonadIO m 
             => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
             -> FoldM m b x 
             -> FoldM m a x
transvertMIO phi = unsafeTransvertM phi

data Pair a b = Pair !a !b

data StreamStateM m a b = PristineM (Stream (Sum (Of b) ((->) (Feed a))) m ())
                        | WaitingM  (Feed a -> Stream (Sum (Of b) ((->) (Feed a))) m ())

{-| A client with direct access to this function could supply a consumer that
    sneakily fed an EOF to the iteratee, trigerring an error. It's better to
    provide various wrapper functions that hide the iteratee transformer behind
    a polymorphic type variable.  
-}
unsafeTransvertM :: Monad m 
                 => (forall r. Stream (Of a) (Stream ((->) (Feed a)) m) r -> Stream (Of b) (Stream ((->) (Feed a)) m) r) -- ^
                 -> FoldM m b x 
                 -> FoldM m a x
unsafeTransvertM transducer (FoldM innerstep innerbegin innerdone) = FoldM step begin done
    where
    begin = do
        innerbegin' <- innerbegin
        return (Pair innerbegin' (PristineM (unseparate (transducer internalsCat))))
    step (Pair innerstate (PristineM pristine)) i = do
        s <- advance innerstate pristine 
        step s i
    step (Pair innerstate (WaitingM waiting)) i = do 
        s <- inspect (waiting (Input i))
        case s of
            Left () -> error stoppedBeforeEOF
            Right (InL (a :> future)) -> do
                step1 <- innerstep innerstate a
                advance step1 future 
            Right (InR f) -> return (Pair innerstate (WaitingM f))
    advance innerstate stream = do 
        r <- inspect stream 
        case r of
            Left () -> error stoppedBeforeEOF
            Right (InL (a :> future)) -> do
                step1 <- innerstep innerstate a
                advance step1 future
            Right (InR f) -> return (Pair innerstate (WaitingM f))
    done (Pair innerstate (PristineM pristine)) = do
        s <- advance innerstate pristine 
        done s
    done (Pair innerstate (WaitingM waiting)) = do
        s <- inspect (waiting EOF)
        case s of
            Left () -> do
                innerdone innerstate
            Right (InL (a :> future)) -> do
                step1 <- innerstep innerstate a
                r <- advancefinal step1 future
                innerdone r
            Right _ -> error continuedAfterEOF
    advancefinal innerstate stream = do
        r <- inspect stream
        case r of
            Left () -> return innerstate
            Right (InL (a :> future)) -> do
                step1 <- innerstep innerstate a
                advancefinal step1 future
            Right (InR _) -> error continuedAfterEOF

