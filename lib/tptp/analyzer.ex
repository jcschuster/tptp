defmodule Tptp.Analyzer do
  @moduledoc """
  A named producer of diagnostics over a `Tptp.Analysis`.

  `Tptp.Lint` is one implementation. A prover-backend probe, a project naming
  convention or a style pass would be others: an analyzer declares the dialects it
  applies to and returns diagnostics for an analysis. `run_all/3` dispatches one
  analysis to the applicable analyzers and returns their findings grouped by
  identifier.

  ## Input

  An analyzer receives a `Tptp.Analysis` rather than a `Tptp.File` so that the
  symbol table, the dialect and the source are already available. Reconstructing
  the table would require a second traversal.

  ## Dialect gating

  `dialects/0` returns one of three forms:

    * `:any` — applies to every file.
    * a list, such as `[:th0]` — applies where the file's dialect is within one of
      them by `Tptp.Query.within?/2`. `[:th0]` therefore admits a FOF file, since
      FOF is within TH0, and `[:tf0]` does not admit TF1.
    * `{:exactly, [:tf0]}` — applies to exactly these dialects, with no containment
      reasoning.

  A gated-out analyzer is reported as `{id, :skipped}`, which is distinct from
  `{id, []}`, so that a caller can separate "did not apply" from "applied and found
  nothing".

  Both list forms exist because `within?/2` is a judgement rather than a statement
  of the BNF. An analyzer depending on the exact statement keywords — one invoking
  a TF0-only implementation, for instance — should use `{:exactly, ...}`.

  ## Failure containment

  `run_all/3` catches an analyzer that raises, exits or throws, and converts it
  into a single `TPTP0800` diagnostic naming the analyzer, so that a third-party
  analyzer cannot terminate the run.
  """

  alias Tptp.Analysis
  alias Tptp.Diagnostic

  @doc "A stable atom identifying this analyzer; the key its findings are grouped under."
  @callback id() :: atom()

  @doc "A short human name, for a list of available analyzers."
  @callback label() :: String.t()

  @typedoc """
  How an analyzer says which files it wants.

  `:any` takes everything; a bare list takes anything *within* one of the named
  dialects by `Tptp.Query.within?/2`; `{:exactly, dialects}` takes those dialects and
  nothing else.
  """
  @type gate :: :any | [Tptp.Query.dialect()] | {:exactly, [Tptp.Query.dialect()]}

  @doc "The files this analyzer wants. See `t:gate/0` and the module documentation."
  @callback dialects() :: gate()

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

      Tptp.Analyzer.run_all(analysis, [Tptp.Lint], tptp_lint: [only: [Tptp.Lint.Rules.Role]])
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

  @spec applies?(gate(), Tptp.Query.dialect()) :: boolean()
  defp applies?(:any, _dialect), do: true

  defp applies?({:exactly, dialects}, dialect) when is_list(dialects), do: dialect in dialects

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
