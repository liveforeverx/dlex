# Dlex

[![Hex pm](http://img.shields.io/hexpm/v/dlex.svg?style=flat)](https://hex.pm/packages/dlex)
[![CircleCI](https://circleci.com/gh/liveforeverx/dlex.svg?style=svg)](https://circleci.com/gh/liveforeverx/dlex)

Dlex is a gRPC based client for the [Dgraph](https://github.com/dgraph-io/dgraph) database in Elixir.
It uses the [DBConnection](https://hexdocs.pm/db_connection/DBConnection.html) behaviour to support transactions and connection pooling.

Small, efficient codebase. Aims for a full Dgraph support. Supports transactions (starting from Dgraph version: `1.0.9`), delete mutations and low-level parameterized queries. DSL is planned.

Now supports the new dgraph 1.1.x [Type System](https://docs.dgraph.io/master/query-language/#type-system).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dlex` to your list of dependencies in `mix.exs`:

Preferred and more performant option is to use `grpc`:

```elixir
def deps do
  [
    {:jason, "~> 1.0"},
    {:dlex, "~> 0.5.0"}
  ]
end
```

`http` transport:

```elixir
def deps do
  [
    {:jason, "~> 1.0"},
    {:castore, "~> 0.1.0", optional: true},
    {:mint, github: "ericmj/mint", branch: "master"},
    {:dlex, "~> 0.5.0"}
  ]
end
```

## Usage examples

```elixir
# try to connect to `localhost:9080` by default
{:ok, conn} = Dlex.start_link(name: :example)

# clear any data in the graph
Dlex.alter!(conn, %{drop_all: true})

# add a term index on then `name` predicate
{:ok, _} = Dlex.alter(conn, "name: string @index(term) .")

# add nodes, returning the uids in the response
mut = %{
  "name" => "Alice",
  "friends" => [%{"name" => "Betty"}, %{"name" => "Mark"}]
}
{:ok, %{json: %{"uid" => uid}}} = Dlex.mutate(conn, mut, return_json: true)

# use the nquad format for mutations instead if preferred
Dlex.mutate(conn, ~s|_:foo <name> "Bar" .|)

# basic query that shows Betty
by_name = "query by_name($name: string) {by_name(func: eq(name, $name)) {uid expand(_all_)}}"
Dlex.query(conn, by_name, %{"$name" => "Betty"})

# delete the Alice node
Dlex.delete(conn, %{"uid" => uid})
```

### Alter schema

Modification of schema supported with string and map form (which is returned by `query_schema`):

```elixir
Dlex.alter(conn, "name: string @index(term, fulltext, trigram) @lang .")

# equivalent map form
Dlex.alter(conn, [
  %{
    "predicate" => "name",
    "type" => "string",
    "index" => true,
    "lang" => true,
    "tokenizer" => ["term", "fulltext", "trigram"]
  }
])
```

### Usage in Phoenix App

#### Enable database connection and add to supervision tree

The example below uses `Grepo` instead of `Repo` to enable use of dgraph along with another database. If dgraph is the only database required for the project, then the changes can be made directly in `repo.ex`:

```elixir
defmodule App.Grepo do
  use Dlex.Repo,
    otp_app: :app,
    modules: [App.Courses.Course]
end
```

In application.ex:

```elixir
def start(_type, _args) do
  # List all child processes to be supervised
  children = [
    # Start the Ecto repository
    App.Repo,
    # Start the endpoint when the application starts
    AppWeb.Endpoint,
    # Starts a worker by calling: App.Worker.start_link(arg)
    # {App.Worker, arg},
    App.Grepo,
  ]
  ...
end
```

#### Define a model

```elixir
defmodule App.Courses.Course do
  use Dlex.Node
  @derive {Phoenix.Param, key: :uid}

  import Ecto.Changeset

  schema "courses" do
    field(:title, :string, index: ["term"])
    field(:description, :string)
    field(:guidelines, :string)
    field(:status, :integer)
    field(:has_learning_path, :uid)
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :title,
      :description,
      :guidelines,
      :status,
      :has_learning_path
    ])
end

```

#### Update the schema

```bash
$ iex -S mix

# To view the schema:
iex> Grepo.snapshot()

# To execute the update (alter_schema uses snapshot() by default and can be omitted)
iex> Grepo.snapshot() |> Grepo.alter_schema()

```

#### Define the context

This follows the same pattern as a regular phoenix app context with the above setup:

```elixir
defmodule App.Courses do
  @moduledoc """
  The Courses context.
  """

  alias App.Grepo
  alias App.Courses.Course

  ...

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking course changes.

  ## Examples

      iex> change_course(course)
      %Ecto.Changeset{source: %Course{}}

  """
  def change_course(%Course{} = course) do
    Course.changeset(course, %{})
  end

  @doc """
  Creates a course.

  ## Examples

      iex> create_course(%{field: value})
      {:ok, %Course{}}

      iex> create_course(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_course(attrs \\ %{}) do
    %Course{}
    |> Course.changeset(attrs)
    |> Grepo.set()
  end

  ...

  def course_statuses() do
    [
      {"Published", 1},
      {"Unpublished", 2}
    ]
  end

  ...
end
```

#### Define the controller

```elixir
defmodule AppWeb.Admin.CourseController do
  use AppWeb, :controller

  alias App.Grepo
  alias App.Courses
  alias App.Courses.Course

  def index(conn, _params) do
    query = "{courses(func: type(courses)) {uid expand(_all_)}}"
    {:ok, %{"courses" => courses}} = Grepo.all(query)
    render(conn, "index.html", courses: courses)
  end

  def show(conn, %{"id" => id}) do
    course = Grepo.get!(id)
    render(conn, "show.html", course: course)
  end

  def new(conn, _params) do
    changeset = Courses.change_course(%Course{})

    render(conn, "new.html",
      changeset: changeset,
      statuses: course_statuses_for_select()
    )
  end

  def create(conn, %{"course" => course_params}) do
    case Courses.create_course(course_params) do
      {:ok, _course} ->
        render_success(
          conn,
          "Course created successfully",
          Routes.admin_course_path(conn, :index)
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          changeset: changeset,
          statuses: course_statuses_for_select()
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    course = Grepo.get!(id)
    changeset = Courses.change_course(course)

    render(conn, "edit.html",
      course: course,
      changeset: changeset,
      statuses: course_statuses_for_select()
    )
  end

  def update(conn, %{"id" => id, "course" => course_params}) do
    course = Grepo.get!(id)

    case Courses.update_course(course, course_params) do
      {:ok, course} ->
        render_success(
          conn,
          "Course updated successfully",
          Routes.admin_course_path(conn, :show, course)
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html",
          course: course,
          changeset: changeset,
          statuses: course_statuses_for_select()
        )
    end
  end

  defp course_statuses_for_select, do: Courses.course_statuses()
end
```

## Developers guide

### Running tests

1. Install dependencies `mix deps.get`
2. Start the local dgraph server (requires Docker) `./start-server.sh`
   This starts a local server bound to ports 9090 (GRPC) and 8090 (HTTP)
3. Run `mix test`

NOTE: You may stop the server using `./stop-server.sh`

### Updating GRPC stubs based on api.proto

#### Install development dependencies

1. Install `protoc`(cpp) [here](https://github.com/google/protobuf/blob/master/src/README.md) or `brew install protobuf` on MacOS.
2. Install protoc plugin `protoc-gen-elixir` for Elixir . NOTE: You have to make sure `protoc-gen-elixir`(this name is important) is in your PATH.

```bash
mix escript.install hex protobuf
```

#### Generate Elixir code based on api.proto

3. Generate Elixir code using protoc

```bash
protoc --elixir_out=plugins=grpc:. lib/api.proto
```

4. Files `lib/api.pb.ex` will be generated

5. Rename `lib/api.pb.ex` to `lib/dlex/api.ex` and add `alias Dlex.Api` to be compliant with Elixir naming

## Credits

Inspired by [exdgraph](https://github.com/ospaarmann/exdgraph), but as I saw too many parts for changes or parts, which I would like to have completely different, so that it was easier to start from scratch with these goals: small codebase, small natural abstraction, efficient, less opinionated, less dependencies.

So you can choose freely which pool implementation to use (poolboy or db_connection intern pool implementation) or which JSON adapter to use. Fewer dependencies.

It seems for me more natural to have API names more or less matching actual query names.

For example `Dlex.mutate()` instead of `ExDgraph.set_map` for JSON-based mutations. Actually, `Dlex.mutate` infers the type (JSON or nquads) from data passed to a function.

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
