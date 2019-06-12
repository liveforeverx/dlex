defmodule Dlex.Repo.Meta do
  @moduledoc """
  Meta holder for repository.
  """

  alias Dlex.Repo

  use GenServer

  @doc false
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register name and modules
  """
  def register(name, modules) do
    GenServer.call(name, {:register, List.wrap(modules)})
  end

  @doc """
  Get saved meta information for the repo
  """
  def get(name) do
    :persistent_term.get(name, %{modules: MapSet.new(), lookup: %{}})
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    modules = Keyword.fetch!(opts, :modules)
    register_modules(name, modules)
    {:ok, name}
  end

  @impl true
  def handle_call({:register, new_modules}, _from, name) do
    {:reply, register_modules(name, new_modules), name}
  end

  defp register_modules(name, new_modules) do
    %{modules: modules, lookup: lookup} = get(name)

    {new_modules, modules} =
      Enum.flat_map_reduce(new_modules, modules, fn new_module, modules ->
        if MapSet.member?(modules, new_module),
          do: {[], modules},
          else: {[new_module], MapSet.put(modules, new_module)}
      end)

    lookup = Repo.build_lookup_map(lookup, new_modules)
    :persistent_term.put(name, %{modules: modules, lookup: lookup})
  end
end
