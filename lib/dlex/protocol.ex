defmodule Dlex.Protocol do
  @moduledoc false

  alias Dlex.{Error, Type, Query}
  alias Dlex.Api.TxnContext

  use DBConnection

  require Logger

  defstruct [:adapter, :channel, :connected, :json, :opts, :txn_context, txn_aborted?: false]

  @impl true
  def connect(opts) do
    host = Keyword.fetch!(opts, :hostname)
    port = Keyword.fetch!(opts, :port)
    adapter = Keyword.fetch!(opts, :adapter)
    json_lib = Keyword.fetch!(opts, :json_library)

    case adapter.connect("#{host}:#{port}", opts) do
      {:ok, channel} ->
        state = %__MODULE__{adapter: adapter, json: json_lib, channel: channel, opts: opts}
        {:ok, state}

      {:error, reason} ->
        {:error, %Error{action: :connect, reason: reason}}
    end
  end

  # Implement calls for DBConnection Protocol

  @impl true
  def ping(%{adapter: adapter, channel: channel} = state) do
    case adapter.ping(channel) do
      :ok -> {:ok, state}
      {:disconnect, reason} -> {:disconnect, reason, state}
    end
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
  def disconnect(error, %{adapter: adapter, channel: channel} = state) do
    adapter.disconnect(channel)
  end

  ## Transaction API

  @impl true
  def handle_begin(_opts, state) do
    {:ok, nil, %{state | txn_context: TxnContext.new(), txn_aborted?: false}}
  end

  @impl true
  def handle_rollback(_opts, state), do: finish_txn(state, :rollback)

  @impl true
  def handle_commit(_opts, state), do: finish_txn(state, :commit)

  defp finish_txn(%{txn_aborted?: true} = state, txn_result) do
    {:error, %Error{action: txn_result, reason: :aborted}, state}
  end

  defp finish_txn(state, txn_result) do
    %{adapter: adapter, channel: channel, txn_context: txn_context, opts: opts} = state
    state = %{state | txn_context: nil}

    case adapter.commit_or_abort(channel, %{txn_context | aborted: txn_result != :commit}, opts) do
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
  def handle_execute(%Query{} = query, request, _opts, state) do
    %{adapter: adapter, channel: channel, opts: opts} = state
    timeout = Keyword.fetch!(opts, :timeout)

    case Type.execute(channel, query, request, timeout: timeout, adapter: adapter) do
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
  def handle_close(query, _opts, state) do
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
  def handle_fetch(query, _cursor, _opts, state) do
    {:halt, nil, state}
  end

  @impl true
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, nil, state}
  end

  defp state_on_error(%GRPC.RPCError{message: ":noproc"}), do: :disconnect
  defp state_on_error(%GRPC.RPCError{message: ":shutdown" <> _}), do: :disconnect
  defp state_on_error(_), do: :error
end
