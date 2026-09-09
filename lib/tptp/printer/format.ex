defmodule Tptp.Printer.Format do
  @moduledoc """
  Rewrites a file's layout without altering its token sequence.

  Backs `mix tptp.format`. The guarantee is stronger than the canonical printer's:
  the tokens are unchanged — not the same structure, but the same tokens, in the
  same order, with the same spellings. Only the white space between them differs.

      iex> Tptp.Printer.Format.to_string("fof( a,axiom,p&q ).  % why\\n")
      "fof(a, axiom, p & q).  % why\\n"

  ## Relation to the canonical printer

  `Tptp.Printer.Canonical` reconstructs output from the tree, so anything the
  grammar admits in more than one form is emitted in the canonical one. That is
  correct for a canonical form and incorrect for a formatter, which must not alter
  a file it was asked to lay out. This module therefore operates on the tokens,
  which are what the source contained.

  ## Comment placement

  Reattaching comments is ordinarily the difficult part of a format-preserving
  printer. Here comments and statements are already ordered by position, so
  merging the two sequences and examining the white space preceding each item
  determines the placement:

    * no newline before a comment indicates that something preceded it on its
      line, so it is a trailing comment and remains one;
    * one newline places it on its own line;
    * two or more preserve the blank line above it, since paragraphing carries
      information.

  This requires a single pass and no position-keyed map.

  ## Unparseable input

  A source containing a lexical error is returned unchanged. A formatter is
  invoked precisely when a file is in an inconsistent state, and rewriting one
  whose tokens are not trustworthy risks discarding content.
  """

  alias Tptp.Lexer
  alias Tptp.Printer.Spacing
  alias Tptp.Splitter

  @doc """
  Reformat TPTP source.
  """
  @spec to_string(binary()) :: binary()
  def to_string(source) when is_binary(source), do: source |> to_iodata() |> IO.iodata_to_binary()

  @doc """
  Reformat TPTP source, as iodata.
  """
  @spec to_iodata(binary()) :: iodata()
  def to_iodata(source) when is_binary(source) do
    {inputs, comments, diagnostics} = Splitter.inputs(source)

    if Enum.any?(diagnostics, &(&1.severity == :error)) do
      source
    else
      inputs |> merge(comments) |> render(source)
    end
  end

  @doc """
  Reformat a file in place, reporting whether it changed.
  """
  @spec format_file(Path.t()) :: {:ok, :changed | :unchanged} | {:error, File.posix()}
  def format_file(path) do
    with {:ok, source} <- File.read(path) do
      formatted = __MODULE__.to_string(source)

      if formatted == source do
        {:ok, :unchanged}
      else
        with :ok <- File.write(path, formatted), do: {:ok, :changed}
      end
    end
  end

  @typedoc "A statement or a comment, with where it starts and ends."
  @type item :: {non_neg_integer(), non_neg_integer(), :statement | :comment, term()}

  @spec merge([Tptp.Input.t()], [Lexer.comment()]) :: [item()]
  defp merge(inputs, comments) do
    statements = Enum.map(inputs, &{&1.offset, &1.offset + &1.length, :statement, &1})

    remarks =
      Enum.map(comments, fn {offset, length, _form, _class} = comment ->
        {offset, offset + length, :comment, comment}
      end)

    Enum.sort(statements ++ remarks)
  end

  @spec render([item()], binary()) :: iodata()
  defp render([], _source), do: ""

  defp render([first | rest], source) do
    [body(first, source) | trailing(rest, elem(first, 1), source)] ++ [?\n]
  end

  defp trailing([], _previous_end, _source), do: []

  defp trailing([{start, finish, kind, payload} | rest], previous_end, source) do
    gap = newlines(source, previous_end, start)

    [
      separator(gap, kind),
      body({start, finish, kind, payload}, source)
      | trailing(rest, finish, source)
    ]
  end

  defp separator(0, :comment), do: "  "
  defp separator(gap, _kind) when gap >= 2, do: "\n\n"
  defp separator(_gap, _kind), do: "\n"

  defp body({_start, _finish, :comment, comment}, source), do: Lexer.comment_text(comment, source)

  defp body({_start, _finish, :statement, input}, source) do
    input.tokens |> Enum.map(&Lexer.text(&1, source)) |> Spacing.join()
  end

  defp newlines(source, from, to) when to > from do
    source |> binary_part(from, to - from) |> count_newlines(0)
  end

  defp newlines(_source, _from, _to), do: 0

  defp count_newlines(<<>>, seen), do: seen
  defp count_newlines(<<?\n, rest::binary>>, seen) when seen >= 2, do: count_newlines(rest, seen)
  defp count_newlines(<<?\n, rest::binary>>, seen), do: count_newlines(rest, seen + 1)
  defp count_newlines(<<_byte, rest::binary>>, seen), do: count_newlines(rest, seen)
end
