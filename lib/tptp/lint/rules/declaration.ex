defmodule Tptp.Lint.Rules.Declaration do
  @moduledoc """
  A symbol used without a declaration.

  Applies to the typed dialects only. TFF, TCF and THF require every symbol to be
  declared by a `type` statement before use; FOF and CNF have no declarations, so
  applying the rule to them would report every symbol they contain.

  ## Requires a unit

  A problem commonly declares nothing and includes an axiom file that declares
  everything. Analysing the problem alone reports every symbol as undeclared, so
  `Tptp.Lint.run_unit/2` is the call under which this rule can be correct.
  Analysing a `Tptp.File` whose declarations are supplied by an include will be
  noisy, and correctly so: the file does not itself declare the symbols it uses.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Table

  @impl true
  def code, do: "TPTP0501"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a symbol used in a typed dialect without a `type` declaration"

  @impl true
  def review(%Table{} = table, _context) do
    if Table.feature?(table, :typed) do
      Enum.flat_map(table.symbols, &undeclared/1)
    else
      []
    end
  end

  defp undeclared({name, %{declared_at: nil, used_at: [first | _rest]}}) do
    if String.starts_with?(name, "$") do
      []
    else
      [
        Diagnostic.new(
          code(),
          severity(),
          first,
          "#{inspect(name)} is used but never declared",
          hint: "a typed dialect wants `<name>, type, #{name}: <type>` first"
        )
      ]
    end
  end

  defp undeclared({_name, _entry}), do: []
end
