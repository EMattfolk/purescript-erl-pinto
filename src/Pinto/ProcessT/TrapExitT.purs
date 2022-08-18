module Pinto.ProcessT.TrapExitT
  ( TrapExitT
  , module TypeExports
  ) where

import Prelude

import Control.Monad.Identity.Trans (IdentityT, runIdentityT)
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Class (class MonadEffect)
import Erl.Process (class HasSelf, self)
import Erl.Process.Raw (setProcessFlagTrapExit)
import Pinto.ProcessT.Internal.Types (class MonadProcessTrans, initialise, parseForeign, run)
import Pinto.Types (ExitMessage(..), parseTrappedExitFFI)
import Pinto.Types (ExitMessage(..)) as TypeExports
import Type.Prelude (Proxy(..))

newtype TrapExitT :: forall k. (k -> Type) -> k -> Type
newtype TrapExitT m a = TrapExitT (IdentityT m a)

derive newtype instance Functor m => Functor (TrapExitT m)
derive newtype instance Monad m => Apply (TrapExitT m)
derive newtype instance Monad m => Applicative (TrapExitT m)
derive newtype instance Monad m => Bind (TrapExitT m)
derive newtype instance Monad m => Monad (TrapExitT m)

derive newtype instance MonadEffect m => MonadEffect (TrapExitT m)
derive newtype instance MonadTrans TrapExitT

instance (HasSelf m msg, Monad m) => HasSelf (TrapExitT m) msg where
  self = lift self

instance
  ( MonadProcessTrans m innerState appMsg innerOutMsg
  , Monad m
  ) =>
  MonadProcessTrans (TrapExitT m) innerState appMsg (Either ExitMessage innerOutMsg) where
  parseForeign fgn = TrapExitT do
    case parseTrappedExitFFI fgn Exit of
      Just exitMsg ->
        pure $ Just $ Left exitMsg
      Nothing -> do
        (map Right) <$> (lift $ parseForeign fgn)

  run (TrapExitT mt) is =
    run (runIdentityT mt) is

  initialise _ = do
    void $ setProcessFlagTrapExit true
    innerState <- initialise (Proxy :: Proxy m)
    pure $ innerState
