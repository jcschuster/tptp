defmodule Tptp.Printer.Spacing do
  @moduledoc """
  Where a space goes between two TPTP tokens.

  Shared by both printers, because they disagree about *which* tokens to emit and
  not at all about how to space them, and two copies of this would drift.

  ## Correctness first, legibility second

  A printer may not change what the tokens are. Two adjacent operators are the way
  that happens: `~` beside `|` is `~|`, a different token. So the default is a
  space, and every rule below removes one only where nothing can munch.

    * Nothing before `)`, `]`, `}`, `,`, `.` or `:`.
    * Nothing after `(`, `[` or `{`.
    * Nothing before an opening bracket that follows a word or a prefix operator,
      so `p(a)` and `![X]:` come out as they went in.
    * Nothing after a prefix operator when a word follows, so `~p` rather than
      `~ p`. Only before a word: `~ |` must keep its space.

  Everywhere else, one space.
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
