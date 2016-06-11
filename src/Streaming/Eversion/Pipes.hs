{-# LANGUAGE RankNTypes #-}

-- | http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html
module Streaming.Eversion.Pipes (
) where

import           Data.Functor.Identity

import           Control.Foldl (Fold(..),FoldM(..))
import qualified Control.Foldl as Foldl

import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Free
import qualified Control.Monad.Trans.Free as TF
import qualified Control.Monad.Morph
import           Control.Comonad

import           Streaming(Of(..))
import qualified Streaming 
import qualified Streaming.Prelude
import           Streaming.Eversion
import qualified Streaming.Eversion as E
import           Pipes
import           Pipes.Prelude

