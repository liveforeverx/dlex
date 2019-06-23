defmodule Dlex.Query do
  @moduledoc false

  @type t :: %__MODULE__{
          type: Diex.Type.Alter | Diex.Type.Mutation | Diex.Type.Query,
          sub_type: atom,
          statement: map | String.t(),
          condition: String.t(),
          parameters: any,
          txn_context: Diex.Api.TxnContext.t(),
          json: atom,
          request: any
        }

  defstruct [:type, :sub_type, :statement, :condition, :parameters, :json, :request, :txn_context]

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
