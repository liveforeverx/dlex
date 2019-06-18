defmodule DlexTest do
  use ExUnit.Case

  setup_all do
    {:ok, pid} =
      Dlex.start_link(pool_size: 2, port: 8080, adapter: Dlex.Adapters.HTTP, timeout: 120_000)

    Dlex.alter!(pid, %{drop_all: true})
    alter = "name: string @index(term) ."
    Dlex.alter!(pid, alter)
    %{pid: pid}
  end

  @mutation_json %{
    "name" => "Alice",
    "friends" => [%{"name" => "Betty"}, %{"name" => "Mark"}]
  }

  @mutation_nquads """
  _:luke <name> "Luke Skywalker" .
  _:leia <name> "Princess Leia" .

  _:sw1 <name> "Star Wars: Episode IV - A New Hope" .
  _:sw1 <release_date> "1977-05-25" .
  _:sw1 <starring> _:luke .
  _:sw1 <starring> _:leia .
  """

  test "mutation json", %{pid: pid} do
    assert {:ok, uids} = Dlex.set(pid, @mutation_json)
    assert 3 == map_size(uids)

    assert %{
             "name" => "Alice",
             "uid" => _uid1,
             "friends" => [
               %{"name" => "Betty", "uid" => _uid2},
               %{"name" => "Mark", "uid" => _uid3}
             ]
           } = Dlex.mutate!(pid, @mutation_json, return_json: true)
  end

  test "mutation nquads", %{pid: pid} do
    assert %{"luke" => uid_luke, "leia" => uid_leia, "sw1" => uid_sw1} =
             Dlex.mutate!(pid, @mutation_nquads)

    assert %{"name" => "Luke Skywalker"} == uid_get(pid, uid_luke)
  end

  test "query with parameters", %{pid: pid} do
    json = %{"name" => "Foo", "surname" => "bar"}
    assert %{"uid" => uid} = Dlex.mutate!(pid, json, return_json: true)
    %{"uid" => ^uid, "name" => "Foo", "surname" => "bar"} = get_by_name(pid, "Foo")
  end

  test "basic transaction test", %{pid: pid} do
    Dlex.mutate!(pid, %{"name" => "client1", "balance" => 1000})
    Dlex.mutate!(pid, %{"name" => "client2", "balance" => 1000})

    tasks = for i <- [1, 2], do: Task.async(fn -> move_balance(pid, i * 100) end)
    results = for task <- tasks, do: Task.await(task)

    assert [{:ok, _}, {:error, _}] = results

    %{"balance" => balance1} = get_by_name(pid, "client1")
    %{"balance" => balance2} = get_by_name(pid, "client2")
    assert balance1 + balance2 == 2000
  end

  test "deletion", %{pid: pid} do
    assert %{"uid" => uid} = Dlex.mutate!(pid, %{"name" => "deletion_test"}, return_json: true)
    assert %{"uid" => ^uid} = get_by_name(pid, "deletion_test")
    assert Dlex.delete!(pid, %{"uid" => uid})
    assert %{"all" => []} = get_by_name(pid, "deletion_test")
  end

  test "schema modification with map", %{pid: pid} do
    surname_predicate = %{
      "index" => true,
      "predicate" => "surname",
      "tokenizer" => ["term", "fulltext"],
      "type" => "string"
    }

    Dlex.alter!(pid, %{schema: surname_predicate})
    {:ok, %{"schema" => schema}} = Dlex.query_schema(pid)
    assert surname_predicate == Enum.find(schema, &(&1["predicate"] == "surname"))
  end

  test "malformed query", %{pid: pid} do
    assert {:error, _} = Dlex.query(pid, "{ fail(func: eq(name, [])) { uid } } ")
  end

  def uid_get(conn, uid) do
    statement = "{uid_get(func: uid(#{uid})) {expand(_all_)}}"
    with %{"uid_get" => [obj]} <- Dlex.query!(conn, statement), do: obj
  end

  defp get_by_name(conn, name) do
    statement = "query all($a: string) {all(func: eq(name, $a)) {uid expand(_all_)}}"
    with %{"all" => [obj]} <- Dlex.query!(conn, statement, %{"$a" => name}), do: obj
  end

  defp move_balance(pid, sum) do
    Dlex.transaction(pid, fn conn ->
      %{"uid" => uid1, "balance" => balance1} = get_by_name(conn, "client1")
      %{"uid" => uid2, "balance" => balance2} = get_by_name(conn, "client2")

      if sum == 100, do: :timer.sleep(50)
      Dlex.mutate!(conn, %{"uid" => uid1, "balance" => balance1 - sum}, return_json: true)

      if sum == 200, do: :timer.sleep(100)
      Dlex.mutate!(conn, %{"uid" => uid2, "balance" => balance2 + sum}, return_json: true)
    end)
  end
end
