defmodule HPDF.Mixfile do
  @moduledoc false
  use Mix.Project

  @version "0.3.0"
  @url "https://github.com/hassox/hpdf"
  @maintainers [
    "Daniel Neighman",
  ]

  def project do
    [app: :hpdf,
     version: @version,
     elixir: "~> 1.5",
     package: package(),
     source_url: @url,
     maintainers: @maintainers,
     description: "PDF printer using headless Chrome",
     homepage_url: @url,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     docs: docs(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {HPDF.Application, []}]
  end

  def docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:socket, "~> 0.3.12"},
     {:httpotion, "~> 3.0.1"},
     {:uuid, "~>1.1"},
     {:poison, "~> 3.1.0" },
     {:ex_doc, ">= 0.0.0", only: :dev},
    ]
  end

  defp package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{github: @url},
      files: ~w(lib) ++ ~w(CHANGELOG.md LICENSE mix.exs README.md)
    ]
  end
end
