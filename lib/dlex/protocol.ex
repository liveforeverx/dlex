defmodule Dlex.Protocol do
  @moduledoc false

  alias GRPC.Stub
  alias Dlex.{Error, Type, Query}
  alias Dlex.Api.TxnContext
  alias Dlex.Api.Dgraph.Stub, as: ApiStub

  use DBConnection

  require Logger

  defstruct [:channel, :connected, :opts, :txn_context, :json, txn_aborted?: false]

  @impl true
  def connect(opts) do
    host = Keyword.fetch!(opts, :hostname)
    port = Keyword.fetch!(opts, :port)
    json_lib = Keyword.fetch!(opts, :json_library)

    case gen_stub_options(opts) do
      {:ok, stub_opts} ->
        case Stub.connect("#{host}:#{port}", stub_opts) do
          {:ok, channel} -> {:ok, %__MODULE__{channel: channel, json: json_lib, opts: opts}}
          {:error, reason} -> {:error, %Error{action: :connect, reason: reason}}
        end

      {:error, error} ->
        {:error, error}
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
  def ping(state) do
    {:ok, state}
  end

  @impl true
  def checkout(state) do
    {:ok, state}
  end

  @impl true
  def checkin(state) do
    {:ok, state}
  end

  @impl true
  def disconnect(_error, _state) do
    :ok
  end

  ## Transaction API

  @impl true
  def handle_begin(_opts, state),
    do: {:ok, nil, %{state | txn_context: TxnContext.new(), txn_aborted?: false}}

  @impl true
  def handle_rollback(_opts, state), do: finish_txn(state, :rollback)

  @impl true
  def handle_commit(_opts, state), do: finish_txn(state, :commit)

  defp finish_txn(%{txn_aborted?: true} = state, txn_result) do
    {:error, %Error{action: txn_result, reason: :aborted}, state}
  end

  defp finish_txn(%{channel: channel, txn_context: txn_context} = state, txn_result) do
    state = %{state | txn_context: nil}

    case ApiStub.commit_or_abort(channel, %{txn_context | aborted: txn_result != :commit}) do
      {:ok, txn} ->
        {:ok, txn, state}

      {:error, reason} ->
        {state_on_error(reason), %Error{action: txn_result, reason: reason}, state}
    end
  end

  ## Query API

  @impl true
  def handle_prepare(query, _opts, %{json: json_lib, txn_context: txn_context} = state) do
    {:ok, %{query | json: json_lib, txn_context: txn_context}, state}
  end

  @impl true
  def handle_execute(%Query{} = query, request, _opts, %{channel: channel, opts: opts} = state) do
    timeout = Keyword.fetch!(opts, :timeout)

    case Type.execute(channel, query, request, timeout: timeout) do
      {:ok, result} ->
        {:ok, query, result, check_txn(state, result)}

      {:error, reason} ->
        error = %Error{action: :execute, reason: reason}
        {state_on_error(reason), error, check_abort(state, reason)}
    end
  end

  defp check_txn(state, result) do
    case result do
      %{txn: %TxnContext{} = txn_context} -> merge_txn(state, txn_context)
      %{context: %TxnContext{} = txn_context} -> merge_txn(state, txn_context)
      _ -> state
    end
  end

  defp check_abort(state, %GRPC.RPCError{status: 10}), do: %{state | txn_aborted?: true}
  defp check_abort(state, _error), do: state

  defp merge_txn(%{txn_context: nil} = state, _), do: state

  defp merge_txn(%{txn_context: %TxnContext{} = txn_context} = state, new_txn_context) do
    %{start_ts: start_ts, keys: keys, preds: preds} = txn_context
    %{start_ts: new_start_ts, keys: new_keys, preds: new_preds} = new_txn_context
    start_ts = if start_ts == 0, do: new_start_ts, else: start_ts
    keys = keys ++ new_keys
    preds = preds ++ new_preds
    %{state | txn_context: %{txn_context | start_ts: start_ts, keys: keys, preds: preds}}
  end

  @impl true
  def handle_close(_query, _opts, state) do
    {:ok, nil, state}
  end

  @impl true
  def handle_status(_opts, state) do
    {:idle, state}
  end

  ## Stream API

  @impl true
  def handle_declare(query, _params, _opts, state) do
    {:ok, query, nil, state}
  end

  @impl true
  def handle_fetch(_query, _cursor, _opts, state) do
    {:halt, nil, state}
  end

  @impl true
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, nil, state}
  end

  ## handle other messages

  def handle_info({:gun_up, _pid, _protocol}, state) do
    Logger.debug("dlex received gun_up")
    {:ok, %__MODULE__{state | connected: true}}
  end

  def handle_info({:gun_down, _pid, _protocol, _level, _, _}, state) do
    Logger.debug("dlex received gun_down")
    {:ok, %__MODULE__{state | connected: false}}
  end

  def handle_info(msg, state) do
    Logger.warn(fn -> ["dix received unexpected message: ", inspect(msg)] end)
    {:ok, state}
  end

  defp state_on_error(%GRPC.RPCError{message: ":noproc"}), do: :disconnect
  defp state_on_error(%GRPC.RPCError{message: ":shutdown" <> _}), do: :disconnect
  defp state_on_error(_), do: :error
end
