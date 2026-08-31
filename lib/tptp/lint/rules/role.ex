defmodule Tptp.Lint.Rules.Role do
  @moduledoc """
  A formula role outside the thirteen the `:==` layer names.

  `<formula_role> ::= <lower_word>` in the grammar, so `fof(a, wibble, p).` parses.
  `<formula_role> :== axiom | hypothesis | ...` is what says it should not have.
  A warning rather than an error: the role is metadata, the formula is still a
  formula, and a consumer that only cares about the terms is unaffected.

  It does find real things. Across the TPTP library it fires exactly once, on
  `PHI003^8.p`, which writes `thf(simple_s5, logic, ...)` — the non-classical
  extension uses a `logic` role that the vendored BNF's `:==` list does not
  mention. That is a gap between the grammar version and the library rather than a
  mistake in the file, and reporting it is the right thing for a warning to do.
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
