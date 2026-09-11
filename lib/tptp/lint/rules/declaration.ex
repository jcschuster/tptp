defmodule Tptp.Lint.Rules.Declaration do
  @moduledoc """
  A symbol used without a declaration, in a dialect that has no default typing.

  Applies to the higher-order dialects only — TH0, TH1, DH0, DH1 and NHF, every
  dialect written with the `thf` keyword. The TPTP language page is explicit that
  the first-order typed dialects are different:

  > A useful feature of TFF is default typing for symbols that are not explicitly
  > declared: predicates default to `($i,...,$i) > $o`, and functions default to
  > `($i,...,$i) > $i`. […] THF does not admit default typing — all symbol types
  > must be declared before use.

  So an undeclared symbol in TFF, TXF, TCF or NXF has a type, and reporting it
  reports legal TPTP. Up to 0.1.0 this rule did, on seventeen library files and 517
  occurrences, every one of which is default-typed and well formed. FOF and CNF
  have no declarations at all.

  What default typing does make an error — a symbol whose later declaration differs
  from its assumed type, or a default-typed symbol applied to an argument that is
  not `$i` — is a question about types, which this library does not answer.

  A unit mixing `thf` with first-order statements is treated as higher-order
  throughout, since the table records which dialects a unit uses and not which
  statement each use sits in.

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
  def describe, do: "a symbol used without a `type` declaration where there is no default typing"

  @impl true
  def review(%Table{} = table, _context) do
    if Table.feature?(table, :thf) do
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
          hint:
            "THF admits no default typing; declare it with `thf(<name>, type, #{name}: <type>)`"
        )
      ]
    end
  end

  defp undeclared({_name, _entry}), do: []
end
