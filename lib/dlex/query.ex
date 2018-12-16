defmodule Dlex.Query do
  @moduledoc false

  @type t :: %__MODULE__{
          type: Diex.Type.Alter | Diex.Type.Mutation | Diex.Type.Query,
          sub_type: atom,
          statement: map | String.t(),
          parameters: any,
          txn_context: Diex.Api.TxnContext.t(),
          request: nil
        }

  defstruct [:type, :sub_type, :statement, :parameters, :request, :txn_context]

  @type request :: any
  @callback request(t) :: request

  @doc """
  Get json adapter
  """
  def json_adapter(), do: Application.get_env(:dlex, :json_adapter, Jason)
end

defimpl DBConnection.Query, for: Dlex.Query do
  alias Dlex.{Query, Type}

  def parse(%Query{} = query, _), do: query
  def describe(query, opts), do: Type.describe(query, opts)
  def encode(query, parameters, opts), do: Type.encode(query, parameters, opts)
  def decode(query, result, opts), do: Type.decode(query, result, opts)
end
