defmodule Tptp.Lint.Rules.Arity do
  @moduledoc """
  A symbol applied at two different arities.

  In CNF and FOF a symbol's arity is fixed by its first use, so `p(a)` and
  `p(a, b)` in one problem is a mistake — usually a dropped argument, occasionally
  two symbols that were meant to have different names.

  ## Why this rule declines in the higher-order dialects

  It would be wrong there, on essentially every TH1 file in the library.

  A polymorphic symbol is applied to its type arguments and then to its value
  arguments, all through the same apply spine. `f @ $i @ a` and `f @ $o @ b @ c`
  are the same `f` at spine lengths two and three, and both are correct.
  Instantiating a type variable *raises* arity — for a scheme `t`, an instance
  `t[b]` has `ar(t[b]) >= ar(t)` — so a symbol whose type contains a `!>` will be
  applied at as many arities as it has instances. Partial application in THF makes
  the same point without any polymorphism at all: `f @ a` is a perfectly good term
  whether or not `f` takes two arguments.

  So the rule fires only for symbols seen in the functional form — `f(a, b)` — and
  never for an apply spine, and it declines outright for any symbol whose declared
  type mentions a type quantifier. That is a syntactic test on the declared type
  node, not an elaboration of it: the question is "does a `!>` appear in here", and
  `Tptp.Lint` answers no other kind.

  The table records every arity it saw regardless; declining to judge is not the
  same as declining to look, and a consumer that knows more can read
  `Tptp.Lint.Table` and decide for itself.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Table
  alias Tptp.Node

  @quantifiers [:type_forall, :type_exists]

  @impl true
  def code, do: "TPTP0505"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a symbol applied at two arities in a first-order dialect"

  @impl true
  def review(%Table{} = table, _context) do
    if Table.feature?(table, :higher_order) do
      []
    else
      Enum.flat_map(table.symbols, &inconsistent(&1, table))
    end
  end

  defp inconsistent({name, entry}, _table) do
    arities = MapSet.to_list(entry.arities)

    cond do
      length(arities) < 2 -> []
      polymorphic?(entry.declared_as) -> []
      entry.used_at == [] -> []
      true -> [complain(name, entry, Enum.sort(arities))]
    end
  end

  defp complain(name, entry, arities) do
    [first | rest] = entry.used_at

    Diagnostic.new(
      code(),
      severity(),
      List.last(rest) || first,
      "#{inspect(name)} is applied at #{Enum.join(arities, " and ")} arguments",
      hint: "a first-order symbol has one arity",
      related: [{first, "first used here"}]
    )
  end

  @doc """
  Whether a declared type mentions a type quantifier, and so may legitimately be
  applied at more than one arity.

  Syntactic, deliberately: it looks for a `!>` or `?*` node and nothing else.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("thf(d, type, g: !>[A: $tType]: (A > A)).")
      iex> [_subject, type] = statement.formula.children
      iex> Tptp.Lint.Rules.Arity.polymorphic?(type)
      true
  """
  @spec polymorphic?(Node.t() | nil) :: boolean()
  def polymorphic?(nil), do: false

  def polymorphic?(%Node{} = node) do
    Enum.any?(Node.walk(node), &(&1.kind in @quantifiers))
  end
end
