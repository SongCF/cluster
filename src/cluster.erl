-module(cluster).

-behaviour(gen_server).

%% API
-export([start_link/0,
         start/0,
         init_table/2,
         init_table/3,
         config_master/0,
         copy_table/1,
         role_list/1,
         node_role/1,
         all_node/0,
         create_table/2,
         clear/3,
         random_node/1,
         random_pid/2,
         wait_all/0,
         get_my_role/0
        ]).

-export([del_object/2]).
-export([del_proc/2]).
-export([set_val/2, get_val/2]).
-export([get_proc/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-record(cluster, {role, node}).

-record(state, {}).


%%%-------------------------------------------------------------------
%%% API
%%%-------------------------------------------------------------------

start() ->
    application:ensure_all_started(cluster).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% master调用，拷贝或者初始化指定的表.
init_table(Table, Schema) ->
    init_table(Table, Schema, set).

init_table(Table, Schema, Type) ->
    case Schema of
        [_,pid,node|_] ->
            case get_my_role() of
                leader -> create_table(Table, Schema, Type);
                _ -> copy_table(Table)
            end;
        _-> {error, scheme_error}
    end.


%% worker调用，拷贝内存表.
copy_table(Table) ->
    case mnesia:add_table_copy(Table, node(), ram_copies) of
        {aborted, {no_exists, _}} -> undefined;
        {aborted, {already_exists, _, _}} -> Table;
        {_, ok} -> Table
    end.

%% master调用，创建表.
create_table(Table, Schema) ->
    create_table(Table, Schema, set).

create_table(Table, Schema, Type) ->
    case mnesia:create_table(Table, [{attributes, Schema}, {type, Type}]) of
        {aborted, Reason} -> throw(Reason);
        {_, ok} -> Table
    end.

wait_all() ->
    {ok, Tables} = application:get_env(cluster, tables),
    mnesia:wait_for_tables([schema]++Tables, infinity).


%% 获取这个Role的所有Node
role_list(Role) ->
    [Node|| #cluster{node=Node} <- mnesia:dirty_read(cluster, Role)].

%% 根据node查询器role
node_role(Node) ->
    NodeRecord = #cluster{role = '$1', node = Node},
    case mnesia:dirty_select(cluster, [{NodeRecord, [], ['$1']}]) of
        [X] -> X;
        _ -> undefined
    end.


%% 返回集群中所有的节点
all_node() ->
    NodeRecord = #cluster{role = '$1', node = '$2'},
    mnesia:dirty_select(cluster, [{NodeRecord, [], ['$2']}]).

random_node(Role) ->
    List = cluster:role_list(Role),
    lists:nth(random:uniform(length(List)), List).

%% 设置cluster数据
set_val(Table, Val) ->
    mnesia:dirty_write(Table, Val).

%% 获取val
get_val(Table, Key) ->
    case mnesia:dirty_read(Table, Key) of
        [Data] -> {ok, Data};
        _ -> {error, not_found}
    end.

%% 删除
del_proc(Table, Key) ->
    mnesia:dirty_delete(Table, Key).

del_object(Table, Obj) ->
    mnesia:dirty_delete_object(Table, Obj).

%% 根据Key查询Table中的进程Pid.

get_proc(Table, Key) ->
    case mnesia:dirty_read(Table, Key) of
        [Data] -> {ok, element(3, Data)};
        _ -> {error, not_found}
    end.


%%%-------------------------------------------------------------------
%%% gen_server callbacks
%%%-------------------------------------------------------------------

init([]) ->
    {ok, Role} = application:get_env(cluster, role),
    DecideRole = decide_role(Role),
    set_my_role(DecideRole),
    lager:info("decide role ~p", [DecideRole]),

    {ok, MasterNodes} = config_master(),
    Tables1 = role_tables(),
    do_init(MasterNodes, DecideRole, Tables1),
    {ok, #state{}}.


handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({nodeup, Node, Role}, State) ->
    monitor_node(Node, true),
    lager:info("Node up (~p)", [Node]),
    ClusterNode = #cluster{node=Node,role=Role},
    mnesia:transaction(fun() -> mnesia:write(ClusterNode) end),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({nodemonitor, NodeList}, State) ->
    lager:info("Node Monitor (~p)", [NodeList]),
    [monitor_node(Node, true) || Node <- NodeList],
    {noreply, State};


handle_info({nodedown, Node}, State) ->
    lager:info("Node down (~p)~n", [Node]),
    %% 删除老的数据.
    node_down(node_role(Node), Node),
    case get_my_role() of
        leader -> notify:post(nodedown, Node);
        _ -> ignore
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% 实际的role，以配置Role为参数.
decide_role(master) ->
    {ok, MasterNodes} = config_master(),
    MasterNodes2 = MasterNodes -- [node()],
    %% 其他master都链接不上，说明自己是第一个启动的master。
    AmIFirstMaster =
        lists:all(fun(Node) ->
                    case net_kernel:connect_node(Node) of
                        true -> false;
                        _ -> true
                    end
                  end, MasterNodes2),
    case AmIFirstMaster of
        true -> leader;
        false -> master
    end;
decide_role(RoleCfg) ->
    RoleCfg.


%% leader的初始化，检查配置里面的表是不是被建立了，是则copy到本地，没有则建立.
do_init(_MasterNodes, leader, _) ->
    cluster = create_table(cluster,
                           record_info(fields, cluster),
                           bag),
    ClusterNode = #cluster{node=node(),role=leader},
    mnesia:transaction(fun() -> mnesia:dirty_write(ClusterNode) end),
    ok;

do_init(MasterNodes, master, Tables) ->
    do_init(MasterNodes, slave, Tables),
    NodeList = all_node() -- [node()],
    [monitor_node(Node, true) || Node <- NodeList],
    ok;

do_init(MasterNodes, _Role, Tables) ->
    {ok, _Ret} = mnesia:change_config(extra_db_nodes, MasterNodes),
    [Table = copy_table(Table) || Table <- Tables],
    ok = mnesia:wait_for_tables([schema] ++ Tables, infinity),
    %% 向master注册自己.
    MyRole = get_my_role(),
    cast_all_master({nodeup, node(), MyRole}),
    ok.


cast_all_master(Msg) ->
    {ok, MasterNodes} = config_master(),
    [gen_server:cast({cluster, Node}, Msg) || Node <- MasterNodes].

role_tables() ->
    {ok, Tables1} = application:get_env(cluster, tables),
    [cluster] ++ Tables1.

node_down(undefined, _Node) -> ok;
node_down(Role, Node) ->
    MyRole = get_my_role(),
    Info = #cluster{role=Role, node = Node},
    TransFun =
        fun() ->
                case mnesia:read(cluster, leader) of
                    [Info] ->
                        %% 只有一个人会成功
                        mnesia:delete_object(Info),
                        DelNode = #cluster{role= MyRole, node = node()},
                        mnesia:delete_object(DelNode),
                        AddNode = #cluster{node = node(), role = leader},
                        mnesia:write(AddNode),
                        set_my_role(leader);
                    Err ->
                        mnesia:abort(Err)
                end
        end,
    %% 如果是leader挂了，自己是master，那么尝试变成leader
    case {Role, MyRole} of
        {leader, master} ->
            %% 使用事务来避免争用.
            mnesia:transaction(TransFun);
        _ ->  mnesia:dirty_delete_object(Info)
    end.


%% 清除Table中所有的Node项目。
clear(TableName, Node, Attrs) ->
    Tuple = {TableName, '$1', '_', Node},
    TupleMatch = lists:foldl(fun(_X,Acc) ->
                                     erlang:append_element(Acc,'_')
                             end, Tuple,  lists:seq(0,length(Attrs)-4)),
    case catch mnesia:dirty_select(TableName, [{TupleMatch, [], ['$1']}]) of
        [] -> ignore;
        Ids when is_list(Ids) ->
            lager:info("delete node ~p ids ~p", [Node, Ids]),
            [mnesia:dirty_delete(TableName, Id) || Id <- Ids];
        {'EXIT', _Reason} ->
            lager:error("Process table ~p not exist anymore!", [TableName])
    end.

random_pid(TableName, Attrs) ->
    Tuple = {TableName, '$1', '$2', '_'},
    TupleMatch = lists:foldl(fun(_X,Acc) ->
                                     erlang:append_element(Acc,'_')
                             end, Tuple,  lists:seq(0,length(Attrs)-4)),
    PidList = mnesia:dirty_select(TableName, [{TupleMatch, [], ['$2']}]),
    No = random:uniform(length(PidList)),
    lists:nth(No, PidList).


%% 返回配置表中的master
config_master() ->
    Ret = {ok, _Masters} = application:get_env(cluster, masters),
    Ret.


set_my_role(Role)->
    application:set_env(cluster, role, Role),
    ok.

get_my_role()->
    %cluster:node_role(node()).
    {ok, MyRole} = application:get_env(cluster, role),
    MyRole.

