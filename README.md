# Dlex

Dlex is a gRPC based client for the [Dgraph](https://github.com/dgraph-io/dgraph) database in Elixir. It uses the [DBConnection](https://hexdocs.pm/db_connection/DBConnection.html) behaviour to support transactions and connection pooling.

Small, efficient codebase. Aims for a full dgraph support. Supports transactions (starting from dgraph version: `1.0.9`),
delete mutations and low-level parameterized queries. DSL is a planned.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dlex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jason, "~> 1.0"},
    {:dlex, "~> 0.1.0"}
  ]
end
```

## Usage example

```elixir
{:ok, conn} = Dlex.start_link(name: :example) # default try to connect `localhost:9080` by default
Dlex.alter!(conn, %{drop_all: true})
{:ok, _} = Dlex.alter(conn, "name: string @index(term) .")
{:ok, %{"uid" => uid}} = Dlex.mutate(conn, %{
  "name" => "Alice",
  "friends" => [%{"name" => "Betty"}, %{"name" => "Mark"}]
}, return_json: true) # return the same json with uids
Dlex.mutate(conn, ~s|_:foo <name> "Bar" .|) # or in nquads format
by_name = "query by_name($name: string) {by_name(func: eq(name, $name)) {uid expand(_all_)}}"
Dlex.query(conn, by_name, %{"$name" => "Betty"})
Dlex.delete(conn, %{"uid" => uid}) # delete Alice node
```

## Developers guide

### By updating api.proto

#### Install development dependencies

1. Install `protoc`(cpp) [here](https://github.com/google/protobuf/blob/master/src/README.md) or `brew install protobuf` on MacOS.
2. Install protoc plugin `protoc-gen-elixir` for Elixir . NOTE: You have to make sure `protoc-gen-elixir`(this name is important) is in your PATH.

```bash
mix escript.install hex protobuf
```

#### By updating [api.proto](https://github.com/dgraph-io/dgo/blob/master/protos/api.proto), generate Elixir code

3. Generate Elixir code using protoc

```bash
protoc --elixir_out=plugins=grpc:. lib/api.proto
```

4. Files `lib/api.pb.ex` will be generated

5. Rename `lib/api.pb.ex` to `lib/dix/api.ex` and add `alias Dlex.Api` to be complient with Elixir naming

## Credits

Inspired by [exdgraph](https://github.com/ospaarmann/exdgraph), but as I saw too many parts for changes or parts, which I would like to have complettly different, so that it was easier to start from scratch with goals: small codebase, small natural abstraction, efficient, less opionated, less dependencies.

So you can choose freely, which pool implementation to use (poolboy or db_connection intern pool implementation),
which json adapter to use. Less dependencies.

It seems for me more natural to have API names more or less matching to actual query names.

For example `Dlex.mutate()` instead of `ExDgraph.set_map` for json-based mutations. Actually `Dlex.mutate` infers
type (json or nquads) from passed data to a function.

## License

   Copyright 2018 Dmitry Russ

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
