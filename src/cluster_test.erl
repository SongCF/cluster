-module(cluster_test).
-compile([export_all]).

-record(table1, {id, pid, node}).
-record(table2, {id, pid, node}).

start_master() ->
    table1 = cluster:init_table(table1, record_info(fields, table1)),
    table2 = cluster:init_table(table2, record_info(fields, table2)),
    ok.

start_slave() ->
    ok.
