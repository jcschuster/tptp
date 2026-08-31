defmodule Tptp.PrinterCorpusTest do
  @moduledoc """
  Gate 7: the printers against the real TPTP library.

  The plan calls this the one that has to be green before any consumer rebases, and
  it is, because a printer is the only stage that can quietly change what a file
  means. Four properties, over every file the corpus offers:

    * **The fixpoint.** `from_string(print(tree))` has the same shape as `tree`,
      statement for statement. Shape is `Tptp.Node.shape/1` — kinds, texts and
      structure — because every offset moves when you reprint.
    * **Stability.** Printing the reparsed tree gives byte-identical output, so the
      canonical form really is one form and not a sequence that keeps drifting.
    * **Token preservation.** The format-preserving printer emits exactly the tokens
      it read, in order, spelled the same. Not a shape comparison — the tokens.
    * **Coverage.** Every node kind the corpus produces has a generated shape. A
      kind without one falls back to concatenating its children, which loses the
      syntax around them, so this is what stops that being silent.
    * **The pretty printer moves nothing but white space.** At three widths, its
      token sequence is the canonical printer's token sequence — and at a width
      nothing can exceed, its output is byte-identical to the canonical form. The
      second is what pins the first down: without it, both printers could be wrong
      the same way.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Lexer
  alias Tptp.Node
  alias Tptp.Printer.Canonical
  alias Tptp.Printer.Format
  alias Tptp.Printer.Pretty
  alias Tptp.Printer.Shapes
  alias Tptp.Statement
  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: 900_000

  setup_all do
    files = Corpus.files(every: 3, max_bytes: 2_000_000)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: files}
  end

  test "every statement survives a canonical print and reparse", %{files: files} do
    outcomes = stream(files, &fixpoint/1)
    broken = Enum.reject(outcomes, &match?({:ok, _count}, &1))
    printed = for {:ok, count} <- outcomes, reduce: 0, do: (total -> total + count)

    IO.puts("\n  #{printed} statements round-tripped through the canonical printer")

    assert broken == []
  end

  test "the format-preserving printer changes no token", %{files: files} do
    changed =
      files
      |> Enum.take_every(3)
      |> stream(&preserved/1)
      |> Enum.reject(&(&1 == :ok))

    assert changed == []
  end

  test "every node kind the library produces has a shape", %{files: files} do
    unshaped =
      files
      |> Enum.take_every(3)
      |> stream(&unshaped/1)
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)
      |> Enum.sort()

    assert unshaped == []
  end

  test "the pretty printer only moves white space", %{files: files} do
    broken =
      files
      |> Enum.take_every(3)
      |> stream(&laid_out/1)
      |> Enum.reject(&(&1 == :ok))

    assert broken == []
  end

  defp laid_out(path) do
    source = File.read!(path)
    {:ok, file, []} = Tptp.from_string(source)

    Enum.find_value(file.statements, :ok, fn statement ->
      canonical = Canonical.tokens(statement)

      cond do
        Pretty.to_string(statement, width: 1_000_000) != Canonical.to_string(statement) ->
          {path, :not_canonical_when_flat, Statement.text(statement, source)}

        Enum.any?([20, 60, 100], &(tokens(Pretty.to_string(statement, width: &1)) != canonical)) ->
          {path, :tokens_changed, Statement.text(statement, source)}

        true ->
          nil
      end
    end)
  end

  defp fixpoint(path) do
    source = File.read!(path)
    {:ok, file, []} = Tptp.from_string(source)
    printed = Canonical.to_string(file)

    case Tptp.from_string(printed) do
      {:ok, again, []} ->
        compare(file, again, printed, path)

      {:ok, _again, diagnostics} ->
        {path, :reparse, diagnostics |> Enum.map(& &1.message) |> Enum.take(2)}
    end
  end

  defp compare(file, again, printed, path) do
    cond do
      length(again.statements) != length(file.statements) ->
        {path, :count, {length(file.statements), length(again.statements)}}

      Canonical.to_string(again) != printed ->
        {path, :unstable, nil}

      true ->
        differing =
          file.statements
          |> Enum.zip(again.statements)
          |> Enum.find(fn {one, two} -> shape(one) != shape(two) end)

        case differing do
          nil -> {:ok, length(file.statements)}
          {one, _two} -> {path, :shape, Statement.text(one, file.source)}
        end
    end
  end

  defp shape(statement) do
    {statement.__struct__, statement |> Statement.roots() |> Enum.map(&Node.shape/1)}
  end

  defp preserved(path) do
    source = File.read!(path)
    formatted = Format.to_string(source)

    if tokens(source) == tokens(formatted) do
      :ok
    else
      {path, :tokens_changed}
    end
  end

  defp tokens(source) do
    {statements, _comments, _diagnostics} = Lexer.statements(source)

    statements |> List.flatten() |> Enum.map(&Lexer.text(&1, source))
  end

  defp unshaped(path) do
    source = File.read!(path)
    {:ok, file, []} = Tptp.from_string(source)

    for statement <- file.statements,
        root <- Statement.roots(statement),
        node <- Node.walk(root),
        node.children != [] or (node.text == nil and Tptp.Token.spelling(node.kind) == nil),
        Shapes.shape(node.kind, length(node.children)) == nil,
        into: MapSet.new(),
        do: {node.kind, length(node.children)}
  end

  defp stream(files, fun) do
    files
    |> Task.async_stream(fun,
      max_concurrency: System.schedulers_online(),
      timeout: 900_000,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
