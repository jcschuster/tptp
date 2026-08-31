defmodule Tptp.Printer.Format do
  @moduledoc """
  Rewrites a file's layout without touching a single token.

  `mix tptp.format` is what this is for. The guarantee is stronger than the
  canonical printer's and easier to state: **the token sequence is unchanged**. Not
  the same shape — the same tokens, in the same order, spelled the same way. Only
  the white space between them moves.

      iex> Tptp.Printer.Format.to_string("fof( a,axiom,p&q ).  % why\\n")
      "fof(a, axiom, p & q).  % why\\n"

  ## Why this is not the canonical printer with comments bolted on

  `Tptp.Printer.Canonical` rebuilds from the CST, so anything the grammar can spell
  two ways comes back in the canonical one. Right for a canonical form, wrong for a
  formatter, which must not change a file it was asked to tidy. So this works from
  the *tokens*, which are exactly what the source said.

  ## Comments need no attachment map

  Re-attaching comments is usually the hard part of a format-preserving printer,
  and here it is not, because comments and statements arrive already sorted by
  offset. Merging the two sequences and looking at the white space each item was
  preceded by answers the question directly:

    * no newline before a comment means something was on its line already, so it is
      a trailing comment and stays there;
    * one newline means its own line;
    * two or more means a blank line above, which is kept — a file's paragraphing
      is information, and collapsing it is not tidying.

  One pass, no map keyed by position, and nothing to keep in step.

  ## It declines rather than mangles

  A source with a lexical error is returned unchanged. A formatter is reached for
  precisely when a file is in a bad state, and rewriting one whose tokens are not
  trustworthy is how a formatter loses someone's work.
  """

  alias Tptp.Lexer
  alias Tptp.Splitter
  alias Tptp.Printer.Spacing

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
