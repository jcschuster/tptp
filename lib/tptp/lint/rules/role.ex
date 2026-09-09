defmodule Tptp.Lint.Rules.Role do
  @moduledoc """
  A formula role outside those named by the `:==` conditions.

  `<formula_role> ::= <lower_word>` in the grammar, so `fof(a, wibble, p).` parses.
  The corresponding `:==` rule is what restricts the role to a fixed set. A warning
  rather than an error: the role is metadata, the formula remains a formula, and a
  consumer concerned only with the terms is unaffected.

  ## Coverage over the TPTP library

  This rule reports nothing on TPTP v9.3.1, and previously reported 354 files.
  Each of those carried a `logic` role, as in `thf(simple_s5, logic, ...)`, by which
  the non-classical extension introduces its semantics. The vendored BNF's `:==`
  rule lists thirteen roles and omits `logic`; the prose of the TPTP language page
  lists fourteen and includes it, several paragraphs above the rule. The role is
  therefore defined by TPTP and absent from the grammar, and a diagnostic reporting
  it attributed a defect in the grammar to the file.

  `Tptp.Bnf.Generator` corrects the vocabulary against the page defining the value,
  under a build check that fails once the BNF lists it. See
  [TPTP-DEFECTS.md](../../../../reports/TPTP-DEFECTS.md), entry `TPTP-1`, for both citations.

  What remains is the rule applied to an actual misspelling: `fof(a, axim, p).` is
  well-formed TPTP and semantically incorrect.
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
  def visit(
        %Node{kind: :formula_role, text: role} = node,
        %Context{slot: :role} = context,
        _table
      )
      when is_binary(role) do
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
