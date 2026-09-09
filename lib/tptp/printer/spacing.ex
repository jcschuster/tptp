defmodule Tptp.Printer.Spacing do
  @moduledoc """
  Determines the white space between two adjacent tokens.

  Shared by `Tptp.Printer.Canonical` and `Tptp.Printer.Pretty`, so that both apply
  the same rules and the pretty printer's token sequence remains that of the
  canonical printer.

  The rules are positional rather than syntactic, since a token pair is all that is
  available: no space precedes a closing delimiter or a separator, none follows an
  opening delimiter, and none precedes an opening delimiter that follows a word or
  a prefix operator. A single space is emitted elsewhere.

  A space is never omitted where its absence would combine two tokens into a third
  under the lexer's longest-match rule.
  """

  @no_space_before [")", "]", "}", ",", ".", ":"]
  @openers ["(", "[", "{"]
  @prefixes ["!", "?", "^", "~", "!!", "??", "@@+", "@@-", "!>", "?*", "#"]

  @doc """
  Join tokens into iodata, spacing them.

      iex> Tptp.Printer.Spacing.join(["p", "(", "a", ",", "b", ")"]) |> IO.iodata_to_binary()
      "p(a, b)"

      iex> Tptp.Printer.Spacing.join(["~", "p", "|", "q"]) |> IO.iodata_to_binary()
      "~p | q"
  """
  @spec join([binary()]) :: iodata()
  def join([]), do: ""
  def join([first | rest]), do: [first | spaced(first, rest)]

  defp spaced(_previous, []), do: []

  defp spaced(previous, [next | rest]) do
    separator = if space?(previous, next), do: [?\s], else: []
    [separator, next | spaced(next, rest)]
  end

  @doc """
  Whether two adjacent tokens need a space between them.

      iex> Tptp.Printer.Spacing.space?("~", "|")
      true
      iex> Tptp.Printer.Spacing.space?("~", "p")
      false
  """
  @spec space?(binary(), binary()) :: boolean()
  def space?(_previous, next) when next in @no_space_before, do: false
  def space?(previous, _next) when previous in @openers, do: false

  def space?(previous, next) when next in @openers do
    not (word_like?(previous) or previous in @prefixes)
  end

  def space?(previous, next) when previous in @prefixes, do: not starts_word?(next)
  def space?(_previous, _next), do: true

  defp word_like?(token) do
    last = :binary.last(token)

    word_byte?(last) or last in [?), ?], ?}]
  end

  defp starts_word?(token), do: token |> :binary.first() |> word_byte?()

  defp word_byte?(byte) when byte >= ?a and byte <= ?z, do: true
  defp word_byte?(byte) when byte >= ?A and byte <= ?Z, do: true
  defp word_byte?(byte) when byte >= ?0 and byte <= ?9, do: true
  defp word_byte?(byte) when byte in [?_, ?', ?", ?$], do: true
  defp word_byte?(_byte), do: false
end
