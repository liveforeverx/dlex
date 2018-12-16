defmodule Dlex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dlex,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Dlex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.0"},
      {:grpc, "~> 0.3.1"},
      {:gun, "1.3.0"},
      {:jason, "~> 1.0", optional: true},
      {:protobuf, "~> 0.5"}
    ]
  end
end
