defmodule Dlex.Type.Query do
  @moduledoc false

  alias Dlex.Query
  alias Dlex.Api.{Request, Response, TxnContext}
  alias Dlex.Api.Dgraph.Stub, as: ApiStub

  @behaviour Dlex.Type

  @impl true
  def execute(channel, request), do: ApiStub.query(channel, request)

  @impl true
  def describe(query, _opts), do: query

  @impl true
  def encode(%Query{statement: statement}, parameters, _) do
    Request.new(query: statement, vars: parameters)
  end

  @impl true
  def decode(_, %Response{json: "{}", schema: schema}, _) do
    Enum.map(schema, &Map.delete(&1, :__struct__))
  end

  def decode(_, %Response{json: json, txn: %TxnContext{aborted: false} = _txn}, _) do
    Query.json_adapter().decode!(json)
  end
end
