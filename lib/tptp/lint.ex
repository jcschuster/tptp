defmodule Tptp.Lint do
  @moduledoc """
  The `:==` well-formedness conditions, and the conditions requiring more than one
  statement.

  The grammar admits considerably more than the language defines.
  `<formula_role> ::= <lower_word>` admits `wibble`; `<defined_functor> ::=
  <atomic_defined_word>` admits `$wibble`; `<thf_top_level_type>` admits a rank-2
  type that no TPTP implementation accepts. The `:==` rules of the BNF state which
  of these are well formed, and the parser does not enforce them: input violating
  one still yields a usable tree, and refusing to produce it would preclude the
  malformed input this library exists to describe.

      {:ok, file, []} = Tptp.from_string("fof(a, wibble, p).")
      Tptp.Lint.run(file)
      #=> [%Tptp.Diagnostic{code: "TPTP0401", severity: :warning, ...}]

  ## Single traversal

  `run/2` traverses once, offering each node to every enabled rule, and accumulates
  the symbol table and the dialect features in the same pass. Rules requiring the
  complete picture run afterwards against the table rather than the tree. Eight
  rules over a large axiom set would otherwise require eight traversals of a tree
  that does not fit in cache.

  ## No type inference

  The symbol table records a declared type as the unelaborated `Tptp.Node` it was
  written as. No unification or substitution is performed, and `$i` is not
  interpreted as a type. Every rule is either syntactic or declines. See
  `Tptp.Lint.Rules.Rank1`, which determines only whether a `!>` occurs within a
  typing.

  ## Absence of a dialect rule

  Use of a construct in a language that does not provide it is not reportable,
  because it cannot occur. The BNF gives each language its own nonterminals, so `^`
  is unreachable from `<tff_formula>`, `!!` from `<fof_formula>`, and a THF tuple
  from anything but THF. Each was tested against every statement keyword; the
  grammar rejects all of them at parse time, so such a rule could never apply.

  What remains is classification rather than defect — a `tff` file using `!>` is
  TF1 rather than TF0, and well formed — which `Tptp.Query.dialect/1` derives from
  the same traversal.

  ## Severities

  A rule's severity is a default. `:severity` overrides it per code, and
  `:only`/`:except` select the rules that run. No shipped rule reports an error on
  a conforming TPTP library file, and a corpus test enforces this. One rule is
  `:info` rather than `:warning`: `Tptp.Lint.Rules.Conjecture` reports a property of
  the problem rather than a defect in it. The remainder are warnings.

  ## Analyzer interface

  `Tptp.Lint` implements `Tptp.Analyzer` as `:tptp_lint`, applicable to any
  dialect. The callback performs the traversal under the options it is given.
  Consumers requiring only the default rule set should read `analysis.diagnostics`
  from `Tptp.analyze/2` rather than dispatching through
  `Tptp.Analyzer.run_all/3`.
  """

  @behaviour Tptp.Analyzer

  alias Tptp.Diagnostic
  alias Tptp.Lint.Collect
  alias Tptp.Lint.Context
  alias Tptp.Lint.Table
  alias Tptp.Node
  alias Tptp.Statement
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include

  @rules [
    Tptp.Lint.Rules.Role,
    Tptp.Lint.Rules.DefinedWord,
    Tptp.Lint.Rules.AtomTyping,
    Tptp.Lint.Rules.Rank1,
    Tptp.Lint.Rules.Declaration,
    Tptp.Lint.Rules.DuplicateName,
    Tptp.Lint.Rules.Parent,
    Tptp.Lint.Rules.Conjecture
  ]

  @typedoc """
  Options accepted by `run/2`.

    * `:only` — run only these rule modules.
    * `:except` — run every rule but these.
    * `:severity` — a map from code to severity, overriding the rule's default.
      `severity: %{"TPTP0401" => :error}` raises an unrecognised role to an error.
      Keyed by binary rather than atom: a diagnostic code originates in
      configuration, and converting it to an atom for lookup would admit unbounded
      growth of the atom table.
    * `:suppress` — diagnostic codes to discard.
  """
  @type option ::
          {:only, [module()]}
          | {:except, [module()]}
          | {:severity, %{binary() => Diagnostic.severity()}}
          | {:suppress, [binary()]}

  @typedoc """
  The diagnostics a lint pass produced and the table it built, from one traversal.
  """
  @type scan :: {[Diagnostic.t()], Table.t()}

  @doc """
  Returns the shipped rules, in the order each node is offered to them.
  """
  @spec rules() :: [module()]
  def rules, do: @rules

  @impl Tptp.Analyzer
  def id, do: :tptp_lint

  @impl Tptp.Analyzer
  def label, do: "TPTP lint"

  @impl Tptp.Analyzer
  def dialects, do: :any

  @impl Tptp.Analyzer
  def analyze(%Tptp.Analysis{} = analysis, options) do
    analysis.file |> scan(options) |> elem(0)
  end

  @doc """
  Lint one file.

      iex> {:ok, file, []} = Tptp.from_string("fof(a, axiom, p). fof(a, axiom, q).")
      iex> file |> Tptp.Lint.run() |> Enum.map(& &1.code)
      ["TPTP0503"]
  """
  @spec run(Tptp.File.t(), [option()]) :: [Diagnostic.t()]
  def run(%Tptp.File{} = file, options \\ []) do
    file |> scan(options) |> elem(0)
  end

  @doc """
  Lint a whole unit, includes expanded.

  A declaration in an axiom file and a use in the problem file are one symbol here,
  which is the point: an undeclared-symbol rule that could not see across an
  `include` would report every typed problem in the library.
  """
  @spec run_unit(Tptp.Unit.t(), [option()]) :: [Diagnostic.t()]
  def run_unit(%Tptp.Unit{} = unit, options \\ []) do
    unit |> scan(options) |> elem(0)
  end

  @doc """
  One traversal, both halves kept.

  Every enabled rule is offered every node, and the symbol table and dialect
  features accumulate in the same pass; the diagnostics and the finished table
  are returned together rather than one being recomputed later.

  `run/2`, `run_unit/2` and `table/1` are projections of this. Pass `only: []` to
  build the table without applying a rule, as `table/1` does.
  """
  @spec scan(Tptp.File.t() | Tptp.Unit.t(), [option()]) :: scan()
  def scan(subject, options \\ []) do
    whole = match?(%Tptp.Unit{}, subject)
    statements = statements(subject)

    enabled = enabled(options)
    visiting = Enum.filter(enabled, &implements?(&1, :visit, 3))
    reviewing = Enum.filter(enabled, &implements?(&1, :review, 2))

    {found, table} = traverse(statements, files(subject), visiting, whole)
    table = Table.finish(table)

    context = %Context{file: root(statements), statement: nil, slot: :formula, whole: whole}
    reviewed = Enum.flat_map(reviewing, fn rule -> rule.review(table, context) end)

    diagnostics =
      (Enum.reverse(found) ++ reviewed)
      |> adjust(options)
      |> Diagnostic.sort()

    {diagnostics, table}
  end

  @doc """
  The symbol table and feature set, without running a single rule.

  The same traversal `run/2` makes, stopping before the opinions. `Tptp.Query` is
  built on this, which is what maintains "one walk" true across both modules rather
  than only within one of them.
  """
  @spec table(Tptp.File.t() | Tptp.Unit.t()) :: Table.t()
  def table(subject) do
    subject |> scan(only: []) |> elem(1)
  end

  @doc """
  Every statement of a file or unit, paired with the file it came from.
  """
  @spec statements(Tptp.File.t() | Tptp.Unit.t()) :: [{Tptp.Span.file_id(), Statement.t()}]
  def statements(%Tptp.File{} = file), do: Enum.map(file.statements, &{file.id, &1})
  def statements(%Tptp.Unit{} = unit), do: Tptp.Unit.statements(unit)

  defp files(%Tptp.File{} = file), do: %{file.id => file}
  defp files(%Tptp.Unit{} = unit), do: unit.files

  defp root([{id, _statement} | _rest]), do: id
  defp root([]), do: 0

  @spec traverse([{Tptp.Span.file_id(), Statement.t()}], map(), [module()], boolean()) ::
          {[Diagnostic.t()], Table.t()}
  defp traverse(statements, files, visiting, whole) do
    Enum.reduce(statements, {[], %Table{}}, fn {id, statement}, {found, table} ->
      context = %Context{
        file: id,
        statement: statement,
        slot: :formula,
        path: files[id] && files[id].path,
        whole: whole
      }

      walk_statement(statement, context, visiting, found, table)
    end)
  end

  defp walk_statement(statement, context, visiting, found, table) do
    statement
    |> slots()
    |> Enum.reduce({found, table}, fn {slot, root}, acc ->
      walk(root, %{context | slot: slot}, visiting, acc)
    end)
  end

  defp slots(%Annotated{} = statement) do
    [name: statement.name, role: statement.role, formula: statement.formula] ++
      if(statement.source, do: [source: statement.source], else: []) ++
      if(statement.info, do: [info: statement.info], else: [])
  end

  defp slots(%Include{} = statement) do
    [file_name: statement.file_name] ++
      if(statement.selection, do: [selection: statement.selection], else: [])
  end

  defp walk(%Node{} = node, context, visiting, {found, table}) do
    table = Collect.observe(node, context, table)

    found =
      Enum.reduce(visiting, found, fn rule, acc ->
        case rule.visit(node, context, table) do
          [] -> acc
          diagnostics -> Enum.reverse(diagnostics, acc)
        end
      end)

    deeper = %{context | depth: context.depth + 1}
    Enum.reduce(node.children, {found, table}, &walk(&1, deeper, visiting, &2))
  end

  @spec implements?(module(), atom(), arity()) :: boolean()
  defp implements?(rule, name, arity) do
    Code.ensure_loaded?(rule) and function_exported?(rule, name, arity)
  end

  defp enabled(options) do
    case Keyword.get(options, :only) do
      nil -> @rules -- Keyword.get(options, :except, [])
      only -> only
    end
  end

  defp adjust(diagnostics, options) do
    severities = Keyword.get(options, :severity, %{})
    suppressed = Keyword.get(options, :suppress, [])

    diagnostics
    |> Enum.reject(&(&1.code in suppressed))
    |> Enum.map(fn diagnostic ->
      case Map.fetch(severities, diagnostic.code) do
        {:ok, severity} -> %{diagnostic | severity: severity}
        :error -> diagnostic
      end
    end)
  end
end
