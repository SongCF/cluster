%%%-------------------------------------------------------------------
%%% @author zhuoyikang <>
%%% @doc
%%% 通用节点启动
%%% @end
%%%-------------------------------------------------------------------

-module(cluster_boot).

-export([start/2]).

%% 通用节点启动.
start(Mod,F) ->
    cluster:start(),
    Mod:F(),
    ok.
