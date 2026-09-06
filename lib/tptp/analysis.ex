defmodule Tptp.Analysis do
  @moduledoc """
  Everything the editor path asks for on one keystroke, from one traversal.

  A debounced edit wants the file, every diagnostic, the symbol table and the
  dialect together. `Tptp.analyze/2` builds all of it in a single walk and returns
  it here; `Tptp.Lint.run/2` and `Tptp.Lint.table/1` would have walked twice.

  A file that does not parse still comes back as an `Analysis` — with a short
  statement list and the diagnostics that say why — because an editor has to
  render markers for a buffer it cannot parse.

  ## The line index is opt-in

  `line_index` is `nil` until `with_line_index/1` fills it. Turning byte offsets
  into line and column costs one scan of the source; an analysis that is never
  rendered should not pay for it, and one that renders thirty markers should pay
  once. `line_column/2` works either way, so the only reason to call
  `with_line_index/1` is to hoist that scan out of a loop — the move
  `Tptp.File.format_diagnostics/1` already makes.

      analysis = source |> Tptp.analyze() |> Tptp.Analysis.with_line_index()

      for d <- analysis.diagnostics do
        {line, column} = Tptp.Analysis.line_column(analysis, d.span.offset)
        %{line: line, column: column, code: d.code, message: d.message}
      end
  """

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
    table |> Tptp.Lint.Table.features() |> Tptp.Query.from_features()
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
end
