defmodule Dlex.Error do
  @moduledoc """
  Dgraph or connection error are wrapped in Dlex.Error.
  """
  defexception [:reason, :action]

  @type t :: %Dlex.Error{}

  @impl true
  def message(%{action: action, reason: reason}) do
    "#{action} failed with #{inspect(reason)}"
  end
end
