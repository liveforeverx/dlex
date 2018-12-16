defmodule Dlex.Type.Mutation do
  @moduledoc false

  alias Dlex.Query
  alias Dlex.Api.{Assigned, Mutation}
  alias Dlex.Api.Dgraph.Stub, as: ApiStub

  @behaviour Dlex.Type

  @impl true
  def execute(channel, request), do: ApiStub.mutate(channel, request)

  @impl true
  def describe(%Query{statement: statement} = query, opts) do
    statement = if opts[:return_json], do: add_blank_ids(statement), else: statement
    %Query{query | statement: statement}
  end

  ## Add temporary blank ids to json object
  defp add_blank_ids(statement), do: statement |> add_blank_ids(0) |> elem(0)

  defp add_blank_ids(list, counter) when is_list(list) do
    {list, counter} =
      Enum.reduce(list, {[], counter}, fn map, {acc, counter} ->
        {map, counter} = add_blank_ids(map, counter)
        {[map | acc], counter}
      end)

    {Enum.reverse(list), counter}
  end

  defp add_blank_ids(map, counter) when is_map(map) do
    map = Map.update(map, "uid", "_:#{counter}", & &1)

    Enum.reduce(map, {%{}, counter + 1}, fn {key, value}, {map, counter} ->
      {value, counter} = add_blank_ids(value, counter)
      {Map.put(map, key, value), counter}
    end)
  end

  defp add_blank_ids(value, counter), do: {value, counter}

  @impl true
  def encode(query, _parameters, _opts) do
    %Query{sub_type: sub_type, statement: statement, txn_context: txn} = query
    {commit, start_ts} = transaction_opts(txn)
    mutation_type = infer_type(statement)
    statement = format(mutation_type, statement)
    mutation_key = mutation_key(mutation_type, sub_type)
    mutation = [{mutation_key, statement} | [start_ts: start_ts, commit_now: commit]]
    Mutation.new(mutation)
  end

  defp transaction_opts(%{start_ts: start_ts}), do: {false, start_ts}
  defp transaction_opts(nil), do: {true, 0}

  defp infer_type(%{}), do: :json
  defp infer_type([%{} | _]), do: :json
  defp infer_type(_), do: :nquads

  defp format(:nquads, statement), do: statement
  defp format(:json, statement), do: Query.json_adapter().encode!(statement)

  defp mutation_key(:json, nil), do: :set_json
  defp mutation_key(:nquads, nil), do: :set_nquads
  defp mutation_key(:json, :deletion), do: :delete_json
  defp mutation_key(:nquads, :deletion), do: :del_nquads

  @impl true
  def decode(%Query{statement: statement} = _query, %Assigned{uids: uids} = _result, opts) do
    if opts[:return_json], do: replace_ids(statement, uids), else: uids
  end

  ## Replace temporary blank ids to real ids

  defp replace_ids(json, uids) when is_list(json), do: Enum.map(json, &replace_ids(&1, uids))

  defp replace_ids(map, uids) when is_map(map),
    do: Enum.reduce(map, %{}, &replace_kv(&1, &2, uids))

  defp replace_ids(value, _uids), do: value

  defp replace_kv({"uid", "_:" <> blank_id}, map, uids), do: Map.put(map, "uid", uids[blank_id])
  defp replace_kv({key, value}, map, uids), do: Map.put(map, key, replace_ids(value, uids))
end
