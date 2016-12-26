-module(cluster_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% -------------------------------------------------------------------
%% Application callbacks
%% -------------------------------------------------------------------

start(_StartType, _StartArgs) ->
    cluster_sup:start_link().

stop(_State) ->
    cluster:leader_select_leave(),
    ok.
