defmodule Dlex.Adapters.HTTP do
  use Dlex.Adapter
  alias Dlex.Api.Payload

  require Logger

  # time a connection stays alive when idle
  # number of connections to stay open per hackney pool (we use DBConnection to handle the pool)
  # default request timeout for HTTPoison requests
  @pool_timeout 60_000
  @pool_size 1
  @default_request_timeout 15_000

  # grab the JSON adapter to use
  defp json_adapter(), do: Application.get_env(:dlex, :json_adapter, Jason)

  # default request options
  defp options_to_httpoison_options(opts) do
    [recv_timeout: Keyword.get(opts, :timeout, @default_request_timeout)]
  end

  # grab default HTTPoison options
  defp default_opts(%{pool: pool}, opts \\ []), do: [hackney: [pool: pool]] ++ opts

  # given any action and the response body, parse any response properly (checking for errors)
  defp parse_response(action, raw_response_body) do
    parsed_body = json_adapter().decode!(raw_response_body)
    errors = parsed_body["errors"]

    if errors && length(errors) > 0 do
      parse_errors(errors)
    else
      data = parsed_body["data"]
      uids = if data, do: data["uids"], else: nil
      extensions = parsed_body["extensions"]
      txn = if extensions, do: extensions["txn"], else: nil

      case action do
        :alter ->
          {:ok, Dlex.Api.Payload.new(Data: data)}

        :mutate ->
          {:ok, Dlex.Api.Assigned.new(uids: uids, context: txn_from_json(txn))}

        :query ->
          data_as_json_str = json_adapter().encode!(parsed_body["data"])
          {:ok, Dlex.Api.Response.new(txn: txn_from_json(txn), json: data_as_json_str)}

        :commit ->
          {:ok, txn_from_json(txn)}
      end
    end
  end

  # grab the first error message
  defp error_message_from_response(errs) do
    error =
      Enum.find(errs, false, fn e ->
        code = e["code"]
        String.contains?(code, "InvalidRequest") || String.contains?(code, "Error")
      end)

    if error, do: error["message"], else: errs
  end

  # given the error array back from Dgraph, parse the first one and use it as the reason
  defp parse_errors(errors) do
    reason = error_message_from_response(errors)
    if is_binary(reason), do: {:error, reason}, else: {:error, "Unknown error occured: #{inspect(errors)}"}
  end

  # given a json representation of a transaction, create the GRPC stub object
  defp txn_from_json(json, aborted \\ false) do
    if json do
      start_ts = Map.get(json, "start_ts", 0)
      commit_ts = Map.get(json, "commit_ts", 0)
      local_aborted = Map.get(json, "aborted", false)
      preds = Map.get(json, "preds", [])
      keys = Map.get(json, "keys", [])
      a = aborted || local_aborted
      Dlex.Api.TxnContext.new(start_ts: start_ts, commit_ts: commit_ts, aborted: a, preds: preds, keys: keys)
    else
      Dlex.Api.TxnContext.new(aborted: aborted)
    end
  end

  @impl true
  @doc """
  Connects to the Dgraph HTTP server via HTTPoison (using Hackney for internal pooling)
  We generate a unique pool name so DBConnection can handle the pooling and the requests don't share the default
  """
  def connect(address, opts \\ []) do
    pool_name = String.to_atom("dlex-#{UUID.uuid4()}")

    case :hackney_pool.start_pool(pool_name, timeout: @pool_timeout, max_connections: @pool_size) do
      :ok ->
        Logger.debug(fn -> "Dlex.Adapter.HTTP -> started hackney pool #{pool_name}" end)
        {:ok, %{address: "http://#{address}", pool: pool_name}}

      _ ->
        {:error, "Failed to start the hackney pool for HTTP adapter"}
    end
  end

  @impl true
  @doc """
  Disconnects the connections that are living in the hackney pool we generated
  """
  def disconnect(%{pool: pool}) do
    case :hackney_pool.stop_pool(pool) do
      :ok ->
        Logger.debug(fn -> "Dlex.Adapter.HTTP -> stopped hackney pool #{pool}" end)
        :ok

      val ->
        val
    end
  end

  @impl true
  @doc """
  Pings the /health endpoint to make sure we have a connection (DBConnection will disconnect if this fails)
  """
  def ping(%{address: address, pool: pool} = conn) do
    case HTTPoison.get("#{address}/health", [], default_opts(conn)) do
      {:ok, _} ->
        Logger.debug(fn -> "Dlex.Adapter.HTTP -> health check passed" end)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def alter(%{address: address} = conn, request, request_options) do
    request = json_adapter().encode!(Map.from_struct(request))
    opts = options_to_httpoison_options(request_options)

    case HTTPoison.post("#{address}/alter", request, [], default_opts(conn, opts)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> parse_response(:alter, body)
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @mutation_json_headers ["X-Dgraph-MutationType": "json", "Content-Type": "application/json"]
  @mutation_rdf_headers ["Content-Type": "application/rdf"]
  defp headers_from_mutation(mutation) do
    h = if mutation.commit_now, do: ["X-Dgraph-CommitNow": "true"], else: []
    h = if mutation.set_json != "" || mutation.delete_json != "", do: h ++ @mutation_json_headers, else: h
    if mutation.set_nquads != "" || mutation.del_nquads != "", do: h ++ @mutation_rdf_headers, else: h
  end

  defp url_from_mutation(mutation) do
    if mutation.start_ts > 0, do: "mutate/#{mutation.start_ts}", else: "mutate"
  end

  defp request_from_mutation(mutation) do
    cond do
      mutation.set_json != "" -> json_adapter().encode!(%{set: json_adapter().decode!(mutation.set_json)})
      mutation.delete_json != "" -> json_adapter().encode!(%{delete: json_adapter().decode!(mutation.delete_json)})
      mutation.set_nquads != "" -> "{ set { #{mutation.set_nquads} } }"
      mutation.del_nquads != "" -> "{ delete { #{mutation.del_nquads} } }"
    end
  end

  @impl true
  def mutate(%{address: address} = conn, request, request_options) do
    url = "#{address}/#{url_from_mutation(request)}"
    start_ts = request.start_ts
    headers = headers_from_mutation(request)
    http_request = request_from_mutation(Map.from_struct(request))
    opts = options_to_httpoison_options(request_options)

    case HTTPoison.post(url, http_request, headers, default_opts(conn, opts)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> parse_response(:mutate, body)
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers_from_query(query) do
    headers = if query.vars, do: ["X-Dgraph-Vars": json_adapter().encode!(query.vars)], else: []
    headers = headers ++ ["Content-Type": "application/json"]
  end

  defp url_from_query(query) do
    if query.start_ts > 0, do: "query/#{query.start_ts}", else: "query"
  end

  defp request_from_query(query) do
    cond do
      query.query -> query.query
      true -> query
    end
  end

  @impl true
  def query(%{address: address} = conn, request, request_options) do
    url = "#{address}/#{url_from_query(request)}"
    start_ts = request.start_ts
    headers = headers_from_query(request)
    http_request = request_from_query(Map.from_struct(request))
    opts = options_to_httpoison_options(request_options)

    case HTTPoison.post(url, http_request, headers, default_opts(conn, opts)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> parse_response(:query, body)
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp url_from_commit(request) do
    "commit/#{request.start_ts}"
  end

  defp headers_from_commit(_request) do
    ["Content-Type": "application/json"]
  end

  defp request_from_commit(request) do
    if length(request.keys) > 0, do: json_adapter().encode!(request.keys), else: "[]"
  end

  @impl true
  def commit_or_abort(%{address: address} = conn, request, request_options) do
    url = "#{address}/#{url_from_commit(request)}"
    start_ts = request.start_ts
    headers = headers_from_commit(request)
    http_request = request_from_commit(Map.from_struct(request))
    opts = options_to_httpoison_options(request_options)

    case HTTPoison.post(url, http_request, headers, default_opts(conn, opts)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> parse_response(:commit, body)
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp abort(%{address: address} = conn, request, request_options) do
    {:error, "Transaction has been aborted. Please retry."}
  end
end
