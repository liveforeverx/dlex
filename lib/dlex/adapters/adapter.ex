defmodule Dlex.Adapter do
  @doc """
  Use `Dlex.Adapter` to set the behaviour.
  """
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Dlex.Adapter
    end
  end

  @type address :: String.t() | atom
  @type connection :: term
  @type connection_options :: keyword()
  @type request_options :: keyword()
  @type transaction :: %{}
  @type request :: %{}
  @type result :: %{}

  @callback connect(address) :: {:ok, connection} | {:error, term}
  @callback connect(address, connection_options) :: {:ok, connection} | {:error, term}
  @callback disconnect(connection) :: :ok | {:error, term}
  @callback ping(connection) :: :ok | {:error, term}

  @callback alter(connection, request, request_options) :: {:ok, result} | {:error, term}
  @callback mutate(connection, request, request_options) :: {:ok, result} | {:error, term}
  @callback query(connection, request, request_options) :: {:ok, result} | {:error, term}

  @callback commit_or_abort(connection, transaction, request_options) :: {:ok, transaction} | {:error, term}
end
