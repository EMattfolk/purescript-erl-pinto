-module(pinto@foreign).

-export([ isRegisteredImpl/1
        , alreadyStartedImpl/1
        ]).

isRegisteredImpl(ServerName) ->
  fun() ->
      case ServerName of
        {via, Module, Name} ->
          Module:whereis_name(Name);
        {global, Name} ->
          global:whereis_name(Name);
        {local, Name} ->
          whereis(Name)
      end =/= undefined
  end.

alreadyStartedImpl(Left) ->
  fun() ->
    case Left of
      %% deliberately partialfunction - we want to crash otherwise
      {already_started, Pid} -> Pid
    end
  end.
