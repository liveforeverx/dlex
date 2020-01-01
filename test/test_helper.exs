{:ok, _} = Application.ensure_all_started(:grpc)
ExUnit.start()

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

defmodule Dlex.TestHelper do
  @dlex_adapter :"#{System.get_env("DLEX_ADAPTER", "grpc")}"

  def opts() do
    case @dlex_adapter do
      :http -> [transport: :http, port: 8090]
      :grpc -> [transport: :grpc, port: 9090]
    end
  end

  def drop_all(pid) do
    Dlex.alter(pid, %{drop_all: true})
  end
end
