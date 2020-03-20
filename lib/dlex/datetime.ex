defmodule Dlex.DateTime do
  @moduledoc """
  An Ecto type for Dgraph RFC3339 datetimes.

  Datetime is given as Elixir DateTime, and inserted as RFC33339 datetime.
  """

  use Ecto.Type

  def type, do: :datetime

  def cast(%DateTime{} = datetime), do: {:ok, Timex.format!(datetime, "{RFC3339}")}
  def cast(_), do: :error

  def load(datetime) when is_binary(datetime), do: {:ok, Timex.parse!(datetime, "{RFC3339}")}

  def dump(%DateTime{} = datetime), do: {:ok, datetime}
  def dump(_), do: :error
end
