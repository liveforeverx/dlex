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
      assert {:ok, %{uid: _uid}} = TestRepo.set(valid_changeset)
    end

    test "setting datetime field in Changeset" do
      now = DateTime.utc_now()
      changeset = Ecto.Changeset.cast(%User{}, %{name: "TimeTraveler", age: 20, modified: now}, [:name, :age, :modified])
      assert {:ok, %{uid: uid}} = TestRepo.set(changeset)

      assert {:ok, %User{name: "TimeTraveler", age: 20, modified: now}} = TestRepo.get(uid)
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
