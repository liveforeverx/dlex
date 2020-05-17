defmodule Dlex.TestHelper do
  @dlex_adapter :"#{System.get_env("DLEX_ADAPTER", "grpc")}"
  @offset String.to_integer(System.get_env("DLEX_PORT_OFFSET", "0"))

  def opts() do
    case @dlex_adapter do
      :http -> [transport: :http, port: 8080 + @offset]
      :grpc -> [transport: :grpc, port: 9080 + @offset]
    end
  end

  def drop_all(pid) do
    Dlex.alter(pid, %{drop_all: true})
  end

  def adapter(), do: @dlex_adapter
end

defmodule Dlex.User do
  use Dlex.Node

  schema "user" do
    field :name, :string, index: ["term"]
    field :age, :integer
    field :friends, :uid
    field :cache, :any, virtual: true
  end
end

defmodule Dlex.TestRepo do
  use Dlex.Repo, otp_app: :dlex, modules: [Dlex.User]
end

to_skip =
  case Dlex.TestHelper.adapter() do
    :http -> [:grpc]
    :grpc -> [:http]
  end

{:ok, _} = Application.ensure_all_started(:grpc)
ExUnit.start(exclude: [:skip | to_skip])
