defmodule Tptp.SpacingTest do
  @moduledoc """
  `Tptp.Printer.Spacing` promises that a space is never omitted where its absence
  would combine two tokens into a third. Every pair of fixed spellings is small
  enough to try, so this tries them all, with a few value tokens for company.
  """

  use ExUnit.Case, async: true

  alias Tptp.Lexer
  alias Tptp.Printer.Spacing
  alias Tptp.Token

  @operators Enum.map(Token.operators(), fn {_category, spelling} -> spelling end)
  @keywords Enum.map(
              Token.statement_keywords() ++ Token.source_keywords() ++ Token.dollar_keywords(),
              fn {_category, spelling} -> spelling end
            )
  @values [
    "p",
    "X",
    "'q a'",
    "\"d\"",
    "$i",
    "$$sys",
    "1",
    "0",
    "-2",
    "+3",
    "1/2",
    "1.5",
    "1e5",
    "-1.5e-3",
    "`X",
    "interpretation",
    "domains"
  ]

  test "no pair of tokens merges, divides or changes under the spacing rule" do
    tokens = Enum.uniq(@operators ++ @keywords ++ @values) -- ["."]

    for a <- tokens, b <- tokens do
      joined = IO.iodata_to_binary(Spacing.join([a, b]))
      expected = Enum.take(lexed(a), 1) ++ Enum.take(lexed(b), 1)

      assert Enum.take(lexed(joined), 2) == expected,
             "#{inspect(a)} then #{inspect(b)} was printed as #{inspect(joined)}, " <>
               "which lexes as #{inspect(Enum.take(lexed(joined), 2))}"
    end
  end

  defp lexed(text) do
    source = text <> " ."
    {statements, _comments, _diagnostics} = Lexer.statements(source)

    statements
    |> List.flatten()
    |> Enum.map(fn token -> {elem(token, 0), Lexer.text(token, source)} end)
  end
end
