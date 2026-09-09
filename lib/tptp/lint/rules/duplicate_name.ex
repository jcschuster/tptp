defmodule Tptp.Lint.Rules.DuplicateName do
  @moduledoc """
  Two statements sharing a name.

  Names identify formulae, and an inference record refers to its parents by name,
  so a shared name renders a derivation ambiguous and a formula selection
  indeterminate.

  A warning rather than an error, and noisy over parts of the TPTP library: the
  machine-generated ITP axiom sets repeat declarations across files, so a problem
  including thirty of them defines one name thirty times. The finding is correct —
  the derivation is ambiguous — but a caller may reasonably `:suppress` it.

  One diagnostic is emitted per name rather than per occurrence. `related` carries
  the remaining occurrences, so the count is available without a diagnostic for
  each.
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
