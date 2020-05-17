defmodule Dlex.Type.Query do
  @moduledoc false

  alias Dlex.{Adapter, Query, Utils}
  alias Dlex.Api.{Request, Response, TxnContext}

  @behaviour Dlex.Type

  @impl true
  def execute(adapter, channel, request, json_lib, opts) do
    Adapter.query(adapter, channel, request, json_lib, opts)
  end

  @impl true
  def describe(query, _opts), do: query

  @impl true
  def encode(%Query{statement: statement}, vars, opts) do
    Request.new(
      query: statement,
      vars: Utils.encode_vars(vars),
      read_only: Keyword.get(opts, :read_only, false),
      best_effort: Keyword.get(opts, :best_effort, false)
    )
  end

  @impl true
  def decode(%{json: json_lib}, %Response{json: json, txn: %TxnContext{aborted: false} = _txn}, _) do
    with json when is_binary(json) <- json, do: json_lib.decode!(json)
  end
end
