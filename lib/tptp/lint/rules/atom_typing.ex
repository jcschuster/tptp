defmodule Tptp.Lint.Rules.AtomTyping do
  @moduledoc """
  A `type`-role statement that does not declare a type, or a typing that is not one.

  `tff(f, type, ...)` exists to declare a symbol, and the grammar cannot insist on
  it: `<tff_formula> ::= <tff_logic_formula> | <tff_atom_typing>` admits either
  under any role. So `tff(a, type, p(X)).` parses and means nothing, and
  `tff(a, axiom, f: $i).` parses and means nothing else.

  Both are warnings. A tool reading the file will ignore the statement either way,
  and refusing to parse it would help nobody.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Node
  alias Tptp.Statement.Annotated

  @typings [:tff_atom_typing, :thf_atom_typing]

  @impl true
  def code, do: "TPTP0405"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a `type` statement that is not a typing, or a typing that is not a `type`"

  @impl true
  def visit(%Node{} = node, %Context{slot: :formula, depth: 0} = context, _table) do
    case context.statement do
      %Annotated{role: %Node{text: "type"}} when node.kind not in @typings ->
        [
          complain(
            context,
            node,
            "a `type` statement must declare a symbol",
            "expected `name: type`, found a #{node.kind}"
          )
        ]

      %Annotated{role: %Node{text: role}} when node.kind in @typings and role != "type" ->
        [
          complain(
            context,
            node,
            "a typing must have the `type` role, not #{inspect(role)}",
            "`name: type` declares a symbol and belongs under the `type` role"
          )
        ]

      _otherwise ->
        []
    end
  end

  def visit(%Node{kind: kind} = node, %Context{slot: :formula} = context, _table)
      when kind in @typings do
    if context.depth == 0 do
      []
    else
      [
        complain(
          context,
          node,
          "a typing is only meaningful at the top of a statement",
          "`name: type` nested inside a formula declares nothing"
        )
      ]
    end
  end

  def visit(_node, _context, _table), do: []

  defp complain(context, node, message, hint) do
    Diagnostic.new(code(), severity(), Context.span(context, node), message, hint: hint)
  end
end
