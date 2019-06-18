defmodule Dlex.Type.Operation do
  @moduledoc false
  alias Dlex.Query
  alias Dlex.Api.{Operation, Payload}

  @behaviour Dlex.Type

  @impl true
  def execute(channel, request, opts) do
    adapter = opts[:adapter]
    apply(adapter, :alter, [channel, request, Keyword.delete(opts, :adapter)])
  end

  @impl true
  def describe(%{statement: statement} = query, _opts) do
    %{query | statement: build(statement)}
  end

  defp build(statement) when is_binary(statement), do: defaults(%{schema: statement})
  defp build(statement) when is_map(statement), do: defaults(statement)

  def defaults(map) do
    map
    |> Map.put_new(:schema, "")
    |> Map.put_new(:drop_attr, "")
    |> Map.put_new(:drop_all, false)
  end

  @impl true
  def encode(%Query{statement: statement}, _, _) do
    %{drop_all: drop_all, schema: schema, drop_attr: drop_attr} = statement
    Operation.new(drop_all: drop_all, schema: encode_schema(schema), drop_attr: drop_attr)
  end

  @impl true
  def decode(_, %Payload{Data: data}, _) do
    data
  end

  def encode_schema(string) when is_binary(string), do: string

  def encode_schema(schemas) when is_list(schemas) or is_map(schemas) do
    schemas |> List.wrap() |> Enum.map_join("\n", &transform_schema/1)
  end

  defp transform_schema(%{"predicate" => predicate, "type" => type} = entry) do
    tokenizers = Map.get(entry, "tokenizer", [])
    keys = :maps.without(["predicate", "type", "tokenizer"], entry)
    opts = Enum.map_join(keys, " ", &render_key(&1, tokenizers))
    "#{predicate}: #{type} #{opts} ."
  end

  def render_key({"index", true}, tokenizers), do: "@index(#{Enum.join(tokenizers, ", ")})"
  def render_key({key, true}, _), do: "@#{key}"
end
