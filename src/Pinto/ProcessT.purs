module Pinto.ProcessT
  ( Timeout(..)
  , receive
  , receiveWithTimeout
  , spawn
  , spawnLink
  , unsafeEvalProcess
  , unsafeExecProcess
  , unsafeRunProcess
  , module ReExports
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple, fst, snd)
import Effect (Effect)
import Effect.Class (class MonadEffect, liftEffect)
import Erl.Kernel.Time (milliseconds)
import Erl.Process (Process)
import Erl.Process.Raw as Raw
import Foreign (unsafeToForeign)
import Pinto.ProcessT.Internal.Types (class MonadProcessHandled, class MonadProcessTrans, initialise, parseForeign, run)
import Pinto.ProcessT.Internal.Types (class MonadProcessHandled, class MonadProcessTrans, ProcessM, ProcessTM) as ReExports
import Type.Prelude (Proxy(..))
import Unsafe.Coerce (unsafeCoerce)

-- Can only be lifted through `IdentityT` due to the `MonadProcessHandled m parsedMsg` constraint
receive
  :: forall m mState appMsg parsedMsg
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => MonadEffect m
  => m parsedMsg
receive = do
  mParsedMsg <- parseForeign =<< liftEffect Raw.receive
  case mParsedMsg of
    Nothing ->
      receive
    Just parsed ->
      pure parsed

data PrivateProcessTTimeoutMsg
  = PrivateProcessTTimeoutMsg__
  | ThereToGetRidOfUnreachableWarning

data Timeout = Timeout

derive instance Eq Timeout
derive instance Ord Timeout
instance Show Timeout where
  show Timeout = "Timeout"

receiveWithTimeout
  :: forall m mState appMsg parsedMsg
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => MonadEffect m
  => Milliseconds
  -> m (Either Timeout parsedMsg)
receiveWithTimeout ms@(Milliseconds msNum) = do
  (Milliseconds startTime) <- liftEffect milliseconds
  rawMsg <- liftEffect $ Raw.receiveWithTimeout ms PrivateProcessTTimeoutMsg__
  case rawMsg of
    PrivateProcessTTimeoutMsg__ ->
      pure $ Left Timeout
    _ -> do
      mParsed <- parseForeign $ unsafeToForeign rawMsg
      case mParsed of
        Nothing -> do
          (Milliseconds ignoredAtTime) <- liftEffect milliseconds
          let newTimeout = msNum - (ignoredAtTime - startTime)
          if newTimeout > 0.0 then
            receiveWithTimeout (Milliseconds newTimeout)
          else
            pure $ Left Timeout
        Just parsed ->
          pure $ Right parsed

unsafeEvalProcess
  :: forall m mState appMsg parsedMsg a
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => m a
  -> Effect a
unsafeEvalProcess mpt =
  fst <$> unsafeRunProcess mpt

unsafeExecProcess
  :: forall m mState appMsg parsedMsg
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => m appMsg
  -> Effect mState
unsafeExecProcess mpt =
  snd <$> unsafeRunProcess mpt

unsafeRunProcess
  :: forall m mState appMsg parsedMsg a
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => m a
  -> Effect (Tuple a mState)
unsafeRunProcess mpt =
  run mpt =<< initialise (Proxy :: Proxy m)

spawn
  :: forall m mState appMsg parsedMsg
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => MonadEffect m
  => m Unit
  -> Effect (Process appMsg)
spawn = unsafeCoerce <<< Raw.spawn <<< unsafeEvalProcess

spawnLink
  :: forall m mState appMsg parsedMsg
   . MonadProcessHandled m parsedMsg
  => MonadProcessTrans m mState appMsg parsedMsg
  => MonadEffect m
  => m Unit
  -> Effect (Process appMsg)
spawnLink = unsafeCoerce <<< Raw.spawnLink <<< unsafeEvalProcess

