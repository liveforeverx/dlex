defmodule Dlex.Adapter do
  @doc """
  Use `Dlex.Adapter` to set the behaviour.
  """

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Dlex.Adapter
    end
  end

  @type host :: String.t() | atom
  @type port_number :: integer()
  @type conn :: term()
  @type opts :: keyword()
  @type transaction :: %{}
  @type request :: %{}
  @type json_lib :: module()
  @type result :: %{}

  @callback connect(host, port_number, opts) :: {:ok, conn} | {:error, term}
  @callback disconnect(conn) :: :ok | {:error, term}
  @callback ping(conn) :: :ok | {:error, term}

  @callback alter(conn, request, json_lib, opts) :: {:ok, result} | {:error, term}
  @callback mutate(conn, request, json_lib, opts) :: {:ok, result} | {:error, term}
  @callback query(conn, request, json_lib, opts) :: {:ok, result} | {:error, term}
  @callback commit_or_abort(conn, transaction, json_lib, opts) ::
              {:ok, transaction} | {:error, term}

  def connect(adapter, host, port, opts), do: adapter.connect(host, port, opts)
  def disconnect(adapter, conn), do: adapter.disconnect(conn)
  def ping(adapter, conn), do: adapter.ping(conn)

  def alter(adapter, conn, request, json_lib, opts),
    do: adapter.alter(conn, request, json_lib, opts)

  def mutate(adapter, conn, request, json_lib, opts),
    do: adapter.mutate(conn, request, json_lib, opts)

  def query(adapter, conn, request, json_lib, opts),
    do: adapter.query(conn, request, json_lib, opts)

  def commit_or_abort(adapter, conn, request, json_lib, opts),
    do: adapter.commit_or_abort(conn, request, json_lib, opts)
end
