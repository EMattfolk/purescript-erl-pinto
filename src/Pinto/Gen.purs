-- | Module roughly representing interactions with the 'gen_server'
-- | See also 'gen_server' in the OTP docs
module Pinto.Gen ( startLink
                 , buildStartLink
                 , StartLinkBuilder(..)
                 , defaultStartLink
                 , stop
                 , CallResult(..)
                 , CastResult(..)
                 , call
                 , doCall
                 , cast
                 , doCast
                 , defaultHandleInfo
                 , TerminateReason(..)
                 , whereIs
                 , emitter
                 , monitor
                 , ExitMessage(..)
                 )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Erl.Atom (atom)
import Erl.Data.Tuple (tuple2, tuple3)
import Erl.ModuleName (NativeModuleName(..))
import Erl.Process.Raw (Pid)
import Foreign (Foreign, unsafeToForeign)
import Pinto (ServerName(..), StartLinkResult)
import Pinto.MessageRouting as MR
import Pinto.Monitor as Monitor
import Pinto.Sup (foreignToSlr)

data ExitMessage = Exit Pid Foreign

foreign import callImpl :: forall response state name. name -> (state -> (CallResult response state)) -> Effect response
foreign import doCallImpl :: forall response state name. name -> (state -> Effect (CallResult response state)) -> Effect response
foreign import castImpl :: forall state name. name -> (state -> (CastResult state)) -> Effect Unit
foreign import doCastImpl :: forall state name. name -> (state -> Effect (CastResult state)) -> Effect Unit
foreign import stopImpl :: forall name. name -> Effect Unit
foreign import startLinkImpl :: forall name state msg. name -> Effect state -> StartLinkBuilder state msg -> Effect Foreign
foreign import emitterImpl :: forall msg serverName. serverName -> Effect (msg -> Effect Unit)
foreign import whereIsImpl :: forall name. name -> (Pid -> Maybe Pid) -> (Maybe Pid) -> Effect (Maybe Pid)
foreign import logWarning :: forall obj. String -> obj -> Effect Unit

-- These imports are just so we don't get warnings
foreign import code_change :: forall a. a -> a -> a -> a
foreign import handle_call :: forall a. a -> a -> a -> a
foreign import handle_cast :: forall a. a -> a -> a -> a
foreign import handle_info :: forall a. a -> a -> a
foreign import init :: forall a. a -> a
foreign import terminate :: forall a. a -> a -> a
foreign import start_from_spec :: forall a. a -> a

nativeName :: forall state msg. ServerName state msg -> Foreign
nativeName (Local name) = unsafeToForeign $ name
nativeName (Global name) = unsafeToForeign $ tuple2 (atom "global") name
nativeName (Via (NativeModuleName m) name) = unsafeToForeign $ tuple3 (atom "via") m name

data TerminateReason
  = Normal
  | Shutdown
  | ShutdownWithCustom Foreign
  | Custom Foreign


-- | Gets the emitter for this gen server
-- | this  is an  effectful function into which messages of the right type can be passed into handle_info
emitter :: forall state msg. ServerName state msg -> Effect (msg -> Effect Unit)
emitter serverName = emitterImpl (nativeName serverName)

-- | Gets the pid of this gen server (if running)
whereIs :: forall state msg. ServerName state msg -> Effect (Maybe Pid)
whereIs serverName = whereIsImpl (nativeName serverName) Just Nothing

-- | Short cut for monitoring a gen server via Pinto.Monitor
monitor :: forall state msg. ServerName state msg -> (Monitor.MonitorMsg -> Effect Unit) -> Effect Unit -> Effect (Maybe (MR.RouterRef Monitor.MonitorRef))
monitor name cb alreadyDown = do
  maybePid <- whereIs name
  case maybePid of
    Nothing -> do
      _ <- alreadyDown
      pure Nothing
    Just pid -> 
      Just <$> Monitor.monitor pid cb

-- | A typed record containing all the optional extras for configuring a genserver
type StartLinkBuilder state msg = { 

    -- | A callback to be invoked when the gen server receives an arbitrary message
    handleInfo :: msg -> state -> Effect (CastResult state)

    -- | A callback to be invoked when this gen server terminates
  , terminate :: Maybe  (TerminateReason -> state -> Effect Unit)
  
    -- | When set to Nothing, exits will not be trapped (the default)
    -- | When there is a mapper provided for ExitMessage, trap_exits will be true
  , trapExit :: Maybe (ExitMessage -> msg)
  }
      
