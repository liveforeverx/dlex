defmodule DlexTest do
  use ExUnit.Case

  alias Dlex.TestHelper

  setup_all do
    # Setup our server
    {:ok, pid} = Dlex.start_link([{:pool_size, 2} | TestHelper.opts()])
    Dlex.alter!(pid, %{drop_all: true})

    schema = """
      type Client {
        name
        email
        balance
      }

      type CastMember {
        name
        surname
      }

      type Film {
        name
        release_date
        starring: [CastMember]
      }

      release_date: string .
      starring: [uid] .
      email: string @index(term, hash) .
      name: string @index(term) .
      surname: string @index(term) .
      balance: float .
    """

    Dlex.alter!(pid, schema)
    %{pid: pid}
  end

  @mutation_json %{
    "name" => "Alice",
    "friends" => [%{"name" => "Betty"}, %{"name" => "Mark"}]
  }

  @mutation_nquads """
  _:luke <name> "Luke Skywalker" .
  _:luke <dgraph.type> "CastMember" .
  _:leia <name> "Princess Leia" .
  _:leia <dgraph.type> "CastMember" .

  _:sw1 <name> "Star Wars: Episode IV - A New Hope" .
  _:sw1 <release_date> "1977-05-25" .
  _:sw1 <starring> _:luke .
  _:sw1 <starring> _:leia .
  _:sw1 <dgraph.type> "Film" .
  """

  test "mutation json", %{pid: pid} do
    assert {:ok, %{uids: uids}} = Dlex.set(pid, @mutation_json)
    assert 3 == map_size(uids)

    assert %{json: %{
             "name" => "Alice",
             "uid" => _uid1,
             "friends" => [
               %{"name" => "Betty", "uid" => _uid2},
               %{"name" => "Mark", "uid" => _uid3}
             ]
           }} = Dlex.mutate!(pid, @mutation_json, return_json: true)
  end

  test "mutation nquads", %{pid: pid} do
    assert %{uids: %{"luke" => uid_luke, "leia" => uid_leia, "sw1" => uid_sw1}} = Dlex.mutate!(pid, @mutation_nquads)
    assert %{"name" => "Luke Skywalker"} == uid_get(pid, uid_luke)
  end

  test "query with parameters", %{pid: pid} do
    json = %{"name" => "Foo", "surname" => "bar", "dgraph.type" => "CastMember"}
    assert %{json: %{"uid" => uid}} = Dlex.mutate!(pid, json, return_json: true)
    %{"uid" => ^uid, "name" => "Foo", "surname" => "bar"} = get_by_name(pid, "Foo")
  end

  test "basic transaction test", %{pid: pid} do
    Dlex.mutate!(pid, %{"dgraph.type" => "Client", "name" => "client1", "balance" => 1000})
    Dlex.mutate!(pid, %{"dgraph.type" => "Client", "name" => "client2", "balance" => 1000})

    tasks = for i <- [1, 2], do: Task.async(fn -> move_balance(pid, i * 100) end)
    results = for task <- tasks, do: Task.await(task)

    assert [
             {:ok, _},
             {:error,
              %Dlex.Error{
                action: :commit,
                reason: %{message: "Transaction has been aborted. Please retry"}
              }}
           ] = results

    %{"balance" => balance1} = get_by_name(pid, "client1")
    %{"balance" => balance2} = get_by_name(pid, "client2")
    assert balance1 + balance2 == 2000
  end

  test "deletion", %{pid: pid} do
    assert %{json: %{"uid" => uid}} =
             Dlex.mutate!(pid, %{"name" => "deletion_test", "dgraph.type" => "CastMember"},
               return_json: true
             )

    assert %{"uid" => ^uid} = get_by_name(pid, "deletion_test")
    assert Dlex.delete!(pid, %{"uid" => uid}, return_json: true)
    assert %{"all" => []} = get_by_name(pid, "deletion_test")
  end

  test "schema modification with map", %{pid: pid} do
    surname_predicate = %{
      "index" => true,
      "predicate" => "surname",
      "tokenizer" => ["term", "fulltext"],
      "type" => "string"
    }

    Dlex.alter!(pid, [surname_predicate])
    {:ok, %{"schema" => schema}} = Dlex.query_schema(pid)
    assert surname_predicate == Enum.find(schema, &(&1["predicate"] == "surname"))
  end

  test "malformed query", %{pid: pid} do
    assert {:error, error} = Dlex.query(pid, "{ fail(func: eq(name, [])) { uid } } ")
    assert String.contains?(error.reason.message, "Empty Argument")
  end

  describe "upsert" do
    setup [:upsert_schema]

    test "basic", %{pid: pid} do

      # insert new node
      resp = Dlex.mutate!(pid, %{
        "name" => "upsert_test",
        "email" => "foo@bar",
        "dgraph.type" => "Client"
      })

      # grab the uid to test the rest of the mutations with
      new_uid = Map.values(resp.uids) |> Enum.at(0)
      assert new_uid && new_uid !== ""

      # assert existing node uid used, :json key is missing when return_json: false used
      query = ~s|{ q(func: eq(email, "foo@bar")) { v as uid } }|
      resp1 = Dlex.mutate!(pid, %{query: query}, ~s|uid(v) <email> "foo@bar_changed" .|, return_json: false)
      assert %{"email" => "foo@bar_changed"} = get_by_name(pid, "upsert_test")
      assert !Map.has_key?(resp1, :json)
      assert resp1.uids === %{}
      assert resp1.queries === %{"q" => [%{"uid" => new_uid}]}

      # assert existing node uid used, :json === %{} when return_json: true and nquad mutation
      query = ~s|{ q(func: eq(email, "foo@bar_changed")) { v as uid } }|
      resp2 = Dlex.mutate!(pid, %{query: query}, ~s|uid(v) <email> "foo@bar_changed2" .|, return_json: true)
      assert %{"email" => "foo@bar_changed2"} = get_by_name(pid, "upsert_test")
      assert resp2.json === %{}
      assert resp2.uids === %{}
      assert resp2.queries === %{"q" => [%{"uid" => new_uid}]}

      # assert existing node used when email already exists, :json has data in it, :queries is empty when `var` used
      query = ~s|{ v as var(func: eq(email, "foo@bar_changed2")) }|
      mutation_json = %{"uid" => "uid(v)", "email" => "foo@bar_changed3"}
      resp3 = Dlex.mutate!(pid, %{query: query}, mutation_json, return_json: true)
      assert %{"email" => "foo@bar_changed3"} = get_by_name(pid, "upsert_test")
      assert resp3.json === %{"uid" => "uid(v)", "email" => "foo@bar_changed3"}
      assert resp3.uids === %{}
      assert resp3.queries === %{}

    end

    test "conditions", %{pid: pid} do
      Dlex.mutate!(pid, %{
        "name" => "upsert_test_2",
        "email" => "foo@baz",
        "dgraph.type" => "Client"
      })

      query = ~s|{ v as var(func: eq(email, "foo@baz")) }|
      mutation_json = %{"uid" => "uid(v)", "email" => "foo@baz_changed"}

      condition = ~s|@if(eq(len(v), 2))|
      Dlex.mutate!(pid, %{query: query, condition: condition}, mutation_json, return_json: true)
      assert %{"email" => "foo@baz"} = get_by_name(pid, "upsert_test_2")

      condition = ~s|@if(eq(len(v), 1))|
      Dlex.mutate!(pid, %{query: query, condition: condition}, mutation_json, return_json: true)
      assert %{"email" => "foo@baz_changed"} = get_by_name(pid, "upsert_test_2")
    end
  end

  defp upsert_schema(%{pid: pid} = context) do
    predicate = %{
      "upsert" => true,
      "index" => true,
      "predicate" => "email",
      "tokenizer" => ["exact"],
      "type" => "string"
    }

    Dlex.alter!(pid, [predicate])
    context
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
