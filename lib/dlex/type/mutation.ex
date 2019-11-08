defmodule Dlex.Type.Mutation do
  @moduledoc false

  alias Dlex.{Adapter, Query, Utils}
  alias Dlex.Api.{Response, Mutation, Request}

  @behaviour Dlex.Type

  @impl true
  def execute(adapter, channel, request, json_lib, opts) do
    Adapter.mutate(adapter, channel, request, json_lib, opts)
  end

  @impl true
  def describe(%Query{statement: statement} = query, opts) do
    statement = if opts[:return_json], do: Utils.add_blank_ids(statement), else: statement
    %Query{query | statement: statement}
  end

  @impl true
  def encode(%{json: json} = query, _parameters, _opts) do
    %Query{sub_type: sub_type, statement: statement, condition: condition, query: query, txn_context: txn} = query

    {commit, start_ts} = transaction_opts(txn)
    mutation_type = infer_type(statement)
    statement = format(mutation_type, statement, json)
    mutation_key = mutation_key(mutation_type, sub_type)

    mutation_opts = [{mutation_key, statement}, {:commit_now, commit}]

    mutation_opts = if is_binary(condition) do
      mutation_opts ++ [{:cond, condition}]
    else
      mutation_opts
    end

    mut = Mutation.new(mutation_opts)
    Request.new([
      commit_now: commit,
      start_ts: start_ts,
      mutations: [mut],
      query: query
    ])
  end

  defp transaction_opts(%{start_ts: start_ts}), do: {false, start_ts}
  defp transaction_opts(nil), do: {true, 0}

  defp infer_type(%{}), do: :json
  defp infer_type([%{} | _]), do: :json
  defp infer_type(_), do: :nquads

  defp format(:nquads, statement, _), do: statement
  defp format(:json, statement, json_lib), do: json_lib.encode!(statement)

  defp mutation_key(:json, nil), do: :set_json
  defp mutation_key(:cond, nil), do: :cond
  defp mutation_key(:nquads, nil), do: :set_nquads
  defp mutation_key(:json, :deletion), do: :delete_json
  defp mutation_key(:nquads, :deletion), do: :del_nquads

  @impl true
  def decode(%Query{statement: statement} = _query, %Response{uids: uids} = _result, opts) do
    if opts[:return_json], do: Utils.replace_ids(statement, uids), else: uids
  end
end
