defmodule Tptp.Lint.Rules.Rank1 do
  @moduledoc """
  A type quantifier in a position admitting only rank-1 polymorphism.

  `!>[A: $tType]: ...` binds a type variable, which TPTP permits only at the
  outermost position of a type. The TF1 grammar enforces this directly, since
  `<tf1_quantified_type>` occurs only beneath `<tff_top_level_type>`. The TH1
  grammar cannot, because THF identifies types with terms and therefore cannot
  delimit a type. Consequently `thf(f, type, f: ($i > !>[A: $tType]: A) > $o).`
  parses, denotes a rank-2 type, and is accepted by no TPTP implementation.

  This is the only rule concerning a type rather than a term, and it remains
  syntactic: a `!>` or `?*` occurring beneath an arrow within the same typing is
  rank-2. No elaboration is performed and the meaning of the type is not
  considered.

  A warning, since an implementation with genuine rank-N support may define its own
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
