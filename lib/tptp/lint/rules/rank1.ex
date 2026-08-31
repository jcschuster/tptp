defmodule Tptp.Lint.Rules.Rank1 do
  @moduledoc """
  A type quantifier where TPTP only allows rank-1 polymorphism.

  `!>[A: $tType]: ...` binds a type variable, and TPTP allows it only at the very
  outside of a type. TF1's grammar enforces that itself — `<tf1_quantified_type>`
  appears only under `<tff_top_level_type>` — but TH1's does not, because THF makes
  types and terms the same nonterminal and so cannot say where a type ends. So
  `thf(f, type, f: ($i > !>[A: $tType]: A) > $o).` parses, and is rank-2, and no
  TPTP tool will read it.

  This is the one place the library says something about a *type* rather than a
  term, and it stays syntactic: a `!>` or `?*` that has an arrow above it inside the
  same typing is rank-2. No elaboration, no notion of what the type means — just
  where the quantifier sits.

  A warning, because a prover with genuine rank-N support is entitled to its own
  extension.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Node

  @quantifiers [:type_forall, :type_exists]
  @arrows [:thf_mapping_type, :thf_binary_type, :tff_mapping_type]

  @impl true
  def code, do: "TPTP0404"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a type quantifier under an arrow, which is rank-2"

  @impl true
  def visit(%Node{kind: kind} = node, %Context{slot: :formula} = context, _table)
      when kind in @arrows do
    case Enum.filter(node.children, &quantified?/1) do
      [] ->
        []

      offenders ->
        Enum.map(offenders, fn offender ->
          Diagnostic.new(
            code(),
            severity(),
            Context.span(context, offender),
            "a type quantifier inside an arrow makes this type rank-2",
            hint: "TPTP allows `!>` and `?*` only at the outside of a type"
          )
        end)
    end
  end

  def visit(_node, _context, _table), do: []

  defp quantified?(%Node{kind: :thf_quantified_formula, children: [quantification | _rest]}) do
    match?(%Node{children: [%Node{kind: kind} | _]} when kind in @quantifiers, quantification)
  end

  defp quantified?(%Node{kind: kind}) when kind in @quantifiers, do: true
  defp quantified?(%Node{}), do: false
end
