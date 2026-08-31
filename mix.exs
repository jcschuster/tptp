defmodule Tptp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/johannes-schuster/tptp"

  def project do
    [
      app: :tptp,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      compilers: [:yecc] ++ Mix.compilers(),
      erlc_options: erlc_options(),
      yecc_options: [warnings_as_errors: true],
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      name: "Tptp",
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "checks", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "checks"]
  defp elixirc_paths(_env), do: ["lib"]

  defp erlc_options do
    [:debug_info, :warnings_as_errors]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:mix, :crypto, :parsetools, :inets, :ssl, :credo],
      flags: [:error_handling, :unknown, :extra_return]
    ]
  end

  defp description do
    "A faithful, span-carrying parser, linter and printer for the TPTP language."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib src/tptp_parser.yrl priv/bnf priv/szs mix.exs README.md LICENSE NOTICE
           CHANGELOG.md examples .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "NOTICE", "LICENSE"],
      groups_for_modules: [
        "Reading a file": [
          Tptp,
          Tptp.File,
          Tptp.Unit,
          Tptp.Statement,
          Tptp.Statement.Annotated,
          Tptp.Statement.Include,
          Tptp.Node,
          Tptp.Query
        ],
        Stages: [
          Tptp.Lexer,
          Tptp.Splitter,
          Tptp.Parser,
          Tptp.Input,
          Tptp.Token
        ],
        Diagnostics: [
          Tptp.Diagnostic,
          Tptp.Error,
          Tptp.Span
        ],
        Includes: [
          Tptp.Include,
          Tptp.Resolver,
          Tptp.Resolver.Cascade,
          Tptp.Resolver.Fs,
          Tptp.Resolver.Http,
          Tptp.Resolver.Map,
          Tptp.Resolver.None
        ],
        Lint: [
          Tptp.Lint,
          Tptp.Lint.Rule,
          Tptp.Lint.Context,
          Tptp.Lint.Table,
          Tptp.Lint.Collect,
          Tptp.Lint.Rules.Arity,
          Tptp.Lint.Rules.AtomTyping,
          Tptp.Lint.Rules.Declaration,
          Tptp.Lint.Rules.DefinedWord,
          Tptp.Lint.Rules.DuplicateName,
          Tptp.Lint.Rules.Parent,
          Tptp.Lint.Rules.Rank1,
          Tptp.Lint.Rules.Role
        ],
        Printers: [
          Tptp.Printer.Canonical,
          Tptp.Printer.Pretty,
          Tptp.Printer.Format,
          Tptp.Printer.Spacing,
          Tptp.Printer.Shapes
        ],
        SZS: [
          Tptp.Szs,
          Tptp.Szs.Ontology
        ],
        "Generated from the BNF": [
          Tptp.Bnf,
          Tptp.Bnf.Rule,
          Tptp.Bnf.Vocabulary,
          Tptp.Bnf.Generator,
          Tptp.Bnf.Oracle,
          Tptp.Szs.Extract,
          Tptp.Szs.Generator
        ]
      ]
    ]
  end
end
