# 0.4.0

* Add support for conditions in upsert
* Add support for returning structs in Repo.all

Backwards-compatible changes:

* `Dlex.mutate(pid, query, mutation, opts)` is now `Dlex.mutate(pid, %{query: query}, mutation, opts)`,
  additionally `Dlex.mutate(pid, %{query: query, condition: condition}, mutation, opts)`
* `Repo.all` defined via `Dlex.Repo` - could return structs(if type is defined) instead of pure jsons

# 0.3.2

* Rename dgraph.type to be without prefix `type.` as it do not needed anymore

# 0.3.1

* Add http support for DGraph `1.1.0`

# 0.3.0

As dgraph has breaking API change, this version supports DGraph only in version `1.1.0`, use
dlex in version `0.2.1` for using with DGraph `1.0.X`.

* support DGraph `1.1.0` (only for `grpc` at the moment)

# 0.2.1

* add support for upcoming `upsert` functionallity (only for `grpc`)
* fix dependency missconfiguration in `v0.2.0`

# 0.2.0

* fix leaking of gun connections on timeouts
* add `transport` option, which specifies if `grpc` or `http` transport should be used
* make `grpc` dependencies optional, so you can choose based on transport the dependencies

# 0.1.3

* add support to alter table in the same format (json) as it queried. Now you can use output of
  `Dlex.query_schema` in `Dlex.alter`.

Example of usage:

```
Dlex.alter(conn, [%{
  "index" => true,
  "predicate" => "user.name",
  "tokenizer" => ["term"],
  "type" => "string"
}])
```

* add initial basic language integrated features on top of dgraph adapter:
  * add `Dlex.Node` to define schemas
  * add `Dlex.Repo` to define something like `Ecto.Repo`, but specific for Dgraph with custom API
  * `Dlex.Repo` supports `Ecto.Changeset` (and `Dlex.Node` schemas supports `Ecto.Changeset`),
  ecto is optional

Example usage:

```
defmodule User do
  use Dlex.Node

  schema "user" do
    field :name, :string, index: ["term"]
    field :age, :integer
    field :owns, :uid
  end
end

defmodule Repo do
  use Dlex.Repo, otp_app: :test, modules: [User]
end

%User{uid: uid} = Repo.mutate!(%User{name: "Alice", age: 29})
%User{name: "Alice"} = Repo.get!(uid)
```

Casting of nodes to structs happens automatically, but you need to either specify module in
`modules` or register them once after `Repo` is started with `Repo.register(User)` to be
available for `Repo`.

To get `User` schema, can be `User.__schema__(:alter)` used or `Repo.snapshot` for all fields or
or `Repo.alter_schema()` to directly migrate/alter schema for `Repo`.

`Ecto.Changeset` works with `Dlex.Node` and `Dlex.Repo`.

Example usage:

```
changeset = Ecto.Changeset.cast(%User{}, %{"name" => "Alice", "age" => 20}, [:name, :age])
Repo.mutate(changeset)
```

# 0.1.2

* add timeout on grpc calls
* ensure client reconnection works on dgraph unavailibility
* optimize json encoding/decoding, fetch json library from environment on connection start

# 0.1.1

* fix adding default options by including as supervisor

# 0.1.0

First release!
