defmodule Tptp.Lint.Rules.Parent do
  @moduledoc """
  An inference record naming a parent that is not in the unit.

  A derivation's `inference(rule, [], [a, b])` says this formula came from `a` and
  `b`. If `a` is nowhere, the derivation cannot be checked and probably cannot be
  read — either a statement was dropped or the name is wrong.

  A warning, and only reported for names that look like formula names: a `<source>`
  can also be a `<file_source>`, a `<theory>` or an arbitrary `<general_term>`, and
  the grammar reaches `<name>` through several of them. The rule stays quiet unless
  the unit names at least one formula, so it says nothing at all about a problem
  file that has no derivation in it.
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
        if Map.has_key?(table.names, name) do
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
