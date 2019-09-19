defmodule Dlex.NodeTest do
  use ExUnit.Case

  alias Dlex.User

  setup_all do
    {:ok, pid} = Dlex.start_link(pool_size: 4)
    %{pid: pid}
  end

  describe "schema generation" do
    test "basic" do
      assert "type.user" == User.__schema__(:source)
      assert :string == User.__schema__(:type, :name)
      assert :integer == User.__schema__(:type, :age)
      assert [:name, :age, :friends] == User.__schema__(:fields)
    end

    test "alter" do
      assert %{ 
              "schema" => [
                 %{
                   "index" => true,
                   "predicate" => "user.name",
                   "tokenizer" => ["term"],
                   "type" => "string"
                 },
                 %{"predicate" => "user.age", "type" => "int"},
                 %{"predicate" => "user.friends", "type" => "uid"}
              ],
              "types" => [
                %{
                  "fields" => [
                    %{"name" => "user.friends", "type" => "uid"},
                    %{"name" => "user.age", "type" => "integer"},
                    %{"name" => "user.name", "type" => "string"}
                  ],
                  "name" => "type.user"
                }
              ]
            } == User.__schema__(:alter)
    end

    test "transformation callbacks" do
      assert "user.name" == User.__schema__(:field, :name)
      assert {:name, :string} == User.__schema__(:field, "user.name")
    end
  end
end
