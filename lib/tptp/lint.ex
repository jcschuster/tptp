defmodule Tptp.Lint do
  @moduledoc """
  The `:==` semantic layer, and the conditions that need more than one statement.

  The grammar accepts far more than TPTP means. `<formula_role> ::= <lower_word>`
  admits `wibble`; `<defined_functor> ::= <atomic_defined_word>` admits `$wibble`;
  `<thf_top_level_type>` admits a rank-2 type that no TPTP tool will read. The `:==`
  rules of the BNF say which of those are actually well formed, and they are
  deliberately not enforced by the parser — a file that trips one of them still has
  a perfectly good CST, and refusing to produce it would make the library useless
  for exactly the malformed input it exists to describe.

      {:ok, file, []} = Tptp.from_string("fof(a, wibble, p).")
      Tptp.Lint.run(file)
      #=> [%Tptp.Diagnostic{code: "TPTP0401", severity: :warning, ...}]

  ## One walk, not one walk per rule

  Ten rules over a 455 MB axiom set is either ten traversals of 27 million nodes or
  one, and the tree does not fit in cache. So `run/2` walks once, offering each node
  to every enabled rule, and accumulates the symbol table and the dialect features
  in the same pass. Rules that need the whole picture run afterwards against the
  table, not against the tree.

  ## Nothing here infers a type

  The symbol table stores a declared type as the unelaborated `Tptp.Node` it was
  written as. No unification, no substitution, no notion that `$i` is a type. Every
  rule that could be tempted — arity consistency above all — is written to be
  syntactic or to decline. See `Tptp.Lint.Rules.Arity` for the one that would
  otherwise be wrong on essentially every TH1 file in the library.

  ## There is no dialect rule, and that is a fact about the BNF

  A construct used in a language that does not have it would be a good thing to
  report, and it cannot happen: the BNF gives each language its own nonterminals,
  so `^` is unreachable from `<tff_formula>`, `!!` from `<fof_formula>`, and a THF
  tuple from anywhere but THF. Every one of those was tried against every statement
  keyword; the grammar refuses all of them at parse time, and a lint rule for it
  would be a rule that can never fire.

  What is left is not a defect but a classification — a `tff` file using `!>` is
  TF1 rather than TF0, and perfectly well formed — and `Tptp.Query.dialect/1`
  answers that constructively from the same traversal.

  ## Severities

  A rule's severity is its own opinion; `:severity` overrides it per code and
  `:only`/`:except` select which rules run at all. Every shipped rule that can fire
  on a conforming TPTP library file does so as a warning, and there is a corpus test
  that will fail if that stops being true.
  """

  alias Tptp.Diagnostic
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
    Tptp.Lint.Rules.Arity
  ]

  @typedoc """
  Options accepted by `run/2`.

    * `:only` — run just these rule modules.
    * `:except` — run everything but these.
    * `:severity` — a map of code to severity, overriding what the rule thinks.
      `severity: %{"TPTP0401" => :error}` promotes an unusual role to a failure.
      Keyed by binary rather than atom on purpose: a diagnostic code is data that
      arrives from a config file, and turning it into an atom to look it up is how
      a library grows an atom-table leak.
    * `:suppress` — diagnostic codes to drop entirely.
  """
  @type option ::
          {:only, [module()]}
          | {:except, [module()]}
          | {:severity, %{binary() => Diagnostic.severity()}}
          | {:suppress, [binary()]}

  @doc """
  Every rule this library ships, in the order they are offered each node.
  """
  @spec rules() :: [module()]
  def rules, do: @rules

  @doc """
  Lint one file.

      iex> {:ok, file, []} = Tptp.from_string("fof(a, axiom, p). fof(a, axiom, q).")
      iex> file |> Tptp.Lint.run() |> Enum.map(& &1.code)
      ["TPTP0503"]
  """
  @spec run(Tptp.File.t(), [option()]) :: [Diagnostic.t()]
  def run(%Tptp.File{} = file, options \\ []) do
    lint(statements(file), %{file.id => file}, options)
  end

  @doc """
  Lint a whole unit, includes expanded.

  A declaration in an axiom file and a use in the problem file are one symbol here,
  which is the point: an undeclared-symbol rule that could not see across an
  `include` would report every typed problem in the library.
  """
  @spec run_unit(Tptp.Unit.t(), [option()]) :: [Diagnostic.t()]
  def run_unit(%Tptp.Unit{} = unit, options \\ []) do
    lint(statements(unit), unit.files, options)
  end

  @doc """
  The symbol table and feature set, without running a single rule.

  The same traversal `run/2` makes, stopping before the opinions. `Tptp.Query` is
  built on this, which is what keeps "one walk" true across both modules rather
  than only within one of them.
  """
  @spec table(Tptp.File.t() | Tptp.Unit.t()) :: Table.t()
  def table(subject) do
    {_found, table} = traverse(statements(subject), files(subject), [])
    Table.finish(table)
  end

  @doc """
  Every statement of a file or unit, paired with the file it came from.
  """
  @spec statements(Tptp.File.t() | Tptp.Unit.t()) :: [{Tptp.Span.file_id(), Statement.t()}]
  def statements(%Tptp.File{} = file), do: Enum.map(file.statements, &{file.id, &1})
  def statements(%Tptp.Unit{} = unit), do: Tptp.Unit.statements(unit)

  defp files(%Tptp.File{} = file), do: %{file.id => file}
  defp files(%Tptp.Unit{} = unit), do: unit.files

  @spec lint([{Tptp.Span.file_id(), Statement.t()}], map(), [option()]) :: [Diagnostic.t()]
  defp lint(statements, files, options) do
    enabled = enabled(options)
    visiting = Enum.filter(enabled, &implements?(&1, :visit, 3))
    reviewing = Enum.filter(enabled, &implements?(&1, :review, 2))

    {found, table} = traverse(statements, files, visiting)
    table = Table.finish(table)

    reviewed =
      Enum.flat_map(reviewing, fn rule ->
        rule.review(table, %Context{file: 0, statement: nil, slot: :formula})
      end)

    (Enum.reverse(found) ++ reviewed)
    |> adjust(options)
    |> Diagnostic.sort()
  end

  @spec traverse([{Tptp.Span.file_id(), Statement.t()}], map(), [module()]) ::
          {[Diagnostic.t()], Table.t()}
  defp traverse(statements, files, visiting) do
    Enum.reduce(statements, {[], %Table{}}, fn {id, statement}, {found, table} ->
      context = %Context{
        file: id,
        statement: statement,
        slot: :formula,
        path: files[id] && files[id].path
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
    table = Tptp.Lint.Collect.observe(node, context, table)

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
