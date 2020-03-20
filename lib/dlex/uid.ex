defmodule Dlex.UID do
  @moduledoc """
  An Ecto type for Dgraph UIDs.
  """

  use Ecto.Type

  def type, do: :uid

  def cast(uid) when is_binary(uid), do: {:ok, uid}
  def cast(_), do: :error

  def load(uid) when is_binary(uid), do: {:ok, uid}

  def dump(uid) when is_binary(uid), do: {:ok, uid}
  def dump(_), do: :error
end
