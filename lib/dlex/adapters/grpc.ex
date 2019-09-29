defmodule Dlex.Adapters.GRPC do
  use Dlex.Adapter

  alias GRPC.Stub
  alias Dlex.Api.Dgraph.Stub, as: ApiStub
  alias Dlex.Api.Check
  alias Dlex.Error

  require Logger

  @impl true
  def connect(host, port, opts \\ []) do
    case gen_stub_options(opts) do
      {:ok, stub_opts} -> Stub.connect("#{host}:#{port}", stub_opts)
      {:error, error} -> {:error, error}
    end
  end

  defp gen_stub_options(opts) do
    adapter_opts = %{http2_opts: %{keepalive: opts[:keepalive]}}
    stub_opts = [adapter_opts: adapter_opts]

    case gen_ssl_config(opts) do
      {:ok, nil} -> {:ok, stub_opts}
      {:ok, ssl_config} -> Keyword.put(stub_opts, :cred, GRPC.Credential.new(ssl: ssl_config))
      {:error, error} -> {:error, error}
    end
  end

  defp gen_ssl_config(opts) do
    case opts[:cacertfile] do
      nil ->
        {:ok, nil}

      cacertfile ->
        with {:ok, tls_config} <- check_tls(opts) do
          ssl_config = [{:cacertfile, cacertfile} | tls_config]
          ssl_config = for {key, value} <- ssl_config, do: {key, to_charlist(value)}
          {:ok, ssl_config}
        end
    end
  end

  defp check_tls(opts) do
    case {opts[:certfile], opts[:keyfile]} do
      {nil, nil} -> {:ok, []}
      {_, nil} -> {:error, %Error{action: :connect, reason: {:not_provided, :keyfile}}}
      {nil, _} -> {:error, %Error{action: :connect, reason: {:not_provided, :certfile}}}
      {certfile, keyfile} -> {:ok, [certfile: certfile, keyfile: keyfile]}
    end
  end

  @impl true
  def disconnect(channel) do
    case Stub.disconnect(channel) do
      {:ok, _} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @impl true
  def ping(channel) do
    # check if the server is up and wait 5s seconds before disconnect
    case ApiStub.check_version(channel, Check.new(), timeout: 5_000) do
      {:ok, _} -> {:ok, channel}
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  @impl true
  def alter(channel, request, _json_lib, opts) do
    ApiStub.alter(channel, request, opts)
  end

  @impl true
  def mutate(channel, request, _json_lib, opts) do
    ApiStub.query(channel, request, opts)
  end

  @impl true
  def query(channel, request, _json_lib, opts) do
    ApiStub.query(channel, request, opts)
  end

  @impl true
  def commit_or_abort(channel, transaction, _json_lib, opts) do
    ApiStub.commit_or_abort(channel, transaction, opts)
  end
end
