defmodule Dlex.Type do
  @moduledoc """
  Behaviour for handling requests of specific types, which abstracts different queries, but
  additionally combines it with execution logic, what should make it easier to extend on other
  request types.
  """

  @callback describe(Dlex.Query.t(), Keyword.t()) :: Dlex.Query.t()
  @callback encode(Dlex.Query.t(), map, Keyword.t()) :: struct
  @callback decode(Dlex.Query.t(), term, Keyword.t()) :: term

  @callback execute(GRPC.Channel.t(), request :: term) ::
              {:ok, struct} | {:error, GRPC.RPCError.t()}

  @doc """
  Execute request
  """
  @spec execute(GRPC.Channel.t(), Dlex.Query.t(), struct) ::
          {:ok, struct} | {:error, GRPC.RPCError.t()}
  def execute(channel, %{type: type} = _query, request),
    do: type.execute(channel, request)

  @doc """
  Describe query according to options
  """
  @spec describe(Dlex.Query.t(), Keyword.t()) :: struct
  def describe(%{type: type} = query, opts), do: type.describe(query, opts)

  @doc """
  Encode query according to options
  """
  @spec encode(Dlex.Query.t(), map, Keyword.t()) :: struct
  def encode(%{type: type} = query, parameters, opts), do: type.encode(query, parameters, opts)

  @doc """
  Decode query according to options
  """
  @spec decode(Dlex.Query.t(), struct, Keyword.t()) :: term
  def decode(%{type: type} = query, result, opts), do: type.decode(query, result, opts)
end
