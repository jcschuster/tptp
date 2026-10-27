defmodule Tptp.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/jcschuster/tptp"

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
    "A span-preserving parser, linter and printer for the TPTP language, " <>
      "generated from the published BNF; with the SZS ontologies and TSTP readers."
  end

  # Renders the ```mermaid blocks of the extras (the README's pipeline).
  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: false,
          theme: document.body.className.includes("dark") ? "dark" : "default"
        });
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "DOI" => "https://doi.org/10.5281/zenodo.23063474",
        "TPTP" => "https://www.tptp.org"
      },
      files: ~w(lib src/tptp_parser.yrl priv/bnf mix.exs README.md LICENSE NOTICE
           CHANGELOG.md reports examples .formatter.exs CITATION.cff)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.svg",
      before_closing_body_tag: &before_closing_body_tag/1,
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "examples/demo.livemd",
        "reports/CORPUS.md",
        "reports/CENSUS.md",
        "CHANGELOG.md",
        "NOTICE",
        "LICENSE"
      ],
      groups_for_modules: [
        "Reading a file": [
          Tptp,
          Tptp.File,
          Tptp.Unit,
          Tptp.Statement,
          Tptp.Statement.Annotated,
          Tptp.Statement.Include,
          Tptp.Node,
          Tptp.Query,
          Tptp.Header
        ],
        Analysis: [
          Tptp.Analysis,
          Tptp.Analyzer
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
          Tptp.Lint.Rules.AtomTyping,
          Tptp.Lint.Rules.Conjecture,
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
          Tptp.Szs.Ontology,
          Tptp.Szs.Page
        ],
        TSTP: [
          Tptp.Derivation,
          Tptp.Derivation.Node,
          Tptp.Derivation.Step,
          Tptp.Tstp,
          Tptp.Tstp.Solution
        ],
        "Generated from the BNFs": [
          Tptp.Bnf,
          Tptp.Bnf.Rule,
          Tptp.Bnf.Vocabulary,
          Tptp.Bnf.Generator,
          Tptp.Bnf.Szs,
          Tptp.Bnf.Oracle
        ]
      ]
    ]
  end
end
