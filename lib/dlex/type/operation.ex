defmodule Dlex.Type.Operation do
  @moduledoc false
  alias Dlex.Query
  alias Dlex.Api.{Operation, Payload}
  alias Dlex.Api.Dgraph.Stub, as: ApiStub

  @behaviour Dlex.Type

  @impl true
  def execute(channel, request, opts), do: ApiStub.alter(channel, request, opts)

  @impl true
  def describe(%{statement: statement} = query, _opts) do
    %{query | statement: build(statement)}
  end

  defp build(statement) when is_binary(statement), do: defaults(%{schema: statement})
  defp build(statement) when is_map(statement), do: defaults(statement)

  def defaults(map) do
    map
    |> Map.put_new(:schema, "")
    |> Map.put_new(:drop_attr, "")
    |> Map.put_new(:drop_all, false)
  end

  @impl true
  def encode(%Query{statement: statement}, _, _) do
    %{drop_all: drop_all, schema: schema, drop_attr: drop_attr} = statement
    Operation.new(drop_all: drop_all, schema: schema, drop_attr: drop_attr)
  end

  @impl true
  def decode(_, %Payload{Data: data}, _) do
    data
  end
end
