defmodule Dlex do
  @moduledoc """
  Dgraph driver for Elixir.

  This module handles the connection to Dgraph, providing pooling (via `DBConnection`), queries,
  mutations and transactions.
  """

  alias Dlex.{Query, Type}

  @type conn :: DBConnection.conn()
  @type uid :: String.t()
  @type query :: iodata
  @type query_map :: %{:query => query, optional(:vars) => map}
  @type statement :: iodata | map
  @type mutation :: %{
          optional(:cond) => iodata,
          optional(:set) => statement(),
          optional(:delete) => statement()
        }
  @type mutations :: [mutation]

  @timeout 15_000
  @default_keepalive :infinity
  @idle_interval 15_000

  @doc """
  Start dgraph connection process.

  ## Options

    * `:hostname` - Server hostname (default: DGRAPH_HOST, than `localhost`)
    * `:port` - Server port (default: DGRAPH_PORT env var, then 9080)
    * `:keepalive` - Keepalive option for http client (default: `:infinity`)
    * `:json_library` - Specifies json library to use (default: `Jason`)
    * `:transport` - Specify if grpc or http should be used (default: `grpc`)
    * `:connect_timeout` - Connection timeout in milliseconds (default: `#{@timeout}`);

  ### SSL/TLS configuration (automaticly enabled, if required files provided)

    * `:cacertfile` - Path to your CA certificate. Should be provided for SSL authentication
    * `:certfile` - Path to client certificate. Should be additionally provided for TSL
      authentication
    * `:keyfile` - Path to client key. Should be additionally provided for TSL authentication

  ### DBConnection options

    * `:backoff_min` - The minimum backoff interval (default: `1_000`)
    * `:backoff_max` - The maximum backoff interval (default: `30_000`)
    * `:backoff_type` - The backoff strategy, `:stop` for no backoff and
    to stop, `:exp` for exponential, `:rand` for random and `:rand_exp` for
    random exponential (default: `:rand_exp`)
    * `:name` - A name to register the started process (see the `:name` option
    in `GenServer.start_link/3`)
    * `:pool` - Chooses the pool to be started
    * `:pool_size` - Chooses the size of the pool
    * `:queue_target` in microseconds, defaults to 50
    * `:queue_interval` in microseconds, defaults to 1000

  ## Example of usage

      iex> {:ok, conn} = Dlex.start_link()
      {:ok, #PID<0.216.0>}
  """
  @spec start_link(Keyword.t()) :: {:ok, pid} | {:error, Dlex.Error.t() | term}
  def start_link(opts \\ []) do
    opts = default_opts(opts)
    DBConnection.start_link(Dlex.Protocol, opts)
  end

  defp default_opts(opts) do
    opts
    |> Keyword.put_new(:hostname, System.get_env("DGRAPH_HOST") || "localhost")
    |> Keyword.put_new(:port, System.get_env("DGRAPH_PORT") || 9080)
    |> Keyword.put_new(:transport, :grpc)
    |> Keyword.put_new(:connect_timeout, @timeout)
    |> Keyword.put_new(:timeout, @timeout)
    |> Keyword.put_new(:keepalive, @default_keepalive)
    |> Keyword.put_new(:idle_interval, @idle_interval)
    |> Keyword.update!(:port, &to_integer/1)
    |> Keyword.put_new_lazy(:json_library, fn -> json_library() end)
  end

  defp json_library(), do: Application.get_env(:dlex, :json_library, Jason)

  defp to_integer(port) when is_binary(port), do: String.to_integer(port)
  defp to_integer(port) when is_integer(port), do: port

  @doc """
  Supervisor callback.

  For available options, see: `start_link/1`.
  """
  @spec child_spec(Keyword.t()) :: Supervisor.Spec.spec()
  def child_spec(opts) do
    opts = default_opts(opts)
    DBConnection.child_spec(Dlex.Protocol, opts)
  end

  @doc """
  Alter dgraph schema

  Example

      iex> Dlex.alter(conn, "name: string @index(term) .")
      {:ok, ""}

  ## Options

    * `:timeout` - Call timeout (default: `#{@timeout}`)
  """
  @spec alter(conn, iodata | map, Keyword.t()) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def alter(conn, statement, opts \\ []) do
    query = %Query{type: Type.Operation, statement: statement}

    with {:ok, _, result} <- DBConnection.prepare_execute(conn, query, %{}, opts),
         do: {:ok, result}
  end

  @doc """
  Alter dgraph schema
  """
  @spec alter(conn, iodata | map, Keyword.t()) :: map
  def alter!(conn, statement, opts \\ []) do
    case alter(conn, statement, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Send mutation to dgraph. Shortcut for `mutate(conn, query, %{set: statement}, opts)`

  Options:

    * `return_json` - if json with uids should be returned (default: `false`)

  Example of usage

      iex> mutation = "
           _:foo <name> "Foo" .
           _:foo <owns> _:bar .
            _:bar <name> "Bar" .
           "
      iex> Dlex.set(conn, mutation)
      {:ok, %{uids: %{"bar" => "0xfe04c", "foo" => "0xfe04b"}, queries: %{}}}

  Using `json`

      iex> json = %{"name" => "Foo", "owns" => [%{"name" => "Bar"}]}
           Dlex.set(conn, json)
      {:ok, %{uids: %{"blank-0" => "0xfe04d", "blank-1" => "0xfe04e"}, queries: %{}}}
      iex> Dlex.set(conn, json, return_json: true)
      {:ok,
       %{json: %{
         "name" => "Foo",
         "owns" => [%{"name" => "Bar", "uid" => "0xfe050"}],
         "uid" => "0xfe04f"
       }}}

  ## Options

    * `:timeout` - Call timeout (default: `#{@timeout}`)

  """

  @spec set(conn, query_map, statement, Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}

  def set(conn, query, statement, opts), do: mutate(conn, query, %{set: statement}, opts)

  @doc """
  The same as `Dlex.set(conn, "", statement, [])`
  """
  @spec set(conn, statement) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def set(conn, statement), do: mutate(conn, %{}, %{set: statement}, [])

  @doc """
  The same as `Dlex.set(conn, "", statement, opts)`.
  """
  @spec set(conn, query_map | statement, statement | Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}
  def set(conn, %{query: _} = query, statement), do: mutate(conn, query, %{set: statement}, [])
  def set(conn, statement, opts), do: mutate(conn, %{}, %{set: statement}, opts)

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `set/4`.
  """
  @spec set!(conn, query_map, statement, Keyword.t()) :: map | no_return
  def set!(conn, query, statement, opts) do
    case mutate(conn, query, %{set: statement}, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `set/3`.
  """
  @spec set!(conn, query_map | statement, statement | Keyword.t()) :: map | no_return
  def set!(conn, statement, opts) do
    case set(conn, statement, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `set/2`.
  """
  @spec mutate!(conn, statement) :: map | no_return
  def set!(conn, statement) do
    case mutate(conn, %{}, %{set: statement}, []) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Send mutation to dgraph

  Options:

    * `return_json` - if json with uids should be returned (default: `false`)

  Example of usage

      iex> mutation = "
           _:foo <name> "Foo" .
           _:foo <owns> _:bar .
            _:bar <name> "Bar" .
           "
      iex> Dlex.mutate(conn, %{set: mutation})
      {:ok, %{uids: %{"bar" => "0xfe04c", "foo" => "0xfe04b"}, queries: %{}}}

  Using `json`

      iex> json = %{"name" => "Foo", "owns" => [%{"name" => "Bar"}]}
           Dlex.mutate(conn, %{set: json})
      {:ok, %{uids: %{"blank-0" => "0xfe04d", "blank-1" => "0xfe04e"}, queries: %{}}}
      iex> Dlex.mutate(conn, %{set: json}, return_json: true)
      {:ok,
       %{json: %{
         "name" => "Foo",
         "owns" => [%{"name" => "Bar", "uid" => "0xfe050"}],
         "uid" => "0xfe04f"
       }}}

  ## Options

    * `:timeout` - Call timeout (default: `#{@timeout}`)
  """

  @spec mutate(conn, query_map, mutations, Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}

  def mutate(conn, query_map, mutations, opts) do
    query_statement = Map.get(query_map, :query, "")
    query_vars = Map.get(query_map, :vars, %{})
    query = %Query{type: Type.Mutation, statement: List.wrap(mutations), query: query_statement}

    with {:ok, _, result} <- DBConnection.prepare_execute(conn, query, query_vars, opts),
         do: {:ok, result}
  end

  @doc """
  The same as `Dlex.mutate(conn, "", mutations, [])`
  """
  @spec mutate(conn, mutations) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def mutate(conn, mutations), do: mutate(conn, %{}, mutations, [])

  @doc """
  The same as `Dlex.mutate(conn, "", mutations, opts)`.
  """
  @spec mutate(conn, query_map | mutations, mutations | Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}
  def mutate(conn, %{query: _} = query, mutations), do: mutate(conn, query, mutations, [])
  def mutate(conn, mutations, opts), do: mutate(conn, %{}, mutations, opts)

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `mutate/5`.
  """
  @spec mutate!(conn, query, mutations, Keyword.t()) :: map | no_return
  def mutate!(conn, query, mutations, opts) do
    case mutate(conn, query, mutations, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `mutate/4`.
  """
  @spec mutate!(conn, query | mutations, mutations | Keyword.t()) :: map | no_return
  def mutate!(conn, mutations, opts) do
    case mutate(conn, mutations, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation and returns the result or raises `Dlex.Error` if there was an error.
  See `mutate/2`.
  """
  @spec mutate!(conn, mutations) :: map | no_return
  def mutate!(conn, mutations) do
    case mutate(conn, %{}, mutations, []) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Send mutation to dgraph

  Options:

    * `return_json` - if json with uids should be returned (default: `false`)

  Example of usage

      iex> Dlex.delete(conn, %{"uid" => "0xfe04c"})
      {:ok, %{queries: %{}, uids: %{}}}

  Using `json`

      iex> json = %{"uid" => "0xfe04c"}
           Dlex.delete(conn, json)
      {:ok, %{queries: %{}, uids: %{}}}

      iex> Dlex.delete(conn, json, return_json: true)
      {:ok, %{json: %{"uid" => "0xfe04c"}, queries: %{}, uids: %{}}}

  ## Options

    * `:timeout` - Call timeout (default: `#{@timeout}`)

  """
  @spec delete(conn, query, statement, Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}
  def delete(conn, query, statement, opts), do: mutate(conn, query, %{delete: statement}, opts)

  @doc """
  The same as `Dlex.delete(conn, "", deletion, [])`
  """
  @spec delete(conn, statement) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def delete(conn, statement), do: mutate(conn, %{}, %{delete: statement}, [])

  @doc """
  The same as `Dlex.delete(conn, query, deletion, [])` or `Dlex.delete(conn, "", deletion, opts)`
  """
  @spec delete(conn, query | statement, statement | Keyword.t()) ::
          {:ok, map} | {:error, Dlex.Error.t() | term}
  def delete(conn, %{query: _} = query, statement),
    do: mutate(conn, query, %{delete: statement}, [])

  def delete(conn, statement, opts), do: mutate(conn, %{}, %{delete: statement}, opts)

  @doc """
  Runs a mutation with delete target and returns the result or raises `Dlex.Error` if there was
  an error. See `delete/4`.
  """
  @spec delete!(conn, query, statement, Keyword.t()) :: map | no_return
  def delete!(conn, query, statement, opts) do
    case mutate(conn, query, %{delete: statement}, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation with delete target and returns the result or raises `Dlex.Error` if there was
  an error. See `delete/3`.
  """
  @spec delete(conn, query | statement, statement | Keyword.t()) :: map | no_return
  def delete!(conn, query_or_statement, statement_or_opts) do
    case delete(conn, query_or_statement, statement_or_opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs a mutation with delete target and returns the result or raises `Dlex.Error` if there was
  an error. See `delete/2`.
  """
  @spec delete(conn, statement) :: map | no_return
  def delete!(conn, statement) do
    case mutate(conn, %{}, %{delete: statement}, []) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Send query to dgraph

  Example of usage

      iex> query = "
           query foo($a: string) {
              foo(func: eq(name, $a)) {
                uid
                expand(_all_)
              }
            }
           "
      iex> Dlex.query(conn, query, %{"$a" => "Foo"})
      {:ok, %{"foo" => [%{"name" => "Foo", "uid" => "0xfe04d"}]}}

  Query options (see DGraph documentation for more information):

      * `best_effort` - `boolean`
      * `read_only` - `boolean`
  """
  @spec query(conn, iodata, map, Keyword.t()) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def query(conn, statement, parameters \\ %{}, opts \\ []) do
    query = %Query{type: Type.Query, statement: statement}

    with {:ok, _, result} <- DBConnection.prepare_execute(conn, query, parameters, opts),
         do: {:ok, result}
  end

  @doc """
  Runs a query and returns the result or raises `Dlex.Error` if there was an error.
  See `query/3`.
  """
  @spec query!(conn, iodata, map, Keyword.t()) :: map | no_return
  def query!(conn, statement, parameters \\ %{}, opts \\ []) do
    case query(conn, statement, parameters, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Query schema of dgraph
  """
  @spec query_schema(conn) :: {:ok, map} | {:error, Dlex.Error.t() | term}
  def query_schema(conn), do: query(conn, "schema {}")

  @doc """
  Query schema of dgraph
  """
  @spec query_schema!(conn) :: map | no_return
  def query_schema!(conn), do: query!(conn, "schema {}")

  @doc """
  Execute serie of queries and mutations in a transactions
  """
  @spec transaction(conn, (DBConnection.t() -> result :: any), Keyword.t()) ::
          {:ok, result :: any} | {:error, any}
  def transaction(conn, fun, opts \\ []) do
    try do
      DBConnection.transaction(conn, fun, opts)
    catch
      :error, %Dlex.Error{} = error ->
        {:error, error}
    end
  end
end
