defmodule Tptp.Lint.Rules.Parent do
  @moduledoc """
  An inference record naming a parent absent from the unit.

  In a derivation, `inference(rule, [], [a, b])` records that the formula was
  derived from `a` and `b`. An absent parent renders the derivation uncheckable,
  indicating either a dropped statement or an incorrect name.

  A warning, reported only for names occurring in formula-name position. A
  `<source>` is a `<dag_source>`, an `<internal_source>`, an `<external_source>`,
  the literal `unknown`, or a bracketed list of sources, and `<name>` is reachable
  through more than one of these: the rule of an `<inference_record>` and the file
  name of a `<file_source>` are not formula names and are not resolved as such. The
  rule also declines unless the unit names at least one formula, so it reports
  nothing for a problem containing no derivation.

  Before v9.3.1.2 a `<source>` was a `<general_term>`. That expansion is also what
  renders four library files unparseable; see
  [TPTP-DEFECTS.md](TPTP-DEFECTS.md), entry `TPTP-2`.
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
