defmodule Dlex.Type do
  @moduledoc false

  @type request :: term
  @type json_lib :: module

  @callback describe(Dlex.Query.t(), Keyword.t()) :: Dlex.Query.t()
  @callback encode(Dlex.Query.t(), map, Keyword.t()) :: struct
  @callback decode(Dlex.Query.t(), term, Keyword.t()) :: term

  @callback execute(module(), GRPC.Channel.t(), request, json_lib, opts :: Keyword.t()) ::
              {:ok, struct} | {:error, GRPC.RPCError.t()}

  @doc """
  Execute request
  """
  @spec execute(module(), GRPC.Channel.t(), Dlex.Query.t(), struct, Keyword.t()) ::
          {:ok, struct} | {:error, GRPC.RPCError.t()}
  def execute(adapter, channel, %{type: type, json: json_lib} = _query, request, opts),
    do: type.execute(adapter, channel, request, json_lib, opts)

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
