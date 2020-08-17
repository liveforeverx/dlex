defmodule Dlex.Repo do
  @moduledoc """
  Ecto-like repository, which allows to embed the schema

    defmodule Repo do
      use Dlex.Repo, otp_app: :my_app, modules: [User]
    end

    config :my_app, Repo,
      hostname: "localhost",
      port: 3306
  """
  alias Dlex.{Error, Node, Repo.Meta, Utils}

  @doc """

  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @name opts[:name] || __MODULE__
      @meta_name :"#{@name}.Meta"
      @otp_app opts[:otp_app]
      @modules opts[:modules] || []

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        start_opts = %{
          module: __MODULE__,
          otp_app: @otp_app,
          name: @name,
          meta_name: @meta_name,
          modules: @modules,
          opts: opts
        }

        Dlex.Repo.Sup.start_link(start_opts)
      end

      def set(node, opts \\ []), do: Dlex.Repo.set(@name, node, opts)
      def set!(node, opts \\ []), do: Dlex.Repo.set!(@name, node, opts)

      def mutate(node, opts \\ []), do: Dlex.Repo.mutate(@name, node, opts)
      def mutate!(node, opts \\ []), do: Dlex.Repo.mutate!(@name, node, opts)

      def delete(node, opts \\ []), do: Dlex.Repo.delete(@name, node, opts)
      def delete!(node, opts \\ []), do: Dlex.Repo.delete!(@name, node, opts)

      def get(uid), do: Dlex.Repo.get(@name, meta(), uid)
      def get!(uid), do: Dlex.Repo.get!(@name, meta(), uid)

      def all(query, params \\ %{}), do: Dlex.Repo.all(@name, query, params, meta())

      def meta(), do: Dlex.Repo.Meta.get(@meta_name)
      def register(modules), do: Dlex.Repo.Meta.register(@meta_name, modules)
      def snapshot(), do: Dlex.Repo.snapshot(@meta_name)
      def alter_schema(snapshot \\ snapshot()), do: Dlex.Repo.alter_schema(@name, snapshot)

      def stop(timeout \\ 5000), do: Supervisor.stop(@name, :normal, timeout)

      def drop_all(), do: Dlex.Repo.drop_all(@name)
    end
  end

  @doc false
  def child_spec(%{module: module, otp_app: otp_app, name: name, opts: opts}) do
    opts = Keyword.merge(opts, Application.get_env(otp_app, module, []))
    Dlex.child_spec([{:name, name} | opts])
  end

  @doc """
  Build or update lookup map from module list
  """
  def build_lookup_map(lookup_map \\ %{}, modules) do
    for module <- List.wrap(modules), reduce: lookup_map do
      acc ->
        case source(module) do
          nil -> acc
          source -> Map.put(acc, source, module)
        end
    end
  end

  @doc """
  Query all. It automatically tries to decode values inside of a query. To make it work, you
  need to expand the results it like this: `uid dgraph.type expand(_all_)`
  """
  def all(conn, query, params, %{lookup: lookup} = _meta \\ %{lookup: %{}}) do
    with {:ok, data} <- Dlex.query(conn, query, params), do: decode(data, lookup, false)
  end

  def set!(conn, data, opts), do: mutate!(conn, data, opts)

  @doc """
  The same as `mutate`.
  """
  def set(conn, data, opts), do: mutate(conn, data, opts)

  @doc """
  The same as `mutate/2`, but return result of sucessful operation or raises.
  """
  def mutate!(conn, data, opts) do
    case mutate(conn, data, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Mutate data.
  """
  def mutate(_conn, %{__struct__: Ecto.Changeset, valid?: false} = changeset, _opts),
    do: {:error, changeset}

  def mutate(conn, %{__struct__: Ecto.Changeset, valid?: true} = changeset, opts) do
    %{data: %{__struct__: struct} = data, changes: changes} = changeset

    with {:ok, new_data} <-
           mutate(conn, Map.merge(changes, %{__struct__: struct, uid: nil}), opts) do
      {:ok, Map.merge(data, new_data)}
    end
  end

  def mutate(conn, data, opts) do
    data_with_ids = Utils.add_blank_ids(data, :uid)

    case encode(data_with_ids) do
      {:error, error} ->
        {:error, %Error{action: :mutate, reason: error}}

      encoded_data ->
        with {:ok, %{uids: ids_map}} <- Dlex.set(conn, %{}, encoded_data, opts) do
          {:ok, Utils.replace_ids(data_with_ids, ids_map, :uid)}
        end
    end
  end

  @doc """
  Delete data.
  """
  def delete(conn, data, _opts) do
    case encode(data) do
      {:error, error} ->
        {:error, %Error{action: :mutate, reason: error}}

      encoded_data ->
        Dlex.delete(conn, encoded_data)
    end
  end

  @doc """
  The same as `delete/2`, but return result of sucessful operation or raises.
  """
  def delete!(conn, data, opts) do
    case delete(conn, data, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def encode(%{__struct__: struct} = data) do
    data
    |> Map.from_struct()
    |> Map.to_list()
    |> encode_kv(%{}, struct)
  end

  def encode(data) when is_list(data), do: encode_list(data, [])
  def encode(data), do: data

  defp encode_kv([], map, _struct), do: map
  defp encode_kv([{_key, nil} | kv], map, struct), do: encode_kv(kv, map, struct)

  defp encode_kv([{:uid, value} | kv], map, struct) do
    map = Map.merge(map, %{"uid" => value, "dgraph.type" => source(struct)})
    encode_kv(kv, map, struct)
  end

  defp encode_kv([{key, value} | kv], map, struct) do
    {field_name, type} = {field(struct, key), type(struct, key)}

    cond do
      field_name == nil ->
        encode_kv(kv, map, struct)

      Node.primitive_type?(type) ->
        map = Map.put(map, field_name, encode(value))
        encode_kv(kv, map, struct)

      true ->
        case type.dump(value) do
          {:ok, data} -> encode_kv(kv, Map.put(map, field_name, data), struct)
          :error -> {:error, {:dump_error, key, type, value}}
        end
    end
  end

  defp encode_list([], list), do: Enum.reverse(list)

  defp encode_list([value | values], list) do
    case encode(value) do
      {:error, error} -> {:error, error}
      data -> encode_list(values, [data | list])
    end
  end

  @compile {:inline, field: 2}
  def type(struct, key), do: struct.__schema__(:type, key)
  @compile {:inline, field: 2}
  def field(_struct, "uid"), do: {:uid, :string}
  def field(struct, key), do: struct.__schema__(:field, key)
  @compile {:inline, source: 1}
  def source(struct), do: struct.__schema__(:source)

  @doc """
  The same as `get/3`, but return result or raises.
  """
  def get!(conn, meta, uid) do
    case get(conn, meta, uid) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Get by uid
  """
  def get(conn, %{lookup: lookup}, uid) do
    statement = ["{uid_get(func: uid(", uid, ")) {uid dgraph.type expand(_all_)}}"]

    with {:ok, %{"uid_get" => nodes}} <- Dlex.query(conn, statement) do
      case nodes do
        [%{"uid" => _} = map] when map_size(map) <= 2 ->
          {:ok, nil}

        [map] ->
          with {:error, error} <- decode(map, lookup),
               do: {:error, %Error{action: :get, reason: error}}
      end
    end
  end

  @doc """
  Decode resulting map to a structure.
  """
  def decode(map, lookup, strict? \\ true) do
    with %{} = map <- do_decode(map, lookup, strict?), do: {:ok, map}
  end

  defp do_decode(map, lookup, strict?) when is_map(map) and is_map(lookup) do
    with %{"dgraph.type" => [type_string]} <- map,
         type when type != nil <- Map.get(lookup, type_string) do
      do_decode_map(map, type, lookup, strict?)
    else
      _ ->
        cond do
          strict? -> {:error, {:untyped, map}}
          true -> do_decode_untyped_map(map, lookup)
        end
    end
  end

  defp do_decode(list, lookup, strict?) when is_list(list) and is_map(lookup) do
    for value <- list, do: do_decode(value, lookup, strict?)
  end

  defp do_decode(value, _lookup, _strict?), do: value

  defp do_decode_map(map, type, lookup, strict?) when is_map(map) and is_atom(type) do
    Enum.reduce_while(map, type.__struct__(), fn {key, value}, struct ->
      case do_decode_field(struct, field(type, key), value, lookup, strict?) do
        {:error, error} -> {:halt, {:error, error}}
        updated_struct -> {:cont, updated_struct}
      end
    end)
  end

  defp do_decode_untyped_map(map, lookup) do
    Enum.reduce_while(map, %{}, fn {key, values}, acc ->
      case do_decode(values, lookup, false) do
        {:error, error} -> {:halt, {:error, error}}
        values -> {:cont, Map.put(acc, key, values)}
      end
    end)
  end

  defp do_decode_field(struct, {field_name, field_type}, value, lookup, strict?) do
    case Ecto.Type.load(field_type, value) do
      {:ok, loaded_value} ->
        if Node.primitive_type?(field_type) do
          Map.put(struct, field_name, do_decode(loaded_value, lookup, strict?))
        else
          Map.put(struct, field_name, loaded_value)
        end

      :error ->
        {:error, {:load_error, field_name, field_type, value}}
    end
  end

  defp do_decode_field(struct, nil, _value, _lookup, _strict?), do: struct

  def get_by(conn, field, name) do
    statement = "query all($a: string) {all(func: eq(#{field}, $a)) {uid expand(_all_)}}"
    with %{"all" => [obj]} <- Dlex.query!(conn, statement, %{"$a" => name}), do: obj
  end

  @doc """
  Alter schema for modules
  """
  def alter_schema(conn, snapshot) do
    with {:ok, sch} <- Dlex.query_schema(conn), do: do_alter_schema(conn, sch, snapshot)
  end

  defp do_alter_schema(conn, %{"schema" => schema, "types" => types}, snapshot) do
    delta = %{
      "schema" => snapshot["schema"] -- schema,
      "types" => delta_types(snapshot["types"], types)
    }

    delta_l = length(delta["schema"]) + length(delta["types"])

    case delta do
      %{"schema" => [], "types" => []} -> {:ok, 0}
      alter -> with {:ok, _} <- Dlex.alter(conn, %{schema: alter}), do: {:ok, delta_l}
    end
  end

  defp do_alter_schema(conn, sch, snapshot) do
    do_alter_schema(conn, Map.put_new(sch, "types", []), snapshot)
  end

  defp delta_types([], _existing_types), do: []

  defp delta_types([type_spec | types], existing_types) do
    if type_exist?(type_spec, existing_types) do
      delta_types(types, existing_types)
    else
      [type_spec | delta_types(types, existing_types)]
    end
  end

  defp type_exist?(%{"name" => name, "fields" => fields}, existing_types) do
    case Enum.find(existing_types, &(Map.get(&1, "name") == name)) do
      nil ->
        false

      %{"fields" => existing_fields} ->
        MapSet.equal?(fields_set(fields), fields_set(existing_fields))
    end
  end

  defp fields_set(fields),
    do: fields |> Enum.map(fn %{"name" => name} -> name end) |> MapSet.new()

  @doc """
  Generate snapshot for running meta process
  """
  def snapshot(meta) do
    %{modules: modules} = Meta.get(meta)

    modules
    |> MapSet.to_list()
    |> List.wrap()
    |> expand_modules()
    |> Enum.map(& &1.__schema__(:alter))
    |> Enum.reduce(%{"types" => [], "schema" => []}, fn mod_sch, acc ->
      %{
        "types" => Enum.concat(acc["types"], mod_sch["types"]),
        "schema" => Enum.concat(acc["schema"], mod_sch["schema"])
      }
    end)
  end

  defp expand_modules(modules) do
    Enum.reduce(modules, modules, fn module, modules ->
      depends_on_modules = module.__schema__(:depends_on)
      Enum.reduce(depends_on_modules, modules, &if(Enum.member?(&2, &1), do: &2, else: [&1 | &2]))
    end)
  end

  @doc """
  Drop everything from database. Use with caution, as it deletes everything, what you have
  in database.
  """
  def drop_all(conn) do
    Dlex.alter(conn, %{drop_all: true})
  end
end
