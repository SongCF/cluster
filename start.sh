rebar compile; erl -name 'master1@127.0.0.1' -config scripts/master_demo.config -pa ebin/ deps/*/ebin/ -eval 'cluster_boot:start(cluster_test,start_master).'

rebar compile; erl -name 'slave1@127.0.0.1' -config scripts/slave_demo.config -pa ebin/ deps/*/ebin/ -eval 'cluster_boot:start(cluster_test,start_slave).'