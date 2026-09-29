defmodule Tptp.Bnf.Szs do
  @moduledoc """
  Translates the vendored `SZSOntology.bnf` into `Tptp.Szs.Ontology`.

  The file is the TPTP World's source of truth for the three SZS ontologies. Each
  value is a nonterminal whose rule names the value's own terminal and the values
  directly beneath it:

      <Theorem> ::= Theorem | <SatisfiableAxiomsTheorem> | <ContradictoryAxioms>

  That is the whole of what the file states, and the whole of what is generated
  from it: the values, the `isa` edges between them, and the three roots that
  `<SZS>` lists. Everything else the generated module offers — ancestors,
  descendants, the ontology a value belongs to — is the closure of those edges,
  computed here so that the module can answer with literal lists.

  ## Shape of the file

  Every rule but two has exactly one terminal alternative, spelled as the rule's own
  name, and any number of single-nonterminal alternatives. The two exceptions are
  the root, `<SZS> ::= <Success> | <NoSuccess> | <Data>`, which has no terminal, and
  `<inference_status_value>`, which is a list of lower-case mnemonics with no
  nonterminal and is the rule `Tptp.Bnf.Generator.vocabularies/2` takes
  `<status_value>` from. One terminal takes arguments:
  `<Assumed> ::= Assumed(<Unknown>,<Success>)`. The references inside the
  parentheses are the arguments' domains, not `isa` edges, and are exposed as
  `arguments/1`.

  A file that departs from this shape fails generation with the rule named. The
  checks are those `SZS_BNF_Check.thy` performs upstream — one terminal per rule,
  every reference defined, acyclic, every value beneath exactly one root — so a
  BNF that builds there generates here.

  ## Atoms

  A value's atom is its name in snake case: `<CounterSatisfiable>` becomes
  `:counter_satisfiable`, `<OSError>` becomes `:os_error`. The conversion is
  `Macro.underscore/1`, applied at generation time and rendered as a literal, so
  the generated module creates no atom at runtime.
  """

  alias Tptp.Bnf
  alias Tptp.Bnf.Rule

  @root "SZS"
  @mnemonics "inference_status_value"

  @typedoc "One value as read from its rule."
  @type entry :: %{
          name: binary(),
          atom: binary(),
          children: [binary()],
          arguments: [binary()],
          line: pos_integer()
        }

  @typedoc "The ontology as read: entries in source order, plus the roots and the mnemonic list."
  @type ontology :: %{
          entries: [entry()],
          roots: [binary()],
          mnemonics: [binary()]
        }

  @typedoc "Statistics for the task to report."
  @type report :: %{
          values: non_neg_integer(),
          edges: non_neg_integer(),
          roots: [binary()],
          mnemonics: non_neg_integer()
        }

  @doc """
  Read the ontology out of the BNF and check its shape.

  Raises `ArgumentError` naming the offending rule when the file is not the shape
  described in the module documentation.
  """
  @spec read!(Path.t()) :: ontology()
  def read!(szs_path) do
    rules = szs_path |> Bnf.read!() |> Bnf.merge_alternatives()
    by_name = Map.new(rules, &{&1.lhs, &1})

    root = Map.fetch!(by_name, @root)
    roots = Enum.map(root.alternatives, &single_ref!(&1, root))

    mnemonics =
      by_name
      |> Map.fetch!(@mnemonics)
      |> Map.fetch!(:alternatives)
      |> Enum.map(&single_literal!(&1, Map.fetch!(by_name, @mnemonics)))

    entries =
      rules
      |> Enum.reject(&(&1.lhs in [@root, @mnemonics]))
      |> Enum.map(&entry!/1)

    check!(entries, roots)

    %{entries: entries, roots: roots, mnemonics: mnemonics}
  end

  @doc """
  Build the `Tptp.Szs.Ontology` source and a report from the BNF.
  """
  @spec generate(Path.t()) :: {binary(), report()}
  def generate(szs_path) do
    ontology = read!(szs_path)
    %{entries: entries, roots: roots} = ontology

    by_name = Map.new(entries, &{&1.name, &1})
    order = Enum.map(entries, & &1.name)
    parents = parents(entries)
    ancestors = closure(by_name, parents, order)
    descendants = closure(by_name, Map.new(entries, &{&1.name, &1.children}), order)
    home = Map.new(entries, &{&1.name, home!(&1.name, roots, ancestors)})

    source =
      render(%{
        path: szs_path,
        entries: entries,
        roots: roots,
        by_name: by_name,
        parents: parents,
        ancestors: ancestors,
        descendants: descendants,
        home: home
      })

    report = %{
      values: length(entries),
      edges: entries |> Enum.map(&length(&1.children)) |> Enum.sum(),
      roots: roots,
      mnemonics: length(ontology.mnemonics)
    }

    {source, report}
  end

  defp entry!(%Rule{} = rule) do
    {terminals, refs} =
      Enum.split_with(rule.alternatives, fn
        [{:ref, _name}] -> false
        _other -> true
      end)

    case terminals do
      [terminal] ->
        %{
          name: rule.lhs,
          atom: atom!(rule),
          children: Enum.map(refs, fn [{:ref, name}] -> name end),
          arguments: arguments!(terminal, rule),
          line: rule.line
        }

      _other ->
        raise ArgumentError,
              "<#{rule.lhs}> on line #{rule.line} of the SZS BNF has #{length(terminals)} " <>
                "terminal alternatives; expected exactly one, spelled #{rule.lhs}"
    end
  end

  defp arguments!([{:literal, word}], %Rule{lhs: word}), do: []

  defp arguments!([{:literal, head} | rest], %Rule{lhs: lhs} = rule) when head == lhs <> "(" do
    case Enum.reverse(rest) do
      [{:literal, ")"} | inner] ->
        inner
        |> Enum.reverse()
        |> Enum.reject(&(&1 == {:literal, ","}))
        |> Enum.map(&single_ref!([&1], rule))

      _other ->
        malformed!(rule)
    end
  end

  defp arguments!(_alternative, rule), do: malformed!(rule)

  @spec malformed!(Rule.t()) :: no_return()
  defp malformed!(rule) do
    raise ArgumentError,
          "the terminal of <#{rule.lhs}> on line #{rule.line} of the SZS BNF is not " <>
            "#{rule.lhs} or #{rule.lhs}(<...>): #{inspect(rule.raw)}"
  end

  defp single_ref!([{:ref, name}], _rule), do: name

  defp single_ref!(alternative, rule) do
    raise ArgumentError,
          "<#{rule.lhs}> on line #{rule.line} of the SZS BNF has an alternative that is " <>
            "not a single nonterminal: #{inspect(alternative)}"
  end

  defp single_literal!([{:literal, word}], _rule), do: word

  defp single_literal!(alternative, rule) do
    raise ArgumentError,
          "<#{rule.lhs}> on line #{rule.line} of the SZS BNF has an alternative that is " <>
            "not a single word: #{inspect(alternative)}"
  end

  defp atom!(%Rule{} = rule) do
    atom = Macro.underscore(rule.lhs)

    if Regex.match?(~r/^[a-z_][a-z0-9_]*$/, atom) do
      atom
    else
      raise ArgumentError,
            "<#{rule.lhs}> on line #{rule.line} of the SZS BNF does not snake-case " <>
              "to a plain atom: #{inspect(atom)}"
    end
  end

  defp check!(entries, roots) do
    names = Enum.map(entries, & &1.name)
    by_name = Map.new(entries, &{&1.name, &1})

    duplicate = names -- Enum.uniq(names)

    if duplicate != [] do
      raise ArgumentError, "the SZS BNF defines <#{hd(duplicate)}> more than once"
    end

    atoms = Enum.map(entries, & &1.atom)
    clash = atoms -- Enum.uniq(atoms)

    if clash != [] do
      raise ArgumentError, "two SZS values snake-case to the same atom :#{hd(clash)}"
    end

    for entry <- entries,
        name <- entry.children ++ entry.arguments ++ roots,
        not Map.has_key?(by_name, name) do
      raise ArgumentError,
            "<#{name}> is referenced from <#{entry.name}> on line #{entry.line} of the " <>
              "SZS BNF but never defined"
    end

    Enum.each(entries, &acyclic!(&1, by_name))

    ancestors = closure(by_name, parents(entries), names)
    Enum.each(names, &home!(&1, roots, ancestors))
  end

  defp acyclic!(entry, by_name) do
    step = Map.new(by_name, fn {name, e} -> {name, e.children} end)

    for child <- entry.children, MapSet.member?(reach(child, step, MapSet.new()), entry.name) do
      raise ArgumentError,
            "the SZS BNF is not acyclic: <#{entry.name}> isa ... isa <#{child}> isa <#{entry.name}>"
    end

    :ok
  end

  defp parents(entries) do
    for parent <- entries, child <- parent.children, reduce: Map.new(entries, &{&1.name, []}) do
      acc -> Map.update!(acc, child, &(&1 ++ [parent.name]))
    end
  end

  # The transitive closure of `step` from each name, without the name itself, in the
  # order `order` lists the names.
  defp closure(by_name, step, order) do
    position = order |> Enum.with_index() |> Map.new()

    Map.new(Map.keys(by_name), fn name ->
      reached = reach(name, step, MapSet.new()) |> MapSet.delete(name)
      {name, Enum.sort_by(MapSet.to_list(reached), &Map.fetch!(position, &1))}
    end)
  end

  defp reach(name, step, seen) do
    if MapSet.member?(seen, name) do
      seen
    else
      Enum.reduce(Map.fetch!(step, name), MapSet.put(seen, name), &reach(&1, step, &2))
    end
  end

  defp home!(name, roots, ancestors) do
    above = [name | Map.fetch!(ancestors, name)]

    case Enum.filter(roots, &(&1 in above)) do
      [root] ->
        root

      [] ->
        raise ArgumentError, "<#{name}> in the SZS BNF sits beneath none of the roots"

      many ->
        raise ArgumentError,
              "<#{name}> in the SZS BNF sits beneath #{length(many)} roots: " <>
                Enum.map_join(many, ", ", &"<#{&1}>")
    end
  end

  defp render(context) do
    %{entries: entries, roots: roots, by_name: by_name} = context
    count = length(entries)
    atom = fn name -> ":" <> Map.fetch!(by_name, name).atom end
    atoms = fn names -> "[" <> Enum.map_join(names, ", ", atom) <> "]" end
    example = Enum.max_by(entries, &length(Map.fetch!(context.parents, &1.name)))
    deepest = Enum.max_by(entries, &length(Map.fetch!(context.ancestors, &1.name)))

    """
    defmodule Tptp.Szs.Ontology do
      @moduledoc \"\"\"
      The SZS ontologies: their #{count} status values, the #{length(roots)} ontologies
      the values belong to, and the `isa` hierarchy among them.

      DO NOT EDIT. Generated by `mix tptp.gen` from
      `priv/bnf/#{Path.basename(context.path)}`.

      Each value is a nonterminal of the BNF, and its rule names the value's own
      terminal and the values directly beneath it:

          <#{example.name}> ::= #{example.name} | #{Enum.map_join(example.children, " | ", &"<#{&1}>")}

      Here `children(#{atom.(example.name)})` is `#{atoms.(example.children)}`,
      and `#{atom.(example.name)}` is among the `parents/1` of each. The hierarchy is
      a directed acyclic graph rather than a tree: `<#{example.name}>` itself has
      #{length(Map.fetch!(context.parents, example.name))} parents,
      #{Enum.map_join(Map.fetch!(context.parents, example.name), ", ", &"`<#{&1}>`")}.
      `ancestors/1` and `descendants/1` are the transitive closures, and `isa?/2` is
      the derivability of one value's terminal from another value's nonterminal.

      The ontologies are the alternatives of `<SZS>`:
      #{Enum.map_join(roots, ", ", &"`<#{&1}>`")}. Every value sits beneath exactly
      one of them, and `ontology/1` says which.

      One terminal takes arguments: `<Assumed> ::= Assumed(<Unknown>,<Success>)`.
      The references inside the parentheses are the domains of the arguments and not
      `isa` edges; `arguments/1` lists them.

      Every atom is created at compile time, so `from_string/1` converts untrusted
      prover output to an atom without `String.to_atom/1` being reachable from
      input. See `Tptp.Token` for the same constraint and the Credo check enforcing
      it.

      The BNF carries neither mnemonics nor descriptions. `Tptp.Szs.Page`
      transcribes those from the ontology page by hand, and the functions here that
      answer with them delegate to it.
      \"\"\"

      @typedoc "One SZS status value. A closed set of #{count} compile-time atoms."
      @type t :: #{Enum.map_join(entries, " | ", &(":" <> &1.atom))}

      @typedoc "Which of the #{length(roots)} SZS ontologies a value belongs to: the alternatives of `<SZS>`."
      @type ontology :: #{Enum.map_join(roots, " | ", atom)}

      @doc "Every status value, in the order the BNF defines them."
      @spec values() :: [t()]
      def values, do: #{atoms.(Enum.map(entries, & &1.name))}

      @doc "How many status values there are."
      @spec count() :: pos_integer()
      def count, do: #{count}

      @doc "The #{length(roots)} ontologies, as `<SZS>` lists them."
      @spec ontologies() :: [ontology()]
      def ontologies, do: #{atoms.(roots)}

      @doc \"\"\"
      The BNF these values are generated from.

      The file carries no version number; `NOTICE` records the commit it was taken at.
      \"\"\"
      @spec source() :: binary()
      def source, do: "https://github.com/TPTPWorld/SZSOntologies/blob/master/BNF/SZSOntology.bnf"

      @doc \"\"\"
      Turn a `OneWord` status value into an atom, without creating one.

          iex> Tptp.Szs.Ontology.from_string("Theorem")
          {:ok, :theorem}
          iex> Tptp.Szs.Ontology.from_string("NotAStatus")
          :error
      \"\"\"
      @spec from_string(binary()) :: {:ok, t()} | :error
    #{Enum.map_join(entries, "\n", &"  def from_string(#{inspect(&1.name)}), do: {:ok, :#{&1.atom}}")}
      def from_string(word) when is_binary(word), do: :error

      @doc \"\"\"
      The `OneWord` spelling of a status value: its nonterminal's name.

          iex> Tptp.Szs.Ontology.name(:counter_satisfiable)
          "CounterSatisfiable"
      \"\"\"
      @spec name(t()) :: binary()
    #{Enum.map_join(entries, "\n", &"  def name(:#{&1.atom}), do: #{inspect(&1.name)}")}

      @doc \"\"\"
      Whether a term is a status value at all.

          iex> Tptp.Szs.Ontology.value?(:theorem)
          true
          iex> Tptp.Szs.Ontology.value?(:banana)
          false
      \"\"\"
      @spec value?(term()) :: boolean()
    #{Enum.map_join(entries, "\n", &"  def value?(:#{&1.atom}), do: true")}
      def value?(_other), do: false

      @doc \"\"\"
      Which of the #{length(roots)} ontologies a value belongs to: the root it descends from.

          iex> Tptp.Szs.Ontology.ontology(:theorem)
          :success
          iex> Tptp.Szs.Ontology.ontology(:timeout)
          :no_success
      \"\"\"
      @spec ontology(t()) :: ontology()
    #{Enum.map_join(entries, "\n", &"  def ontology(:#{&1.atom}), do: #{atom.(Map.fetch!(context.home, &1.name))}")}

      @doc \"\"\"
      Whether a value says something was established.

          iex> Tptp.Szs.Ontology.success?(:theorem)
          true
          iex> Tptp.Szs.Ontology.success?(:gave_up)
          false
      \"\"\"
      @spec success?(t()) :: boolean()
      def success?(value), do: ontology(value) == :success

      @doc \"\"\"
      Whether a value says why nothing was established.

          iex> Tptp.Szs.Ontology.no_success?(:timeout)
          true
      \"\"\"
      @spec no_success?(t()) :: boolean()
      def no_success?(value), do: ontology(value) == :no_success

      @doc \"\"\"
      Whether a value describes a form of data rather than a result.

          iex> Tptp.Szs.Ontology.data?(:cnf_refutation)
          true
      \"\"\"
      @spec data?(t()) :: boolean()
      def data?(value), do: ontology(value) == :data

      @doc \"\"\"
      The values directly beneath a value: the nonterminals its rule lists, in that order.

          iex> Tptp.Szs.Ontology.children(:theorem)
          [:satisfiable_axioms_theorem, :contradictory_axioms]
          iex> Tptp.Szs.Ontology.children(:tautology)
          []
      \"\"\"
      @spec children(t()) :: [t()]
    #{Enum.map_join(entries, "\n", &"  def children(:#{&1.atom}), do: #{atoms.(&1.children)}")}

      @doc \"\"\"
      The values a value sits directly beneath, in the order the BNF defines them.

          iex> Tptp.Szs.Ontology.parents(:theorem)
          [:satisfiability_preserving, :tautology_preserving, :finite_theorem]
          iex> Tptp.Szs.Ontology.parents(:success)
          []
      \"\"\"
      @spec parents(t()) :: [t()]
    #{Enum.map_join(entries, "\n", &"  def parents(:#{&1.atom}), do: #{atoms.(Map.fetch!(context.parents, &1.name))}")}

      @doc \"\"\"
      Every value above a value, in the order the BNF defines them. The value itself
      is not among them.

          iex> Tptp.Szs.Ontology.ancestors(#{atom.(deepest.name)})
          #{atoms.(Map.fetch!(context.ancestors, deepest.name))}
      \"\"\"
      @spec ancestors(t()) :: [t()]
    #{Enum.map_join(entries, "\n", &"  def ancestors(:#{&1.atom}), do: #{atoms.(Map.fetch!(context.ancestors, &1.name))}")}

      @doc \"\"\"
      Every value beneath a value, in the order the BNF defines them. The value itself
      is not among them.

          iex> Tptp.Szs.Ontology.descendants(:type_check_success)
          [:type_check_partial, :type_checked_complete]
      \"\"\"
      @spec descendants(t()) :: [t()]
    #{Enum.map_join(entries, "\n", &"  def descendants(:#{&1.atom}), do: #{atoms.(Map.fetch!(context.descendants, &1.name))}")}

      @doc \"\"\"
      Whether `value` is `other` or sits beneath it: whether the BNF derives
      `value`'s terminal from `<other>`.

          iex> Tptp.Szs.Ontology.isa?(:theorem, :satisfiable)
          false
          iex> Tptp.Szs.Ontology.isa?(:equivalent_theorem, :satisfiable)
          true
          iex> Tptp.Szs.Ontology.isa?(:theorem, :theorem)
          true
      \"\"\"
      @spec isa?(t(), t()) :: boolean()
      def isa?(value, other) when is_atom(value) and is_atom(other) do
        value == other or other in ancestors(value)
      end

      @doc \"\"\"
      The values a terminal takes as arguments, or `[]` for the terminals that take none.

          iex> Tptp.Szs.Ontology.arguments(:assumed)
          [:unknown, :success]
          iex> Tptp.Szs.Ontology.arguments(:theorem)
          []
      \"\"\"
      @spec arguments(t()) :: [t()]
    #{Enum.map_join(entries, "\n", &"  def arguments(:#{&1.atom}), do: #{atoms.(&1.arguments)}")}

      @doc "The three-letter mnemonic for a status value. See `Tptp.Szs.Page.mnemonic/1`."
      @spec mnemonic(t()) :: binary()
      defdelegate mnemonic(value), to: Tptp.Szs.Page

      @doc "Turn a mnemonic into an atom. See `Tptp.Szs.Page.from_mnemonic/1`."
      @spec from_mnemonic(binary()) :: {:ok, t()} | {:ambiguous, [t()]} | :error
      defdelegate from_mnemonic(mnemonic), to: Tptp.Szs.Page

      @doc "Turn a `status(...)` mnemonic into an atom. See `Tptp.Szs.Page.from_status_value/1`."
      @spec from_status_value(binary()) :: {:ok, t()} | :error
      defdelegate from_status_value(word), to: Tptp.Szs.Page

      @doc "What the page says a status value means. See `Tptp.Szs.Page.describe/1`."
      @spec describe(t()) :: binary()
      defdelegate describe(value), to: Tptp.Szs.Page
    end
    """
  end
end
