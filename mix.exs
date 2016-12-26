defmodule Cluster.Mixfile do
  use Mix.Project

  def project do
    [app: :cluster,
     version: "0.0.1",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      mod: {:cluster_app, []},
      applications: [:lager, :mnesia, :framework]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:lager, git: "https://github.com/basho/lager.git", tag:  "master", override: true},
      {:framework, git: "ssh://git@139.198.2.55/platform/framework", tag:  "master", override: true},
      {:notify, git:  "ssh://git@139.198.2.55:22/erlang/notify.git", tag: "master"}
    ]
  end

end
