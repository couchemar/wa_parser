defmodule WaParserEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://nest.pijul.com/couchemar/wa_parser"

  def project do
    [
      app: :wa_parser_ex,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "WaParserEx",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # The Erlang core (`:wa_parser`) is a separate hex package built with
  # rebar3. Locally it lives in the parent directory; set WA_PARSER_PATH
  # (see the flake/dev shell) to build against the sibling source instead
  # of the published release.
  defp deps do
    core =
      case System.get_env("WA_PARSER_PATH") do
        nil -> {:wa_parser, "~> 0.1"}
        path -> {:wa_parser, path: path, manager: :rebar3, override: true}
      end

    [
      core,
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Idiomatic Elixir wrapper over the wa_parser WebAssembly binary parser " <>
      "(the Erlang :wa_parser core). Streams a .wasm binary into parse events " <>
      "and raises %WaParser.ParseError{} on malformed input."
  end

  defp package do
    [
      licenses: ["Unlicense"],
      links: %{
        "Pijul" => @source_url,
        "Core (Erlang)" => "https://hex.pm/packages/wa_parser"
      },
      files: ~w(lib mix.exs README.md UNLICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "UNLICENSE"]
    ]
  end
end
