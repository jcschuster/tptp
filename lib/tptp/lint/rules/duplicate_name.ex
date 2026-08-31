defmodule Tptp.Lint.Rules.DuplicateName do
  @moduledoc """
  Two statements with the same name.

  Names identify formulae — an inference record names its parents by them — so two
  statements sharing one makes a derivation ambiguous and a selection unpredictable.

  A warning rather than an error, and genuinely noisy on parts of the TPTP library:
  the machine-generated ITP axiom sets repeat declarations across files, so a
  problem pulling in thirty of them really does define one name thirty times. That
  is a true finding about an ambiguous derivation, not a false one — but it is a
  finding a caller may well want to `:suppress`.

  One diagnostic per name rather than one per repeat. Thirty-two copies of a name
  is one problem, and `related` carries every other occurrence, so the count is
  visible without thirty-one separate lines saying the same thing.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Table

  @impl true
  def code, do: "TPTP0503"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "two statements sharing a name"

  @impl true
  def review(%Table{} = table, _context) do
    Enum.flat_map(table.names, fn
      {_name, [_single]} ->
        []

      {name, [first, second | rest]} ->
        [
          Diagnostic.new(
            code(),
            severity(),
            second,
            "#{inspect(name)} names #{2 + length(rest)} statements",
            hint: "names identify formulae, and an inference record refers to them by name",
            related: [{first, "first named here"} | Enum.map(rest, &{&1, "and here"})]
          )
        ]
    end)
  end
end
