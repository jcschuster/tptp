defmodule Tptp.Lint.Rules.Conjecture do
  @moduledoc """
  A file stating no conjecture, or more than one.

  A TPTP problem states a set of axioms and a single conjecture. Both departures
  are well-formed input and neither is a defect, which is why this is the library's
  only `:info` rule. Both nonetheless determine what a consumer may do with the
  file, and any consumer dispatching problems to provers must establish the count
  for itself.

  ## No conjecture

  A file without a conjecture states no proof obligation: it is a satisfiability
  problem, an axiom set, or a problem whose conjecture has been removed. A prover
  given one reports `Satisfiable` rather than `Theorem`, which a pipeline expecting
  a proof obligation may misinterpret as failure.

  This half of the rule requires the whole problem, so it applies under
  `Tptp.Lint.run_unit/2` and declines under `Tptp.Lint.run/2`. A file that includes
  its conjecture rather than stating it does not lack one, and a rule unable to
  resolve `include` would report that it did. This is the purpose of the `whole`
  flag on `Tptp.Lint.Context`.

  It still applies to an axiom set analysed as a unit, where the finding is
  self-evident. That reading is correct — the file states no obligation — and the
  diagnostic is `:info` and suppressible by code so that a caller which knows what
  it holds can discard it.

  ## Multiple conjectures

  Two `conjecture` statements leave the problem ambiguous: a prover will select one,
  and the selection is not determined by the file.

  `negated_conjecture` is counted separately and never triggers this rule, since a
  single conjecture negated into clause normal form yields many
  `negated_conjecture` clauses. Counting those would report most of the CNF portion
  of the TPTP library.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Lint.Table
  alias Tptp.Span

  @impl true
  def code, do: "TPTP0506"

  @impl true
  def severity, do: :info

  @impl true
  def describe, do: "a problem with no conjecture, or with more than one"

  @impl true
  def review(%Table{} = table, %Context{} = context) do
    {stated, negated} = Enum.split_with(table.conjectures, &match?({:conjecture, _span}, &1))

    cond do
      stated == [] and negated == [] -> none(table, context)
      match?([_first, _second | _rest], stated) -> several(stated)
      true -> []
    end
  end

  defp none(%Table{names: names}, _context) when map_size(names) == 0, do: []

  defp none(_table, %Context{whole: false}), do: []

  defp none(_table, %Context{file: file}) do
    [
      Diagnostic.new(
        code(),
        severity(),
        Span.new(file, 0, 0),
        "no conjecture: this problem states things and asks nothing",
        hint: "an axiom set legitimately has none; a problem that meant to ask something does not"
      )
    ]
  end

  defp several([{_first_form, first}, {_second_form, second} | rest]) do
    [
      Diagnostic.new(
        code(),
        severity(),
        second,
        "#{2 + length(rest)} conjectures; a problem asks one question",
        hint: "a prover will prove one of them, and which one is its choice rather than yours",
        related: [
          {first, "first conjecture here"} | Enum.map(rest, fn {_f, s} -> {s, "and here"} end)
        ]
      )
    ]
  end
end
