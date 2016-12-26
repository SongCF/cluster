defmodule ClusterTest do
  use ExUnit.Case
  doctest Cluster
  require Record

  Record.defrecord :procx, [:id, :pid, :node]
  Record.defrecord :proc1, [:id, :pid, :node, :attr1]
  Record.defrecord :procw, [:id, :pid]

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "all node" do
    assert [node()] == :cluster.all_node()
  end

  test "node role be leader" do
    assert :leader == :cluster.node_role(node())
  end

  test "init table right" do
    assert :leader == :cluster.node_role(node())
    :procx = :cluster.init_table(:procx, [:id, :pid, :node])
    procx1 = procx(id: 1, pid: self(), node: node())
    :cluster.set_val(:procx, procx1)
    assert {:ok, self()} == :cluster.get_proc(:procx, 1)
    :cluster.del_proc(:procx, 1)
    assert {:error, :not_found} == :cluster.get_proc(:procx, 1)
  end

  test "table scheme must have pattern [_,pid,node|_]" do
    {:error, :scheme_error} = :cluster.init_table(:procw, [:id, :pid])
    :proc1 = :cluster.init_table(:proc1, [:id, :pid, :node, :attr1])
  end

end
