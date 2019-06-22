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
  def drop_all(pid) do
    Dlex.alter(pid, %{drop_all: true})
  end
end
