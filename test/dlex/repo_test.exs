defmodule Dlex.RepoTest do
  use ExUnit.Case

  alias Ecto.Changeset
  alias Dlex.{Geo, TestHelper, TestRepo, User}

  setup_all do
    {:ok, pid} = TestRepo.start_link(TestHelper.opts())
    %{pid: pid}
  end

  describe "schema operations" do
    setup do
      TestRepo.register(User)
      TestRepo.alter_schema()
      :ok
    end

    test "basic crud operations" do
      user = %User{name: "Alice", age: 25}
      assert {:ok, %User{uid: uid}} = TestRepo.set(user)
      assert uid != nil
      assert {:ok, %User{uid: ^uid, name: "Alice", age: 25}} = TestRepo.get(uid)
      assert %User{uid: ^uid, name: "Alice", age: 25} = TestRepo.get!(uid)

      assert {:ok, %{"uid_get" => [%User{uid: ^uid, name: "Alice", age: 25}]}} =
               TestRepo.all("{uid_get(func: uid(#{uid})) {uid dgraph.type expand(_all_)}}")

      assert {:ok, %{"uid_get" => [%{"uid" => _, "user.age" => 25, "user.name" => "Alice"}]}} =
               TestRepo.all("{uid_get(func: uid(#{uid})) {uid expand(_all_)}}")

      invalid_changeset = Ecto.Changeset.cast(%User{}, %{name: 20, age: "Bernard"}, [:name, :age])
      assert {:error, %Ecto.Changeset{valid?: false}} = TestRepo.set(invalid_changeset)

      valid_changeset = Ecto.Changeset.cast(%User{}, %{name: "Bernard", age: 20}, [:name, :age])
      assert {:ok, %{uid: uid2}} = TestRepo.set(valid_changeset)

      assert uid != nil
      assert uid2 != nil
      assert {:ok, %{queries: %{}, uids: %{}}} = TestRepo.delete(%{uid: uid})
      assert {:ok, nil} = TestRepo.get(uid)
      assert %{queries: %{}, uids: %{}} = TestRepo.delete!(%{uid: uid2})
      assert {:ok, nil} = TestRepo.get(uid2)
    end

    test "using custom types" do
      changes = %{name: "John", age: 30, location: %{lat: 15.5, lon: 10.2}}
      changeset = Changeset.cast(%User{}, changes, [:name, :age, :location])

      assert {:ok, %User{uid: uid, location: %Geo{lat: 15.5, lon: 10.2}}} =
               TestRepo.mutate(changeset)

      assert {:ok, %User{location: %Geo{lat: 15.5, lon: 10.2}}} = TestRepo.get(uid)
    end
  end
end
