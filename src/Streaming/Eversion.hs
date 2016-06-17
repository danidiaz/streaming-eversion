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
    ,   evertR
    ,   evertR_
        -- * Stream transformations 
    ,   transvert
    ,   transvertM
    ,   transvertMIO
    ,   transvertR
        -- * Internals
--    ,   Feed(..)
    ,   generalEvertM
    ,   generalTransvertM
    ) where

import           Prelude 
import           Control.Foldl (Fold(..),FoldM(..),generalize,simplify)
import           Streaming (Stream,Of(..),Sum(..),inspect,unseparate,MonadResource)
import           Streaming.Internal
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class

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

stoppedBeforeEOF :: String
stoppedBeforeEOF = "Stopped before receiving EOF."

continuedAfterEOF :: String
continuedAfterEOF = "Continued after receiving EOF."

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

evert :: (forall m r. Monad m => Stream (Of a) m r -> m (Of x r)) 
      -> Fold a x -- ^
evert phi = simplify (generalEvertM phi)

{- | Like 'evert', but gives the stream-folding function access to a base monad.
   
>>> :{
    let consume stream = lift (putStrLn "x") >> S.effects stream
    in  L.foldM (evertM_ consume) ["a","b","c"]
    :}
x

    Note however that control operations can't be lifted through the transformer.
-}
evertM :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 
       -> FoldM m a x -- ^
evertM phi = generalEvertM phi

evertM_ :: Monad m => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> t m r) 
        -> FoldM m a () -- ^
evertM_ phi = evertM (fmap (fmap ((:>) ())) phi)

{-| Like 'evertM', but gives the stream-consuming function the ability to use 'liftIO'.
 
>>> L.foldM (evertMIO_ S.print) ["a","b","c"]
"a"
"b"
"c"

-}
evertMIO :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 
         -> FoldM m a x -- ^
evertMIO phi = generalEvertM phi

evertMIO_ :: MonadIO m => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> t m r) 
          -> FoldM m a () -- ^
evertMIO_ phi = evertMIO (fmap (fmap ((:>) ())) phi)

evertR :: MonadResource m => (forall t r. (MonadTrans t, MonadResource (t m)) => Stream (Of a) (t m) r -> t m (Of x r)) 
       -> FoldM m a x -- ^
evertR phi = generalEvertM phi

{-| 
 
>>> runResourceT (L.foldM (evertR_ (S.writeFile "/dev/null")) ["aaa","bbb"]) 
()

-}
evertR_ :: MonadResource m => (forall t r. (MonadTrans t, MonadResource (t m)) => Stream (Of a) (t m) r -> t m r) 
        -> FoldM m a () -- ^
evertR_ phi = evertR (fmap (fmap ((:>) ())) phi)

generalEvertM :: (Monad m) 
              => (forall r. Stream (Of a) (Stream ((->) (Feed a)) m) r -> Stream ((->) (Feed a)) m (Of b r))
              -> FoldM m a b -- ^
generalEvertM consumer = FoldM step begin done
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
          e' <- inspect (f EOF)
          case e' of
            Left (a :> ()) -> return a
            Right _ -> error continuedAfterEOF 

transvert :: (forall m r. Monad m => Stream (Of a) m r -> Stream (Of b) m r)
          -> Fold b x -- ^
          -> Fold a x 
transvert phi = \somefold -> simplify ((generalTransvertM phi) (generalize somefold))

transvertM :: Monad m 
           => (forall t r. (MonadTrans t, Monad (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
           -> FoldM m b x -- ^
           -> FoldM m a x
transvertM phi = generalTransvertM phi

transvertMIO :: MonadIO m 
             => (forall t r. (MonadTrans t, MonadIO (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
             -> FoldM m b x -- ^
             -> FoldM m a x
transvertMIO phi = generalTransvertM phi

transvertR  :: MonadResource m 
            => (forall t r. (MonadTrans t, MonadResource (t m)) => Stream (Of a) (t m) r -> Stream (Of b) (t m) r)
            -> FoldM m b x -- ^
            -> FoldM m a x
transvertR phi = generalTransvertM phi

data Pair a b = Pair !a !b

data StreamStateM m a b = PristineM (Stream (Sum (Of b) ((->) (Feed a))) m ())
                        | WaitingM  (Feed a -> Stream (Sum (Of b) ((->) (Feed a))) m ())

generalTransvertM :: Monad m 
                  => (forall r. Stream (Of a) (Stream ((->) (Feed a)) m) r -> Stream (Of b) (Stream ((->) (Feed a)) m) r) -- ^
                  -> FoldM m b x 
                  -> FoldM m a x
generalTransvertM transducer (FoldM innerstep innerbegin innerdone) = FoldM step begin done
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

