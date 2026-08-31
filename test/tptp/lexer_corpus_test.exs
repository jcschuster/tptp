defmodule Tptp.LexerCorpusTest do
  @moduledoc """
  Gate 1: the lexer against the real TPTP library.

  Two properties, both over every file the corpus offers:

    * **Reassembly.** Concatenating every token and comment span with the bytes
      between them reproduces the file exactly. Nothing is dropped, nothing is
      duplicated, and no span is off by a byte. This is a much stronger statement
      than "the token categories look right", and it is cheap.
    * **Silence.** A conforming library file produces no diagnostics at all. If one
      does, either the file is not conforming or our reading of the BNF is wrong,
      and we want to know which.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Lexer
  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: 900_000

  setup_all do
    files = Corpus.files(every: 3)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: files}
  end

  test "every file reassembles from its spans, byte for byte", %{files: files} do
    failures =
      files
      |> stream(&reassembles?/1)
      |> Enum.reject(&(&1 == :ok))

    assert failures == []
  end

  test "no library file produces a lexical diagnostic", %{files: files} do
    noisy =
      files
      |> stream(&diagnostics/1)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "statement counts are stable and non-trivial", %{files: files} do
    total =
      files
      |> stream(fn path ->
        {statements, _comments, _diagnostics} = Lexer.statements(File.read!(path))
        length(statements)
      end)
      |> Enum.sum()

    assert total > 100_000, "expected a substantial corpus, counted #{total} statements"
  end

  defp stream(files, fun) do
    Task.async_stream(files, fun,
      max_concurrency: System.schedulers_online(),
      timeout: 300_000,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp diagnostics(path) do
    {_statements, _comments, diagnostics} = Lexer.statements(File.read!(path))

    if diagnostics == [] do
      :ok
    else
      index = Tptp.Span.line_index(File.read!(path))
      {path, Enum.map(diagnostics, &Tptp.Diagnostic.format(&1, index))}
    end
  end

  defp reassembles?(path) do
    source = File.read!(path)
    {statements, comments, _diagnostics} = Lexer.statements(source)

    spans =
      Enum.flat_map(statements, fn tokens ->
        Enum.map(tokens, fn {_category, offset, length} -> {offset, length} end)
      end) ++ Enum.map(comments, fn {offset, length, _form, _class} -> {offset, length} end)

    {parts, position} =
      spans
      |> Enum.sort()
      |> Enum.reduce({[], 0}, fn {offset, length}, {parts, position} ->
        gap = binary_part(source, position, offset - position)
        {[binary_part(source, offset, length), gap | parts], offset + length}
      end)

    tail = binary_part(source, position, byte_size(source) - position)
    rebuilt = [tail | parts] |> Enum.reverse() |> IO.iodata_to_binary()

    if rebuilt == source, do: :ok, else: {path, :reassembly}
  end
end
