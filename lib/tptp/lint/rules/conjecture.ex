defmodule Tptp.Lint.Rules.Conjecture do
  @moduledoc """
  Nothing is being asked, or more than one thing is.

  A TPTP problem states axioms and one conjecture. Both departures are legal input
  and neither is a defect, which is why this is the library's only `:info` rule —
  but both change what a consumer may do with the file, and every consumer that
  routes problems to provers ends up counting conjectures for itself. Counting them
  once, here, is cheaper than counting them in every consumer and getting the two
  spellings wrong.

  ## Zero

  A file with no conjecture asks nothing: it is a satisfiability problem, an axiom
  set, or a problem whose conjecture was dropped. A prover given one will report
  `Satisfiable` rather than `Theorem`, and a pipeline that expected a proof
  obligation will read that as a failure rather than as the answer to the question
  it actually asked.

  This half of the rule needs the whole problem, so it reports under
  `Tptp.Lint.run_unit/2` and declines under `Tptp.Lint.run/2`. A file that includes
  its conjecture rather than stating it does not lack one, and a rule that could
  not see through an `include` would say it did. That is `Tptp.Lint.Context`'s
  `whole` flag, and this is the rule it exists for.

  It still fires on an axiom set linted as a unit, where it says something obvious.
  That is the honest reading — the file really does ask nothing — and it is `:info`
  and suppressible by code precisely so that a caller who knows what it is holding
  can say so.

  ## More than one

  Two `conjecture` statements make the problem ambiguous: a prover will take one,
  and which one is its business rather than the file's.

  `negated_conjecture` is counted separately and never triggers this, because one
  conjecture negated into clause normal form *is* many `negated_conjecture` clauses.
  Counting those would report most of the CNF half of the TPTP library.
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
