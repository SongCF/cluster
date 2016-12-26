# 介绍

-------------------------------------------------------------------------------

一个基于mnesia的集群管理系统。

1. 每个节点可以指定自己的角色类型，可以方便的按角色查询对应的节点。
2. master作为特殊的类型，支持多master备份。
3. 每张需要同步的Mnesia表都由master创建，其他节点可以配置需要同步到本地的表。

# 应用配置

-------------------------------------------------------------------------------

+ master: 可以有多个master
+ leader: 多master时需要有一个leader来干活，其他master闲置.
+ 其他: 用户自定义节点类型.

有两个配置demo
```
ls -l config
-rw-r--r--  1  staff  159  4 28 14:10 master_demo.config
-rw-r--r--  1  staff  159  4 28 14:10 slave_demo.config
```

# 设计

-------------------------------------------------------------------------------

## 核心规则

1. 每个新加入集群的节点都需要给所有除了自己的的master发送nodeup。
2. 任意master收到node_up消息，都尝试将新节点加入到cluster_node表，以避免nodeup过程中主master挂掉的问题(事务操作)。
3. 任意master加入节点时都尝试monitor现在除了自己的所有cluster_node(直接从mnesia中读取)。

## master选举

需要有个简单的计算自己是不是主master，当主master挂掉后，其他master自动接管。
实现leader竞选，通过事务控制检查，集群中是否已经存在master，没有则提高自己为master.

1. 新master加入节点时执行。
2. 收到其他master挂掉的消息后执行。

同一时间只有一个leader，有些逻辑只能leader可以做.

## 测试

```
# 启动一个master
rebar compile; erl -name 'master1@127.0.0.1'  -config config/master_demo.config -pa ebin/ -s cluster_test start_master

# 启动一个另一个master
rebar compile; erl -name 'master2@127.0.0.1'  -config config/master_demo.config -pa ebin/ -s cluster_test start_master

# 再启动一个一个Master
rebar compile; erl -name 'master3@127.0.0.1'  -config config/master_demo.config -pa ebin/ -s cluster_test start_master

# 启动一个player节点
rebar compile; erl -name 'slave1@127.0.0.1'  -config config/slave_demo.config -pa ebin/ -s cluster_test start_player

```

全部启动后可以kill掉任何一个master或者slave来体验一下。

节点上可以通过mnesia:info(), ets:tab2list(cluster) 等查看数据.

```
mnesia:info().

ets:tab2list(cluster).
```

