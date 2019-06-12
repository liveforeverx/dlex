defmodule Dlex.Repo.Sup do
  @moduledoc false
  alias Dlex.Repo

  use Supervisor

  @doc false
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, [])
  end

  @doc false
  def init(%{meta_name: meta_name, modules: modules} = opts) do
    children = [
      {Repo, opts},
      {Repo.Meta, [name: meta_name, modules: modules]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
