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

  One pair is spelled rather than positional: the `-` of a sub-role closes up on
  both sides, since `interpretation-domains` is how the TPTP writes it and `-`
  occurs in no other production.

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

  The `-` of a sub-role closes up, as the TPTP writes it, unless a number follows:

      iex> Tptp.Printer.Spacing.space?("interpretation", "-")
      false
      iex> Tptp.Printer.Spacing.space?("-", "domains")
      false
      iex> Tptp.Printer.Spacing.space?("-", "1")
      true
  """
  @spec space?(binary(), binary()) :: boolean()
  def space?(_previous, next) when next in @no_space_before, do: false
  def space?(previous, _next) when previous in @openers, do: false

  # `-` is the one token of `<formula_role> ::= <lower_word>-<general_term>`, the
  # only production using it, and `interpretation-domains` is how the TPTP writes
  # one. A digit after it would lex as a signed number and the role would not parse
  # again, so there the space stays; and `@` before it would lex as `@-`, which no
  # tree produces but which the rule below must not produce either.
  # `test/tptp/spacing_test.exs` checks every pair of fixed spellings for this.
  def space?("-", next), do: number_like?(next)
  def space?("@", "-"), do: true
  def space?(_previous, "-"), do: false

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

  defp number_like?(<<sign, rest::binary>>) when sign in [?-, ?+], do: number_like?(rest)
  defp number_like?(<<byte, _rest::binary>>) when byte >= ?0 and byte <= ?9, do: true
  defp number_like?(_token), do: false

  defp word_byte?(byte) when byte >= ?a and byte <= ?z, do: true
  defp word_byte?(byte) when byte >= ?A and byte <= ?Z, do: true
  defp word_byte?(byte) when byte >= ?0 and byte <= ?9, do: true
  defp word_byte?(byte) when byte in [?_, ?', ?", ?$], do: true
  defp word_byte?(_byte), do: false
end