-- | Starts a typed gen-server proxy with the supplied ServerName, with the state being the result of the supplied effect
-- | This sets up the most basic gen server without a terminate handler, handle_info handler or any means of trapping exits
-- |
-- | ```purescript
-- | serverName :: ServerName State Unit
-- | serverName = ServerName "some_uuid"
-- |
-- | startLink :: Effect StartLinkResult
-- | startLink = Gen.startLink serverName init
-- |
-- | init :: Effect State
-- | init = pure {}
-- | ```
-- | See also: gen_server:start_link in the OTP docs (roughly)
startLink :: forall state msg. ServerName state msg -> Effect state -> Effect StartLinkResult
startLink name eInit = buildStartLink name eInit $ defaultStartLink


-- | Starts a typed gen-server proxy with the supplied ServerName, with the state being the result of the supplied effect
-- | This takes in a builder of optional values which can be overriden (See: StartLinkBuilder)
-- |
-- | ```purescript
-- | serverName :: ServerName State Msg
-- | serverName = ServerName "some_uuid"
-- |
-- | startLink :: Effect StartLinkResult
-- | startLink = Gen.startLink serverName init $ Gen.defaultStartLink { handleInfo: myHandleInfo }
-- |
-- | init :: Effect State
-- | init = pure {}
-- | 
-- | handleInfo :: Msg -> State -> Effect (CastResult State)
-- | handleInfo msg state = pure $ CastNoReply state
-- | ```
-- | See also: gen_server:start_link in the OTP docs (roughly)
buildStartLink :: forall state msg. ServerName state msg -> Effect state -> StartLinkBuilder state msg-> Effect StartLinkResult
buildStartLink (Local name) eInit builder = foreignToSlr <$> startLinkImpl (tuple2 (atom "local") name) eInit builder
buildStartLink (Global name) eInit builder  = foreignToSlr <$> startLinkImpl (tuple2 (atom "global") name) eInit builder
buildStartLink (Via (NativeModuleName m) name) eInit builder = foreignToSlr <$> startLinkImpl (tuple3 (atom "via") m name) eInit builder

-- | Creates the default start link options for a gen server
-- | These can be replaced  by modifying the record
defaultStartLink :: forall state msg. StartLinkBuilder state msg
defaultStartLink = {
    handleInfo : defaultHandleInfo
  , terminate : Nothing
  , trapExit : Nothing
    }


data CallResult response state = CallReply response state | CallReplyHibernate response state | CallStop response state
data CastResult state = CastNoReply state | CastNoReplyHibernate state | CastStop state | CastStopReason TerminateReason state

-- | A default implementation of handleInfo that just ignores any messages received
-- | A  warning will be printed if messages are received
defaultHandleInfo :: forall state msg. msg -> state -> Effect (CastResult state)
defaultHandleInfo msg state = do
  logWarning "Gen server received message, consider looking at startLinkBuilder and supplying a handleInfo function" { msg, state }
  pure $ CastNoReply state


-- | Defines a "pure" "call" that performs an interaction on the state held by the gen server, but with no other side effects
-- | Directly returns the result of the callback provided
-- | ```purescript
-- |
-- | doSomething :: Effect Unit
-- | doSomething = Gen.call serverName \state -> CallReply unit (modifyState state)
-- | ```
-- | See also handle_call and gen_server:call in the OTP docs
call :: forall response state msg. ServerName state msg -> (state -> (CallResult response state)) -> Effect response
call name fn = callImpl (nativeName name) fn

-- | Defines an effectful call that performs an interaction on the state held by the gen server, and perhaps side-effects
-- | Directly returns the result of the callback provided
-- | ```purescript
-- |
-- | doSomething :: Effect Unit
-- | doSomething = Gen.doCall serverName \state -> pure $ CallReply unit (modifyState state)
-- | ```
-- | See also handle_call and gen_server:call in the OTP docs
doCall :: forall response state msg. ServerName state msg -> (state -> Effect (CallResult response state)) -> Effect response
doCall name fn = doCallImpl (nativeName name) fn

-- | Defines an "pure" cast that performs an interaction on the state held by the gen server
-- | ```purescript
-- | doSomething :: Effect Unit
-- | doSomething = Gen.cast serverName \state -> CastNoReply $ modifyState state
-- | ```
-- | See also handle_cast and gen_server:cast in the OTP docs
cast :: forall state msg. ServerName state msg -> (state -> (CastResult state)) -> Effect Unit
cast name fn = castImpl (nativeName name) fn

-- | Defines an effectful cast that performs an interaction on the state held by the gen server
-- | ```purescript
-- | doSomething :: Effect Unit
-- | doSomething = Gen.cast serverName \state -> pure $ CastNoReply $ modifyState state
-- | ```
-- | See also handle_cast and gen_server:cast in the OTP docs
doCast :: forall state msg. ServerName state msg -> (state -> Effect (CastResult state)) -> Effect Unit
doCast name fn = doCastImpl (nativeName name) fn

stop :: forall state msg. ServerName state msg -> Effect Unit
stop name = stopImpl (nativeName name)
