defmodule Tptp.Lint.Rules.AtomTyping do
  @moduledoc """
  A `type`-role statement that does not declare a type, or a typing under another
  role.

  `tff(f, type, ...)` declares a symbol, and the grammar cannot require this:
  `<tff_formula> ::= <tff_logic_formula> | <tff_atom_typing>` admits either under
  any role. `tff(a, type, p(X)).` and `tff(a, axiom, f: $i).` therefore both parse
  and neither declares anything.

  Both are warnings. A consumer will disregard the statement in either case, and
  refusing to parse it serves no purpose.

  ## Nested typings are not reported

  A typing below the top of a statement appears reportable and is not. The grammar
  reaches `<thf_atom_typing>` from three positions, each of them legitimate:
  `<thf_formula> ::= … | <thf_atom_typing>` is the declaration itself;
  `<thf_let_types> ::= <thf_atom_typing> | [<thf_atom_typing_list>]` is a `$let`
  binding, which is a typing nested within a formula by construction; and
  `<thf_atom_typing> ::= (<thf_atom_typing>)` is the same typing parenthesised. TFF
  and TCF provide the same three.

  A rule reporting nested typings therefore reports `$let` bindings and
  `thf(a, type, (f: $i)).` and nothing else; it produced eleven findings on
  `SYN000^2.p`, none of them correct. Depth does not separate a meaningful typing
  from a meaningless one, and no criterion does, since the grammar admits none.

  The role is taken from `Tptp.Lint.Context.role/1`, so a sub-role counts as its
  word: `tff(d, type-datatype, nat: $tType).` declares, as the BNF's `datatype`
  sub-role of `type` is meant to.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Node

  @typings [:tff_atom_typing, :thf_atom_typing]

  @impl true
  def code, do: "TPTP0405"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a `type` statement that is not a typing, or a typing that is not a `type`"

  @impl true
  def visit(%Node{} = node, %Context{slot: :formula, depth: 0} = context, _table) do
    role = Context.role(context)
    typing? = node.kind in @typings

    cond do
      role == "type" and not typing? ->
        [
          complain(
            context,
            node,
            "a `type` statement must declare a symbol",
            "expected `name: type`, found a #{node.kind}"
          )
        ]

      typing? and role != "type" ->
        [
          complain(
            context,
            node,
            "a typing must have the `type` role, not #{inspect(role)}",
            "`name: type` declares a symbol and belongs under the `type` role"
          )
        ]

      true ->
        []
    end
  end

  def visit(_node, _context, _table), do: []

  defp complain(context, node, message, hint) do
    Diagnostic.new(code(), severity(), Context.span(context, node), message, hint: hint)
  end
end
