module Pinto.ProcessT.Internal.Types where

import Prelude

import Control.Monad.Identity.Trans (IdentityT(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class (class MonadEffect)
import Erl.Process (class HasReceive, class HasSelf, ProcessM, self, unsafeRunProcessM)
import Erl.Process.Raw as Raw
import Foreign (Foreign)
import Prim.TypeError as TE
import Type.Prelude (class TypeEquals, Proxy(..))
import Unsafe.Coerce (unsafeCoerce)

newtype ProcessTM :: Type -> Type -> Type -> Type
newtype ProcessTM userMsg handledMsg a = ProcessTM (Effect a)
derive newtype instance Functor (ProcessTM userMsg inMsg)
derive newtype instance Apply (ProcessTM userMsg inMsg)
derive newtype instance Applicative (ProcessTM userMsg inMsg)
derive newtype instance Bind (ProcessTM userMsg inMsg)
derive newtype instance Monad (ProcessTM userMsg inMsg)
derive newtype instance MonadEffect (ProcessTM userMsg inMsg)

unsafeRunProcessTM :: forall a b c. ProcessTM a b c -> Effect c
unsafeRunProcessTM (ProcessTM c) = c

instance HasSelf (ProcessTM userMsg handledMsg) userMsg where
  self = ProcessTM $ unsafeRunProcessM self

-- Only works if ProcessTM is the top of the stack being run, i.e. there is no stack!
-- (or the stack just consists of IdentityT)
instance TypeEquals userMsg handledMsg => HasReceive (ProcessTM userMsg handledMsg) userMsg userMsg where
  receive = ProcessTM Raw.receive
  receiveWithTimeout t d = ProcessTM $ Raw.receiveWithTimeout t d

class MonadProcessTrans :: (Type -> Type) -> Type -> Type -> Type -> Constraint
class MonadProcessTrans m mState appMsg outMsg | m -> mState appMsg outMsg where
  parseForeign :: Foreign -> m (Maybe outMsg)
  run :: forall a. m a -> mState -> Effect (Tuple a mState)
  initialise :: Proxy m -> Effect mState

instance MonadProcessTrans (ProcessTM appMsg handledMsg) Unit appMsg appMsg where
  parseForeign = pure <<< Just <<< unsafeCoerce
  run pm _ = do
    res <- unsafeRunProcessTM pm
    pure $ Tuple res unit
  initialise _ = pure unit

instance MonadProcessTrans m mState appMsg outMsg => MonadProcessTrans (IdentityT m) mState appMsg outMsg where
  parseForeign = IdentityT <<< parseForeign
  run (IdentityT m) = run m
  initialise _ = initialise (Proxy :: Proxy m)


class MonadProcessHandled :: (Type -> Type) -> Type -> Constraint
class MonadProcessHandled m handledMsg

instance TypeEquals topMsg handledMsg => MonadProcessHandled (ProcessTM appMsg handledMsg) topMsg
else instance TE.Fail
  (TE.Above
    (TE.Above (TE.Text "Usage of old type, please upgrade from") (TE.Beside (TE.Text "  ") (TE.Quote (ProcessM appMsg))))
    (TE.Above (TE.Text "to the new type") (TE.Beside (TE.Text "  ") (TE.Quote (ProcessTM appMsg topMsg))))
  ) => MonadProcessHandled (ProcessM appMsg) topMsg
else instance MonadProcessHandled m handledMsg => MonadProcessHandled (stack m) handledMsg
