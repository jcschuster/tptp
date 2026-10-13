defmodule Tptp.Lint.Rules.Parent do
  @moduledoc """
  An inference record naming a parent absent from the unit.

  In a derivation, `inference(rule, [], [a, b])` records that the formula was
  derived from `a` and `b`. An absent parent renders the derivation uncheckable,
  indicating either a dropped statement or an incorrect name.

  A warning, reported only for a name in parent position: the `<parents>` of an
  `<inference_record>` or an `<internal_source>`, however deeply those nest
  (`SyntaxBNF-v9.3.1.3` lines 536, 540 and 550). A `<name>` is reachable through a
  `<source>` in other positions, and none of those is a parent. The `<file_info>`
  of a `<file_source>` (line 545) is the formula's name *in the file named*, which
  the language page says may differ from the name the formula now carries, and a
  `<refutation>` under a record's `<useful_info>` names a file as well. The
  `<inference_rule>` and the `<file_name>` are not `<name>`s to the grammar and so
  never reached this rule at all.

  `Tptp.Lint.Collect` therefore takes the names from
  `Tptp.Derivation.Node.parent_nodes/1`, which descends into `<parents>` and
  nothing else, and the two readers of a `<source>` answer alike.

  The literal `unknown` is not reported either: the grammar reads it as a `<name>`
  — the first of `Tptp.Bnf.Generator`'s departures — and a system writing it has
  declined to record a parent rather than named a missing one. The rule also
  declines unless the unit names at least one formula, so it reports nothing for a
  problem containing no derivation.

  Before v9.3.1.2 a `<source>` was a `<general_term>`, which admitted anything at
  all in the position this rule resolves.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Table

  @impl true
  def code, do: "TPTP0504"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "an inference record naming a parent the unit does not contain"

  @impl true
  def review(%Table{} = table, _context) do
    if table.names == %{} do
      []
    else
      Enum.flat_map(table.parents, fn {name, span} ->
        if name == "unknown" or Map.has_key?(table.names, name) do
          []
        else
          [
            Diagnostic.new(
              code(),
              severity(),
              span,
              "#{inspect(name)} is named as a parent but no statement has that name",
              hint: "either the parent is missing or the name is wrong"
            )
          ]
        end
      end)
    end
  end
end
