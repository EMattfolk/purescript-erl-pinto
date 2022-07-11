module Pinto.ProcessT.MonitorT
  ( MonitorInfo
  , MonitorMap
  , MonitorMsg(..)
  , MonitorObject
  , MonitorRef
  , MonitorT
  , MonitorType
  , monitor
  , monitor'
  , spawnLinkMonitor
  , spawnMonitor
  )
  where

import Prelude

import Control.Monad.State.Trans (StateT, get, modify_, put, runStateT)
import Control.Monad.Trans.Class (class MonadTrans, lift)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class (class MonadEffect, liftEffect)
import Erl.Data.Map (Map)
import Erl.Data.Map as Map
import Erl.Process (Process, toPid)
import Erl.Process.Raw as Raw
import Foreign (Foreign)
import Partial.Unsafe (unsafeCrashWith)
import Pinto.ProcessT (spawn, spawnLink)
import Pinto.ProcessT.Internal.Types (class MonadProcessTrans, initialise, parseForeign, run)
import Type.Prelude (Proxy(..))

newtype MonitorT monitorMsg m a = MonitorT (StateT (MonitorMap monitorMsg) m a)

derive newtype instance Functor m => Functor (MonitorT monitorMsg m)
derive newtype instance Monad m => Apply (MonitorT monitorMsg m)
derive newtype instance Monad m => Applicative (MonitorT monitorMsg m)
derive newtype instance Monad m => Bind (MonitorT monitorMsg m)
derive newtype instance Monad m => Monad (MonitorT monitorMsg m)

derive newtype instance MonadEffect m => MonadEffect (MonitorT monitorMsg m)
derive newtype instance MonadTrans (MonitorT monitorMsg)

type MonitorObject
  = Foreign

-- | The 'reason' for the monitor being invoked, if this needs unpacking
-- | then FFI will need to be written
type MonitorInfo
  = Foreign

-- | The type of monitor this message is being sent on behalf
data MonitorType
  = Process
  | Port

data MonitorMsg
  = Down MonitorRef MonitorType MonitorObject MonitorInfo


-- | Reference to a monitor, used to stop the monitor once it is started
foreign import data MonitorRef :: Type

type MonitorMap msg = Map MonitorRef (MonitorMsg -> msg)

foreign import monitorImpl :: Raw.Pid -> Effect MonitorRef
foreign import parseMonitorMsg :: Foreign -> Maybe MonitorMsg

instance
  (MonadProcessTrans m innerState appMsg, Monad m) =>
  MonadProcessTrans (MonitorT monitorMsg m) (Tuple (MonitorMap monitorMsg) innerState) (Either monitorMsg appMsg) where
  parseForeign fgn = do
      case parseMonitorMsg fgn of
        Just down@(Down ref _ _ _) -> MonitorT $ do
          mtState <- get
          case Map.lookup ref mtState of
            Nothing ->
              unsafeCrashWith "Down from unknown monitor"
            Just mapper -> do
              put $ Map.delete ref mtState
              pure $ Left $ mapper down
        Nothing -> do
          lift $ Right <$> parseForeign fgn
  run (MonitorT mt) (Tuple mtState is) = do
      (Tuple (Tuple res newMtState) newIs) <- run (runStateT mt mtState) is
      pure $ Tuple res $ Tuple newMtState newIs
  initialise _ = do
    innerState <- initialise (Proxy :: Proxy m)
    pure $ Tuple Map.empty innerState

monitor ::
  forall monitorMsg m.
  MonadEffect m =>
  Raw.Pid -> (MonitorMsg -> monitorMsg) -> MonitorT monitorMsg m MonitorRef
monitor pid mapper = do
    MonitorT do
      ref <- liftEffect $ monitorImpl pid
      modify_ \mm -> Map.insert ref mapper mm
      pure ref

monitor' ::
  forall monitorMsg m msg.
  MonadEffect m =>
  Process msg -> (MonitorMsg -> monitorMsg) -> MonitorT monitorMsg m MonitorRef
monitor' pid mapper = do
    MonitorT do
      ref <- liftEffect $ monitorImpl (toPid pid)
      modify_ \mm -> Map.insert ref mapper mm
      pure ref

spawnMonitor
  :: forall m mState msg m2 monitorMsg
   . MonadProcessTrans m mState msg
  => MonadEffect m
  => MonadEffect m2
  => m Unit -> (MonitorMsg -> monitorMsg) -> MonitorT monitorMsg m2 (Process msg)
spawnMonitor = doSpawnMonitor spawn

spawnLinkMonitor
  :: forall m mState msg m2 monitorMsg
   . MonadProcessTrans m mState msg
  => MonadEffect m
  => MonadEffect m2
  => m Unit -> (MonitorMsg -> monitorMsg) -> MonitorT monitorMsg m2 (Process msg)
spawnLinkMonitor = doSpawnMonitor spawnLink


doSpawnMonitor
  :: forall m msg m2 monitorMsg
   . MonadEffect m2
  => (m -> Effect (Process msg)) -> m -> (MonitorMsg -> monitorMsg) -> MonitorT monitorMsg m2 (Process msg)
doSpawnMonitor spawner m mapper = do
  pid <- liftEffect $ spawner m
  void $ monitor' pid mapper
  pure pid
