defmodule Tptp.Analysis do
  @moduledoc """
  The file, its diagnostics, the symbol table and the dialect, from one traversal.

  An editor integration requires all four on each edit. `Tptp.analyze/2` produces
  them in a single traversal and returns them here; obtaining them through
  `Tptp.Lint.run/2` and `Tptp.Lint.table/1` would require two.

  Input that does not parse still yields an `Analysis`, with a shortened statement
  list and the diagnostics recording the failure, since an editor must render
  markers for a buffer it cannot parse.

  ## Line index

  `line_index` is `nil` until `with_line_index/1` populates it. Converting byte
  offsets to line and column requires one scan of the source, which an analysis
  that is never rendered should not incur and one rendering many positions should
  incur once. `line_column/2` operates in either state, so `with_line_index/1` is
  required only to hoist the scan out of a loop, as
  `Tptp.File.format_diagnostics/1` does.

      analysis = source |> Tptp.analyze() |> Tptp.Analysis.with_line_index()

      for d <- analysis.diagnostics do
        {line, column} = Tptp.Analysis.line_column(analysis, d.span.offset)
        %{line: line, column: column, code: d.code, message: d.message}
      end
  """

  alias Tptp.Lint.Table
  alias Tptp.Query
  alias Tptp.Span

  @enforce_keys [:file, :diagnostics, :table]
  defstruct [:file, :diagnostics, :table, :line_index]

  @typedoc """
  A parsed subject, every diagnostic about it, the symbol table one traversal
  built, and — once `with_line_index/1` has run — a line index over its source.
  """
  @type t :: %__MODULE__{
          file: Tptp.File.t() | Tptp.Unit.t(),
          diagnostics: [Tptp.Diagnostic.t()],
          table: Tptp.Lint.Table.t(),
          line_index: Span.line_index() | nil
        }

  @doc """
  The narrowest dialect that accepts the file.

  Read from the feature set the traversal already recorded, so this costs nothing
  beyond the walk `Tptp.analyze/2` did. Equal to `Tptp.Query.dialect/1`.

      iex> Tptp.Analysis.dialect(Tptp.analyze("cnf(a, axiom, p | ~q)."))
      :cnf
  """
  @spec dialect(t()) :: Tptp.Query.dialect()
  def dialect(%__MODULE__{table: table}) do
    table |> Table.features() |> Query.from_features()
  end

  @doc """
  A copy of the analysis with the line index computed and stored.

  Idempotent — an analysis that already has one is returned unchanged.
  """
  @spec with_line_index(t()) :: t()
  def with_line_index(%__MODULE__{line_index: index} = analysis) when index != nil, do: analysis

  def with_line_index(%__MODULE__{} = analysis) do
    %{analysis | line_index: Span.line_index(source_of(analysis))}
  end

  @doc """
  The one-based line and column of a byte offset.

  Uses the memoised index when `with_line_index/1` has run and a fresh scan
  otherwise, so the answer is the same either way. Offsets resolve against the
  root file of a unit.

      iex> analysis = Tptp.analyze("fof(a, axiom, p).\\nfof(b, axiom, q).")
      iex> Tptp.Analysis.line_column(analysis, 18)
      {2, 1}
  """
  @spec line_column(t(), non_neg_integer()) :: {pos_integer(), pos_integer()}
  def line_column(%__MODULE__{} = analysis, offset) when is_integer(offset) and offset >= 0 do
    index = analysis.line_index || Span.line_index(source_of(analysis))
    Span.line_column(index, offset)
  end

  @spec source_of(t()) :: binary()
  defp source_of(%__MODULE__{file: %Tptp.File{source: source}}), do: source
  defp source_of(%__MODULE__{file: %Tptp.Unit{} = unit}), do: unit.files[unit.root].source

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # An analysis holds the file, the symbol table and optionally a line index over the
    # whole source. Printing the dialect here would be wrong even though it reads well:
    # it is a fold over the table, and `inspect/1` is called from places — a logger, a
    # crash report — that must not start doing work.
    @impl true
    def inspect(analysis, opts) do
      concat([
        "#Tptp.Analysis<",
        to_doc(analysis.file, opts),
        ", ",
        count(length(analysis.diagnostics), "diagnostic"),
        ", ",
        count(map_size(analysis.table.symbols), "symbol"),
        indexed(analysis.line_index),
        ">"
      ])
    end

    defp count(1, noun), do: "1 #{noun}"
    defp count(n, noun), do: "#{n} #{noun}s"

    defp indexed(nil), do: ""
    defp indexed(_index), do: ", line index"
  end
end
