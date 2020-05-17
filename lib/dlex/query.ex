defmodule Dlex.Query do
  @moduledoc false

  @type mutation :: %{
          optional(:cond) => String.t(),
          optional(:set) => map | iodata,
          optional(:delete) => map | iodata
        }

  @type t :: %__MODULE__{
          type: Dlex.Type.Alter | Dlex.Type.Mutation | Dlex.Type.Query,
          query: String.t(),
          statement: [mutation] | map | iodata,
          parameters: any,
          txn_context: Diex.Api.TxnContext.t(),
          json: atom,
          request: any
        }

  defstruct [:type, :query, :parameters, :statement, :json, :request, :txn_context]

  @type request :: any
  @callback request(t) :: request
end

defimpl DBConnection.Query, for: Dlex.Query do
  alias Dlex.{Query, Type}

  def parse(%Query{} = query, _), do: query
  def describe(query, opts), do: Type.describe(query, opts)
  def encode(query, parameters, opts), do: Type.encode(query, parameters, opts)
  def decode(query, result, opts), do: Type.decode(query, result, opts)
end
