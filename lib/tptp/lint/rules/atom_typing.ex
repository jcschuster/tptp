defmodule Tptp.Lint.Rules.AtomTyping do
  @moduledoc """
  A `type`-role statement that does not declare a type, or a typing that is not one.

  `tff(f, type, ...)` exists to declare a symbol, and the grammar cannot insist on
  it: `<tff_formula> ::= <tff_logic_formula> | <tff_atom_typing>` admits either
  under any role. So `tff(a, type, p(X)).` parses and means nothing, and
  `tff(a, axiom, f: $i).` parses and means nothing else.

  Both are warnings. A tool reading the file will ignore the statement either way,
  and refusing to parse it would help nobody.

  ## There is no rule about a nested typing, because there is nothing to report

  A typing below the top of a statement looks like it should be a finding, and it
  cannot be one: the grammar reaches `<thf_atom_typing>` from exactly three places
  and all three are legitimate. `<thf_formula> ::= … | <thf_atom_typing>` is the
  declaration itself; `<thf_let_types> ::= <thf_atom_typing> | [<thf_atom_typing_list>]`
  is a `$let` binding, which is a typing nested inside a formula on purpose; and
  `<thf_atom_typing> ::= (<thf_atom_typing>)` is the same typing in brackets. TFF
  and TCF are the same three.

  A rule that reported nested typings therefore reported `$let` bindings and
  `thf(a, type, (f: $i)).`, and nothing else — it fired eleven times on
  `SYN000^2.p`, all of them wrong. Depth is not what separates a meaningful typing
  from a meaningless one; nothing does, because the grammar admits no meaningless
  one.
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

  def visit(_node, _context, _table), do: []

  defp complain(context, node, message, hint) do
    Diagnostic.new(code(), severity(), Context.span(context, node), message, hint: hint)
  end
end
