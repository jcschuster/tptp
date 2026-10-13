defmodule Tptp.Lint.Rules.Role do
  @moduledoc """
  A formula role outside those named by the `:==` conditions.

  `<formula_role> ::= <lower_word>` in the grammar, so `fof(a, wibble, p).` parses.
  The corresponding `:==` rule is what restricts the role to a fixed set. A warning
  rather than an error: the role is metadata, the formula remains a formula, and a
  consumer concerned only with the terms is unaffected.

  ## Coverage over the TPTP library

  This rule reports nothing on TPTP v9.3.1, and reported 354 files under the BNF up
  to v9.3.1.2. Each of those carried a `logic` role, as in
  `thf(simple_s5, logic, ...)`, by which the non-classical extension introduces its
  semantics. That `:==` rule listed thirteen roles and omitted `logic` while the
  prose of the TPTP language page listed fourteen and included it, so a diagnostic
  reporting one of those files attributed a defect in the grammar to the file.
  v9.3.1.3 added the value, and the vocabulary is a transcription of the rule again.

  What remains is the rule applied to an actual misspelling: `fof(a, axim, p).` is
  well-formed TPTP and semantically incorrect.

  ## Sub-roles

  The second alternative of the rule, `<lower_word>-<general_term>`, is checked on
  its `<lower_word>` alone: `interpretation-domains` is an `interpretation` and
  passes, `wibble-[1]` is reported. The `<general_term>` is drawn from no closed
  set — the BNF names `domains`, `mappings` and `datatype` as examples of its use —
  so there is nothing to check it against. The diagnostic spans the whole role.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Bnf.Vocabulary
  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Node

  @impl true
  def code, do: "TPTP0401"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a formula role the TPTP semantic layer does not define"

  @impl true
  def visit(%Node{kind: :formula_role} = node, %Context{slot: :role} = context, _table) do
    role = Context.role(context)

    if Vocabulary.formula_role?(role) do
      []
    else
      [
        Diagnostic.new(
          code(),
          severity(),
          Context.span(context, node),
          "#{inspect(role)} is not a TPTP formula role",
          hint: "expected one of #{Enum.join(Vocabulary.formula_role_values(), ", ")}"
        )
      ]
    end
  end

  def visit(_node, _context, _table), do: []
end
