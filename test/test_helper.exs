ExUnit.start()

defmodule Dlex.TestHelper do
  def drop_all(pid) do
    Dlex.alter(pid, %{drop_all: true})
  end
end
