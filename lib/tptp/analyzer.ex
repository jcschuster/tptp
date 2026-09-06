defmodule Tptp.Analyzer do
  @moduledoc """
  A named diagnostic producer over a `Tptp.Analysis`.

  `Tptp.Lint` is one. A prover-backend probe, a project naming convention, a style
  pass — each is an analyzer: it declares the dialects it applies to and returns
  diagnostics for an analysis. `run_all/3` dispatches one analysis to the
  analyzers that fit and returns their findings grouped by id.

  ## Why `Analysis` and not `File`

  An analyzer that wanted the symbol table would otherwise rebuild it, undoing the
  one-traversal guarantee. It gets the table, the dialect and the source off the
  analysis and walks nothing it does not have to.

  ## Dialect gating

  `dialects/0` returns a list of dialects or `:any`. An analyzer runs when the
  file's dialect is within one of them by `Tptp.Query.within?/2`, so `[:th0]`
  accepts a FOF file — FOF is within TH0 — and `[:tf0]` does not accept TF1. A
  gated-out analyzer is reported as `{id, :skipped}`, distinct from `{id, []}`, so
  a caller can tell "did not run" from "ran and found nothing".

  ## A raise is contained

  `run_all/3` catches an analyzer that raises, exits or throws and turns it into
  one `TPTP0800` diagnostic naming it. A third-party analyzer cannot take the run
  down.
  """

  alias Tptp.Analysis
  alias Tptp.Diagnostic

  @doc "A stable atom identifying this analyzer; the key its findings are grouped under."
  @callback id() :: atom()

  @doc "A short human name, for a list of available analyzers."
  @callback label() :: String.t()

  @doc "The dialects this analyzer applies to, or `:any`. Gated by `Tptp.Query.within?/2`."
  @callback dialects() :: [Tptp.Query.dialect()] | :any

  @doc """
  This analyzer's diagnostics for one analysis.

  `options` are whatever `run_all/3` was passed under this analyzer's `id/0`.
  """
  @callback analyze(Analysis.t(), keyword()) :: [Diagnostic.t()]

  @typedoc "One analyzer's result: its diagnostics, or `:skipped` when its dialects excluded the file."
  @type outcome :: [Diagnostic.t()] | :skipped

  @crash "TPTP0800"

  @doc """
  Run each analyzer that fits the analysis's dialect and return `{id, outcome}`
  pairs, in the order given.

  A gated-out analyzer yields `{id, :skipped}` rather than being dropped. An
  analyzer that raises, exits or throws is caught and turned into one `TPTP0800`
  diagnostic naming it.

  Per-analyzer options are read from `options` under each analyzer's `id/0`:

      Tptp.Analyzer.run_all(analysis, [Tptp.Lint], tptp_lint: [only: [Tptp.Lint.Rules.Arity]])
  """
  @spec run_all(Analysis.t(), [module()], keyword()) :: [{atom(), outcome()}]
  def run_all(%Analysis{} = analysis, analyzers, options \\ []) do
    dialect = Analysis.dialect(analysis)

    Enum.map(analyzers, fn analyzer ->
      {analyzer.id(),
       outcome(analyzer, analysis, dialect, Keyword.get(options, analyzer.id(), []))}
    end)
  end

  @spec outcome(module(), Analysis.t(), Tptp.Query.dialect(), keyword()) :: outcome()
  defp outcome(analyzer, analysis, dialect, analyzer_options) do
    if applies?(analyzer.dialects(), dialect) do
      try do
        analyzer.analyze(analysis, analyzer_options)
      rescue
        exception -> [crash(analyzer, analysis, Exception.message(exception))]
      catch
        kind, reason ->
          [crash(analyzer, analysis, Exception.format(kind, reason, __STACKTRACE__))]
      end
    else
      :skipped
    end
  end

  @spec applies?([Tptp.Query.dialect()] | :any, Tptp.Query.dialect()) :: boolean()
  defp applies?(:any, _dialect), do: true

  defp applies?(dialects, dialect) when is_list(dialects) do
    Enum.any?(dialects, &Tptp.Query.within?(dialect, &1))
  end

  @spec crash(module(), Analysis.t(), binary()) :: Diagnostic.t()
  defp crash(analyzer, analysis, detail) do
    Diagnostic.new(
      @crash,
      :error,
      Tptp.Span.new(root_id(analysis), 0, 0),
      "analyzer #{inspect(analyzer)} raised: #{detail}"
    )
  end

  @spec root_id(Analysis.t()) :: Tptp.Span.file_id()
  defp root_id(%Analysis{file: %Tptp.File{id: id}}), do: id
  defp root_id(%Analysis{file: %Tptp.Unit{root: root}}), do: root
end
