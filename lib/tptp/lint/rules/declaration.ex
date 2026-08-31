defmodule Tptp.Lint.Rules.Declaration do
  @moduledoc """
  A symbol used without a declaration, or declared twice.

  Only in the typed dialects. TFF, TCF and THF require every symbol to be declared
  by a `type` statement before use; FOF and CNF have no declarations at all, so
  running this over them would report every symbol in half the library.

  ## Why this needs the unit, not the file

  A problem declares nothing and includes an axiom file that declares everything.
  Linting the problem alone would report every one of its symbols as undeclared, so
  `Tptp.Lint.run_unit/2` is the call that gives this rule a chance to be right, and
  running it on a bare `Tptp.File` that includes its declarations will be noisy.
  That is not a bug to paper over: the file really does not say where `f` came from.
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
