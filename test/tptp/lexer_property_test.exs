defmodule Tptp.LexerPropertyTest do
  @moduledoc """
  The lexer's invariants, over generated input rather than chosen input.

  The corpus proves the lexer handles well-formed TPTP. These properties prove it
  handles anything at all — which is the harder half, because `Broken.p` is a test
  fixture and the library's defining property is that it survives malformed input
  without raising.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tptp.Lexer

  @printable Enum.concat([?\s..?~, [?\n, ?\t, ?\r]])

  property "never raises, whatever the bytes" do
    check all(source <- binary()) do
      assert {_statements, _comments, _diagnostics} = Lexer.statements(source)
    end
  end

  property "never raises on plausible-looking TPTP fragments" do
    check all(source <- ascii_soup()) do
      assert {_statements, _comments, _diagnostics} = Lexer.statements(source)
    end
  end

  property "spans are ordered, non-overlapping and within the source" do
    check all(source <- ascii_soup()) do
      {statements, comments, _diagnostics} = Lexer.statements(source)

      spans =
        Enum.flat_map(statements, fn tokens ->
          Enum.map(tokens, fn {_category, offset, length} -> {offset, length} end)
        end) ++ Enum.map(comments, fn {offset, length, _form, _class} -> {offset, length} end)

      sorted = Enum.sort(spans)

      Enum.reduce(sorted, 0, fn {offset, length}, position ->
        assert offset >= position, "spans overlap at #{offset}"
        assert offset + length <= byte_size(source), "span runs past the end of the source"
        offset + length
      end)
    end
  end

  property "every byte is a token, a comment, white space, or something we complained about" do
    check all(source <- ascii_soup()) do
      {statements, comments, diagnostics} = Lexer.statements(source)

      spans =
        Enum.flat_map(statements, fn tokens ->
          Enum.map(tokens, fn {_category, offset, length} -> {offset, length} end)
        end) ++ Enum.map(comments, fn {offset, length, _form, _class} -> {offset, length} end)

      complained =
        Enum.reduce(diagnostics, MapSet.new(), fn diagnostic, acc ->
          span = diagnostic.span
          Enum.into(span.offset..(span.offset + max(span.length, 1) - 1)//1, acc)
        end)

      position =
        Enum.reduce(Enum.sort(spans), 0, fn {offset, length}, position ->
          unaccounted(source, position, offset, complained)
          offset + length
        end)

      unaccounted(source, position, byte_size(source), complained)
    end
  end

  property "every token's text is exactly the bytes its span names" do
    check all(source <- ascii_soup()) do
      {statements, _comments, _diagnostics} = Lexer.statements(source)

      for tokens <- statements, {_category, offset, length} = token <- tokens do
        assert Lexer.text(token, source) == binary_part(source, offset, length)
      end
    end
  end

  property "scanning statement by statement agrees with scanning all at once" do
    check all(source <- ascii_soup()) do
      {eager, _comments, _diagnostics} = Lexer.statements(source)
      assert resumed(source, 0, []) == eager
    end
  end

  defp unaccounted(source, from, to, complained) do
    for index <- from..(to - 1)//1 do
      byte = :binary.at(source, index)

      assert byte in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v] or MapSet.member?(complained, index),
             "byte #{inspect(<<byte>>)} at #{index} is neither scanned, white space, " <>
               "nor covered by a diagnostic"
    end
  end

  defp resumed(source, offset, acc) do
    case Lexer.next_statement(source, offset) do
      {:statement, tokens, next, _comments, _diagnostics} ->
        resumed(source, next, [tokens | acc])

      {:eof, _next, _comments, _diagnostics} ->
        Enum.reverse(acc)
    end
  end

  defp ascii_soup do
    gen all(parts <- list_of(fragment(), max_length: 40)) do
      IO.iodata_to_binary(parts)
    end
  end

  defp fragment do
    one_of([
      constant("fof(a,axiom,p)."),
      constant("thf(t,type,f: $i > $o)."),
      constant("cnf(c,axiom,p | ~q)."),
      constant("include('Axioms/SET007+0.ax')."),
      constant("% a comment\n"),
      constant("/* block */"),
      constant("'quoted'"),
      constant("\"distinct\""),
      constant("`Upper"),
      constant("$let"),
      constant("$$system"),
      constant("1.5e-3"),
      constant("-1/2"),
      constant("[.]"),
      constant("<.>"),
      constant("!! @ p"),
      constant("@@+"),
      constant("<=>"),
      constant("."),
      constant("("),
      constant(")"),
      constant("'"),
      constant("\""),
      constant("/*"),
      string(@printable, max_length: 12)
    ])
  end
end
