module Test.Main where

import Prelude

import Control.Monad.Free (Free)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Debug.Trace (spy)
import Effect (Effect)
import Effect.Unsafe (unsafePerformEffect)
import Erl.Atom (Atom, atom)
import Erl.Data.List (List)
import Erl.Process (Process(..), (!))
import Erl.Process.Raw (Pid)
import Erl.Test.EUnit (TestF, TestSet, collectTests, runTests, suite, test)
import Partial.Unsafe (unsafePartial)
import Pinto.GenServer (CallResult(..), CastResult(..), InitFn, ServerRunning(..))
import Pinto.GenServer as GS
import Pinto.Types (InstanceRef(..), NotStartedReason(..), RegistryName(..), ServerPid, StartLinkResult, crashIfNotStarted)
import Test.Assert (assert, assertEqual)
import Unsafe.Coerce (unsafeCoerce)

foreign import filterSasl :: Effect  Unit

main :: Effect Unit
main =
  let _ = unsafePerformEffect filterSasl
  in
    void $ runTests do
      genServerSuite

genServerSuite :: Free TestF Unit
genServerSuite =
  suite "Pinto genServer test" do
    testStartLinkAnonymous
    testStartLinkNamed
    testHandleInfo
    testCall



data TestState = TestState Int
derive instance eqTestState :: Eq TestState
instance showTestState :: Show TestState where
  show (TestState x) = "TestState: " <> show x

data Cont = TestCont
data Msg = TestMsg

testStartLinkAnonymous :: Free TestF Unit
testStartLinkAnonymous =
  test "Can start an anonymous GenServer" do
    slRes <- GS.startLink $ GS.mkSpec init
    let
      worked = case slRes of
        Right pid -> true
        Left reason -> false
    assert worked
    pure unit

    where
      init :: forall cont msg. InitFn TestState cont msg
      init = do
        pure $ Right $ InitOk $ TestState 0

testStartLinkNamed :: Free TestF Unit
testStartLinkNamed =
  test "Can start an anonymous GenServer" do
    slRes <- GS.startLink $ (GS.mkSpec init) { name = Just (Local (atom "foo")) }
    let
      worked = case slRes of
        Right pid -> true
        Left reason -> false
    assert worked
    pure unit

    where
      init :: forall cont msg. InitFn TestState cont msg
      init = do
        pure $ Right $ InitOk (TestState 0)

testHandleInfo :: Free TestF Unit
testHandleInfo =
  test "HandleInfo handler receives message" do
    slRes <- GS.startLink $ (GS.mkSpec init) { handleInfo = Just handleInfo }

    worked <- case slRes of
        Right pid -> do
            (unsafeCoerce pid :: Process Msg) ! TestMsg
            pure true
        Left reason ->
            pure false

    assert worked
    pure unit

    where
      init :: forall cont msg. InitFn TestState cont msg
      init = do
        pure $ Right $ InitOk $ TestState 0

      handleInfo msg (TestState x) = do
        let _ = spy "Got message" msg
        pure $ NoReply $ TestState $ x + 1


testCall :: Free TestF Unit
testCall =
  test "Can create gen_server:call handlers" do
    serverPid <- crashIfNotStarted  <$> (GS.startLink $ GS.mkSpec init)

    state <- getState (ByPid serverPid)
    assertEqual { actual: state
                , expected: TestState 7
                }
    pure unit

    where
      init :: forall cont msg. InitFn TestState cont msg
      init = do
        pure $ Right $ InitOk $ TestState 7

getState :: forall state msg. InstanceRef state msg -> Effect state
getState handle = GS.call handle
       \state -> pure $ CallReply state state
