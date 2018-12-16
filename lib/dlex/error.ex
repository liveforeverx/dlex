defmodule Dlex.Error do
  defexception [:reason, :action]

  @type t :: %Dlex.Error{}

  @impl true
  def message(%{action: action, reason: reason}) do
    "#{action} failed with #{inspect(reason)}"
  end
end
