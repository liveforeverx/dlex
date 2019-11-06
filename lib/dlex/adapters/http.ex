if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Dlex.Adapters.HTTP do
    use Dlex.Adapter

    require Logger

    defmodule Request do
      defstruct [:action, :start_ts, :commit_now, :json, :headers, :body]
    end

    defmodule Response do
      defstruct [:ref, :done, :status, :headers, body: []]
    end

    defmodule Error do
      defexception [:message]

      @impl true
      def message(%{message: message}), do: message
    end

    @impl true
    def connect(host, port, _opts \\ []) do
      case Mint.HTTP.connect(:http, host, port, mode: :passive) do
        {:ok, conn} -> {:ok, %{conn: conn, host: host, port: port}}
        {:error, error} -> {:error, error}
      end
    end

    @impl true
    def disconnect(%{conn: conn} = _channel) do
      with {:ok, _} <- Mint.HTTP.close(conn), do: :ok
    end

    @impl true
    def ping(channel) do
      with {:ok, _response, channel} <- get(channel, "/health", [], "", 5000), do: {:ok, channel}
    end

    @impl true
    def alter(channel, request, json_lib, opts) do
      request = %Request{
        action: :alter,
        start_ts: 0,
        json: json_lib,
        headers: [],
        body: request |> Map.from_struct() |> json_lib.encode!()
      }

      handle_request(channel, request, opts)
    end

    @impl true
    def mutate(channel, request, json_lib, opts) do
      %{mutations: [mutation], start_ts: start_ts, query: query} = request
      {type, mutation} = find_mutation(mutation)

      request = %Request{
        action: :mutate,
        start_ts: start_ts,
        commit_now: request.commit_now,
        json: json_lib,
        headers: content_type(type),
        body: build_mutation(mutation, query)
      }

      handle_request(channel, request, opts)
    end

    defp build_mutation(mutation, query) when query in [nil, ""], do: mutation

    defp build_mutation(mutation, query), do: ~s|upsert { query #{query} mutation #{mutation} }|

    defp find_mutation(%{set_json: json}) when json != "", do: {:json, ~s|{"set": #{json}}|}
    defp find_mutation(%{delete_json: json}) when json != "", do: {:json, ~s|{"delete": #{json}}|}

    defp find_mutation(%{set_nquads: nquads}) when nquads != "",
      do: {:nquads, "{ set { #{nquads} } }"}

    defp find_mutation(%{del_nquads: nquads}) when nquads != "",
      do: {:nquads, "{ delete { #{nquads} } }"}

    @impl true
    def query(channel, %{start_ts: start_ts, vars: vars, query: query}, json_lib, opts) do
      request = %Request{
        action: :query,
        start_ts: start_ts,
        json: json_lib,
        headers: content_type(:json),
        body: json_lib.encode!(%{"variables" => vars, "query" => to_string(query)})
      }

      handle_request(channel, request, opts)
    end

    @impl true
    def commit_or_abort(channel, %{start_ts: start_ts, keys: keys}, json_lib, opts) do
      request = %Request{
        action: :commit,
        start_ts: start_ts,
        json: json_lib,
        headers: content_type(:json),
        body: json_lib.encode!(keys)
      }

      handle_request(channel, request, opts)
    end

    ## Generic request handling

    defp content_type(:json), do: [{"Content-Type", "application/json"}]
    defp content_type(:nquads), do: [{"Content-Type", "application/rdf"}]

    defp handle_request(channel, request, opts) do
      %Request{
        action: action,
        start_ts: start_ts,
        commit_now: commit_now,
        json: json_lib,
        headers: headers,
        body: request_body
      } = request

      path = build_path(action, start_ts, commit_now)

      case post(channel, path, headers, request_body, opts[:timeout]) do
        {:ok, %{status: 200, body: response_body}, channel} ->
          handle_response(channel, json_lib, action, response_body)

        {:ok, response, channel} ->
          {:error, response, channel}

        {:error, reason, channel} ->
          {:error, reason, channel}
      end
    end

    defp build_path(action, start_ts, commit_now) do
      path = path(action)

      opts = [{"startTs", start_ts, start_ts > 0}, {"commitNow", "true", commit_now}]
      opts = for {key, value, true} <- opts, do: "#{key}=#{value}"
      opts_string = Enum.join(opts, "&")

      if opts_string != "", do: "#{path}?#{opts_string}", else: path
    end

    defp path(:alter), do: "/alter"
    defp path(:mutate), do: "/mutate"
    defp path(:query), do: "/query"
    defp path(:commit), do: "/commit"

    defp handle_response(channel, json_lib, action, body) do
      response = json_lib.decode!(body)

      case Map.get(response, "errors", []) do
        [] ->
          {:ok, parse_success(action, response), channel}

        errors ->
          {:error, %Error{message: parse_error(errors)}, channel}
      end
    end

    defp parse_success(:alter, %{"data" => data}) do
      Dlex.Api.Payload.new(Data: data)
    end

    defp parse_success(:mutate, %{"data" => %{"uids" => uids}} = response) do
      Dlex.Api.Response.new(txn: parse_txn(response), uids: uids)
    end

    defp parse_success(:query, %{"data" => data} = response) do
      Dlex.Api.Response.new(txn: parse_txn(response), json: data)
    end

    defp parse_success(:commit, response) do
      parse_txn(response)
    end

    defp parse_txn(json, aborted \\ false)

    defp parse_txn(%{"extensions" => %{"txn" => txn}}, aborted) do
      Dlex.Api.TxnContext.new(
        start_ts: Map.get(txn, "start_ts", 0),
        commit_ts: Map.get(txn, "commit_ts", 0),
        aborted: aborted || Map.get(txn, "aborted", false),
        preds: Map.get(txn, "preds", []),
        keys: Map.get(txn, "keys", [])
      )
    end

    defp parse_txn(_, aborted) do
      Dlex.Api.TxnContext.new(aborted: aborted)
    end

    defp parse_error([%{"message" => message} | _]), do: message
    defp parse_error(errors), do: inspect(errors)

    ## HTTP Client implementation

    def post(channel, path, headers, body, timeout),
      do: request(channel, "POST", path, headers, body, timeout)

    def get(channel, path, headers, body, timeout),
      do: request(channel, "GET", path, headers, body, timeout)

    defp request(channel, method, path, headers, body, timeout) do
      do_request(channel, method, path, headers, body, timeout, true)
    end

    defp do_request(%{conn: conn} = channel, method, path, headers, body, timeout, may_connect) do
      with {:ok, conn, ref} <- Mint.HTTP.request(conn, method, path, headers, body),
           {:ok, response, conn} <- recv(conn, ref, timeout) do
        {:ok, response, %{channel | conn: conn}}
      else
        {:error, conn, %{reason: :closed}, []} when may_connect ->
          conn_request(%{channel | conn: conn}, method, path, headers, body, timeout)

        {:error, conn, %{reason: :closed}} when may_connect ->
          conn_request(%{channel | conn: conn}, method, path, headers, body, timeout)

        {:error, conn, error} ->
          {:error, error, %{channel | conn: conn}}

        {:error, conn, error, _} ->
          {:error, error, %{channel | conn: conn}}
      end
    end

    defp conn_request(%{host: host, port: port} = channel, method, path, headers, body, timeout) do
      case Mint.HTTP.connect(:http, host, port, mode: :passive) do
        {:ok, conn} ->
          channel = %{channel | conn: conn, host: host, port: port}
          do_request(channel, method, path, headers, body, timeout, false)

        {:error, error} ->
          {:error, error, channel}
      end
    end

    defp recv(conn, ref, timeout) do
      start_time = :erlang.monotonic_time(:microsecond)
      do_recv(conn, %Response{ref: ref}, start_time, timeout)
    end

    defp do_recv(conn, response, start_time, timeout) do
      now_time = :erlang.monotonic_time(:microsecond)
      recv_timeout = max(timeout - (now_time - start_time), 0)

      with {:ok, conn, responses} <- Mint.HTTP.recv(conn, 0, recv_timeout) do
        case Enum.reduce(responses, response, &parse_response/2) do
          %{done: true} = response -> {:ok, response, conn}
          response -> do_recv(conn, response, start_time, timeout)
        end
      end
    end

    defp parse_response(message, %{ref: ref} = response) when ref != elem(message, 1),
      do: response

    defp parse_response({:status, _, status}, response), do: %{response | status: status}
    defp parse_response({:headers, _, headers}, response), do: %{response | headers: headers}

    defp parse_response({:data, _, data}, %{body: body} = response),
      do: %{response | body: [data | body]}

    defp parse_response({:done, _}, %{body: body} = response) do
      body = body |> Enum.reverse() |> Enum.join()
      %{response | body: body, done: true}
    end
  end
end
