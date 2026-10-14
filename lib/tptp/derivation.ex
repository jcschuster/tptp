defmodule Tptp.Derivation do
  @moduledoc """
  A derivation read as a graph: which statement was derived from which.

  A derivation is an ordinary TPTP file whose annotated statements carry `source`
  annotations — `inference(rw, [status(thm)], [c_0_19])`, `file('p.p', ax1)`,
  `introduced(definition, [], [])` — and this walks those annotations and indexes
  them. It is a reading of the file's structure and no more than that: no formula
  is evaluated and no inference is checked. `status(thm)` resolves to an SZS value
  because the ontology is a vocabulary this library already models, not because the
  claim is believed.

      iex> source = "fof(ax, axiom, p, file('p.p', ax)).\\n" <>
      ...>   "fof(goal, negated_conjecture, ~p, inference(assume_negation, [status(cth)], [ax])).\\n" <>
      ...>   "cnf(bot, plain, $false, inference(rw, [status(thm)], [goal, ax]))."
      iex> {:ok, derivation, []} = Tptp.Derivation.from_string(source)
      iex> {derivation.order, derivation.roots, derivation.leaves}
      {["ax", "goal", "bot"], ["bot"], ["ax"]}

  ## The graph

  `nodes` is keyed by `Tptp.Node.value/1` of a statement's `<name>`, so `'c_0_7'`
  and `c_0_7` are one node: the BNF defines a `<single_quoted>` as the word without
  its quotes, and a parent written one way must resolve a statement named the
  other. Where two statements share a name the later one wins the key, since a file
  is read in order and a reference can only mean the name as last bound; the
  earlier statement is still in `file.statements`, and the duplicate is reported.

  `roots` are the nodes no node derives from — in a refutation, the statement of
  `$false` — and `leaves` the nodes that derive from nothing, which in a proof
  found from a problem are the `file(...)` statements. Both are facts about the
  edges rather than about how an edge was written: a statement justified by a bare
  `<name>` has a parent and no inference step, and is not a leaf.

  An edge is a name, and a name need not resolve. A parent naming no statement of
  the file is reported and is then ignored by every query that walks the graph —
  `ancestors/2`, `descendants/2`, `cone/2`, `topological/1`, `acyclic?/1` —
  because a node it cannot name is a node this graph does not have. `leaves`
  reads `parents` as written instead: a statement whose parent the file lacks was
  derived from something, and is not an input of the derivation. The literal
  `unknown`, by which a system declines to record a parent, is the case that shows
  why; `inference(r, [], [unknown])` is no axiom.

  ## Diagnostics

  Reading never fails; a graph is always returned. Three things are reported, with
  spans into `file.id`:

  | Code | Finding |
  |------|---------|
  | `TPTP0503` | two statements sharing a name |
  | `TPTP0504` | a parent naming no statement, once per occurrence, `unknown` excepted |
  | `TPTP0507` | a node derived from itself, once per cycle |

  The first two are `Tptp.Lint.Rules.DuplicateName` and
  `Tptp.Lint.Rules.Parent`'s own codes and wording, called through their `code/0`:
  the finding is the same one, and a caller filtering on a code should not have to
  know which reader reported it. `TPTP0507` has no lint counterpart, because a
  single statement cannot show a cycle.

  `order`, `roots` and `leaves` stay the textual facts when there is a cycle. A
  derivation that is not a DAG is still indexed and still printable; `acyclic?/1`
  and `topological/1` are what answer the question.

  ## What this does not do

  Nothing here prints: `cone/2` returns a `Tptp.Derivation` whose `file` is a
  `Tptp.File` over the original source, so `Tptp.Printer.Canonical.to_string/1`
  prints it and `Tptp.Statement.text/2` slices it. Nothing here checks an
  inference, resolves a `file(...)` reference against the file system, or writes a
  TSTP solution file — see `Tptp.Tstp` for reading one.
  """

  alias Tptp.Derivation.Node, as: Vertex
  alias Tptp.Diagnostic
  alias Tptp.Lint.Rules.DuplicateName
  alias Tptp.Lint.Rules.Parent
  alias Tptp.Node
  alias Tptp.Statement.Annotated

  @cycle "TPTP0507"

  @enforce_keys [:file, :nodes, :order, :roots, :leaves]
  defstruct [:file, :nodes, :order, :roots, :leaves]

  @typedoc """
  A derivation: the file it was read from, its nodes by name, and three readings of
  the graph.

  `order` holds each name once, at the position of the statement that bound it
  last; `roots` and `leaves` are `order` filtered, so every list here is in the
  file's own order.
  """
  @type t :: %__MODULE__{
          file: Tptp.File.t(),
          nodes: %{binary() => Vertex.t()},
          order: [binary()],
          roots: [binary()],
          leaves: [binary()]
        }

  @doc """
  Index a parsed file as a derivation.

  Takes the `Tptp.File` rather than a path, so that a derivation lifted out of a
  solution file or an SZS output block is read the same way as one in a file of its
  own:

      iex> {:ok, solution, []} = Tptp.Tstp.from_file("test/fixtures/tstp/E---3.5.1.THM-CRf.s")
      iex> {:ok, derivation, []} = Tptp.Derivation.from_file(solution.solution)
      iex> {length(derivation.order), length(derivation.leaves), derivation.roots}
      {54, 11, ["c_0_53"]}
  """
  @spec from_file(Tptp.File.t()) :: {:ok, t(), [Diagnostic.t()]}
  def from_file(%Tptp.File{} = file) do
    statements = Enum.filter(file.statements, &match?(%Annotated{}, &1))
    nodes = Enum.map(statements, &Vertex.from_statement/1)
    index = Map.new(nodes, &{&1.name, &1})
    order = order(nodes)

    derivation = %__MODULE__{
      file: file,
      nodes: index,
      order: order,
      roots: roots(order, index),
      leaves: leaves(order, index)
    }

    {:ok, derivation, Diagnostic.sort(found(derivation, statements, nodes))}
  end

  @doc """
  Parse a derivation from a binary.

  The options are `Tptp.from_string/2`'s. Its diagnostics come first, then this
  module's, each group in reading order.

      iex> {:ok, derivation, []} = Tptp.Derivation.from_string("fof(a, axiom, p).\\nfof(b, plain, q, a).")
      iex> {derivation.nodes["b"].origin, derivation.nodes["b"].parents}
      {{:name, "a"}, ["a"]}

      iex> {:ok, _derivation, [diagnostic]} = Tptp.Derivation.from_string("fof(b, plain, q, inference(r, [], [a])).")
      iex> {diagnostic.code, diagnostic.message}
      {"TPTP0504", ~s("a" is named as a parent but no statement has that name)}
  """
  @spec from_string(binary(), [Tptp.option()]) :: {:ok, t(), [Diagnostic.t()]}
  def from_string(input, options \\ []) when is_binary(input) and is_list(options) do
    {:ok, file, parsing} = Tptp.from_string(input, options)
    {:ok, derivation, found} = from_file(file)

    {:ok, derivation, parsing ++ found}
  end

  @doc """
  Every node the named one is derived from, however far back, in `order`.

  The node itself is not in the list, even where a cycle derives it from itself,
  and a name the derivation does not have has no ancestors.

      iex> {:ok, derivation, []} =
      ...>   Tptp.Derivation.from_string("fof(a, axiom, p).\\nfof(b, plain, q, a).\\nfof(c, plain, r, b).")
      iex> {Tptp.Derivation.ancestors(derivation, "c"), Tptp.Derivation.ancestors(derivation, "z")}
      {["a", "b"], []}
  """
  @spec ancestors(t(), binary()) :: [binary()]
  def ancestors(%__MODULE__{} = derivation, name) when is_binary(name) do
    reachable(derivation, name, &parents_of(derivation, &1))
  end

  @doc """
  Every node derived from the named one, however far on, in `order`.

      iex> {:ok, derivation, []} =
      ...>   Tptp.Derivation.from_string("fof(a, axiom, p).\\nfof(b, plain, q, a).\\nfof(c, plain, r, b).")
      iex> Tptp.Derivation.descendants(derivation, "a")
      ["b", "c"]
  """
  @spec descendants(t(), binary()) :: [binary()]
  def descendants(%__MODULE__{} = derivation, name) when is_binary(name) do
    children = children(derivation)

    reachable(derivation, name, &Map.get(children, &1, []))
  end

  @doc """
  The sub-derivation ending in the named node: it and its ancestors.

  The `file` of the result is the input's, with the statements of the dropped nodes
  and the comments outside the retained statements removed — so the source is
  intact and the result prints and slices like any other file. A node's `parents`
  are as written: every parent that resolves is an ancestor of the node, so it is
  retained, and a name that resolved to nothing stays, as it stays in the
  derivation. A node is therefore a leaf of its cone exactly when it is a leaf of
  the derivation (`verify/Tptp/Derivation.lean` proves the first half of that).
  An unknown name yields an empty derivation.

      iex> {:ok, derivation, []} =
      ...>   Tptp.Derivation.from_string("fof(a, axiom, p).\\nfof(b, axiom, q).\\nfof(c, plain, r, inference(x, [], [a])).")
      iex> cone = Tptp.Derivation.cone(derivation, "c")
      iex> {cone.order, Tptp.Printer.Canonical.to_string(cone.file)}
      {["a", "c"], "fof(a, axiom, p).\\nfof(c, plain, r, inference(x, [], [a])).\\n"}
  """
  @spec cone(t(), binary()) :: t()
  def cone(%__MODULE__{} = derivation, name) when is_binary(name) do
    retained = retained(derivation, name)
    nodes = Map.new(retained, &{&1, derivation.nodes[&1]})
    order = Enum.filter(derivation.order, &MapSet.member?(retained, &1))

    %__MODULE__{
      file: sub_file(derivation, nodes, order),
      nodes: nodes,
      order: order,
      roots: roots(order, nodes),
      leaves: leaves(order, nodes)
    }
  end

  @doc """
  Whether no node is derived from itself.

      iex> {:ok, derivation, []} = Tptp.Derivation.from_string("fof(a, axiom, p).\\nfof(b, plain, q, a).")
      iex> Tptp.Derivation.acyclic?(derivation)
      true

      iex> {:ok, derivation, [_cycle]} = Tptp.Derivation.from_string("fof(a, plain, p, b).\\nfof(b, plain, q, a).")
      iex> Tptp.Derivation.acyclic?(derivation)
      false
  """
  @spec acyclic?(t()) :: boolean()
  def acyclic?(%__MODULE__{} = derivation), do: match?({:ok, _sorted}, topological(derivation))

  @doc """
  The nodes with every parent before every child, or `:error` for a cycle.

  Among the nodes whose parents have all been emitted, the one earliest in `order`
  comes first, so the answer is the file's own order wherever the graph does not
  require otherwise.

      iex> {:ok, derivation, []} =
      ...>   Tptp.Derivation.from_string("fof(c, plain, r, a).\\nfof(a, axiom, p).\\nfof(b, axiom, q).")
      iex> Tptp.Derivation.topological(derivation)
      {:ok, ["a", "c", "b"]}

  `a` comes first because `c` derives from it, and `c` before `b` because the file
  writes it first.

      iex> {:ok, derivation, [_cycle]} = Tptp.Derivation.from_string("fof(a, plain, p, a).")
      iex> Tptp.Derivation.topological(derivation)
      :error
  """
  @spec topological(t()) :: {:ok, [binary()]} | :error
  def topological(%__MODULE__{} = derivation) do
    sorted = kahn(derivation)

    if length(sorted) == length(derivation.order), do: {:ok, sorted}, else: :error
  end

  @spec order([Vertex.t()]) :: [binary()]
  defp order(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, index}, seen -> Map.put(seen, node.name, index) end)
    |> Enum.sort_by(fn {_name, index} -> index end)
    |> Enum.map(fn {name, _index} -> name end)
  end

  @spec roots([binary()], %{binary() => Vertex.t()}) :: [binary()]
  defp roots(order, index) do
    parented =
      index |> Map.values() |> Enum.flat_map(& &1.parents) |> MapSet.new()

    Enum.reject(order, &MapSet.member?(parented, &1))
  end

  @spec leaves([binary()], %{binary() => Vertex.t()}) :: [binary()]
  defp leaves(order, index), do: Enum.filter(order, &(index[&1].parents == []))

  @spec found(t(), [Annotated.t()], [Vertex.t()]) :: [Diagnostic.t()]
  defp found(derivation, statements, nodes) do
    id = derivation.file.id

    duplicates(statements, id) ++
      unresolved(nodes, derivation.nodes, id) ++ cycles(derivation, id)
  end

  @spec duplicates([Annotated.t()], Tptp.Span.file_id()) :: [Diagnostic.t()]
  defp duplicates(statements, id) do
    statements
    |> Enum.group_by(&Node.value(&1.name), & &1.name)
    |> Enum.flat_map(fn
      {_name, [_single]} -> []
      {name, [first, second | rest]} -> [duplicate(name, first, second, rest, id)]
    end)
  end

  @spec duplicate(binary(), Node.t(), Node.t(), [Node.t()], Tptp.Span.file_id()) :: Diagnostic.t()
  defp duplicate(name, first, second, rest, id) do
    Diagnostic.new(
      DuplicateName.code(),
      DuplicateName.severity(),
      Node.span(second, id),
      "#{inspect(name)} names #{2 + length(rest)} statements",
      hint: "names identify formulae, and an inference record refers to them by name",
      related: [
        {Node.span(first, id), "first named here"}
        | Enum.map(rest, &{Node.span(&1, id), "and here"})
      ]
    )
  end

  @spec unresolved([Vertex.t()], %{binary() => Vertex.t()}, Tptp.Span.file_id()) :: [
          Diagnostic.t()
        ]
  defp unresolved(nodes, index, id) do
    Enum.flat_map(nodes, fn node ->
      node.statement.source
      |> Vertex.parent_nodes()
      |> Enum.reject(&resolves?(&1, index))
      |> Enum.map(&missing(&1, id))
    end)
  end

  # `unknown` is a `<name>` to the grammar — the first of `Tptp.Bnf.Generator`'s
  # departures — and names a parent a system declined to record, so it is not
  # reported, as in `Tptp.Lint.Rules.Parent`.
  @spec resolves?(Node.t(), %{binary() => Vertex.t()}) :: boolean()
  defp resolves?(parent, index) do
    name = Node.value(parent)

    name == "unknown" or Map.has_key?(index, name)
  end

  @spec missing(Node.t(), Tptp.Span.file_id()) :: Diagnostic.t()
  defp missing(parent, id) do
    Diagnostic.new(
      Parent.code(),
      Parent.severity(),
      Node.span(parent, id),
      "#{inspect(Node.value(parent))} is named as a parent but no statement has that name",
      hint: "either the parent is missing or the name is wrong"
    )
  end

  @spec cycles(t(), Tptp.Span.file_id()) :: [Diagnostic.t()]
  defp cycles(derivation, id) do
    derivation |> components() |> Enum.map(&cycle(&1, derivation, id))
  end

  @spec cycle([binary()], t(), Tptp.Span.file_id()) :: Diagnostic.t()
  defp cycle([name | rest], derivation, id) do
    Diagnostic.new(
      @cycle,
      :warning,
      name_span(derivation, name, id),
      "#{inspect(name)} is derived from itself#{through(rest)}",
      hint: "a derivation is a DAG; `Tptp.Derivation.acyclic?/1` is false",
      related: Enum.map(rest, &{name_span(derivation, &1, id), "on the same cycle"})
    )
  end

  @spec through([binary()]) :: binary()
  defp through([]), do: ""
  defp through(rest), do: " through " <> Enum.map_join(rest, ", ", &inspect/1)

  @spec name_span(t(), binary(), Tptp.Span.file_id()) :: Tptp.Span.t()
  defp name_span(derivation, name, id), do: Node.span(derivation.nodes[name].statement.name, id)

  # Strongly connected components of more than one node, and self-loops, are what
  # `:digraph_utils.cyclic_strong_components/1` returns, which is the definition of a
  # cycle wanted here. The graph is a private ETS table, so it is deleted whatever
  # happens; nothing of it escapes this function.
  @spec components(t()) :: [[binary()]]
  defp components(derivation) do
    graph = :digraph.new([:private])

    try do
      Enum.each(derivation.order, &:digraph.add_vertex(graph, &1))

      Enum.each(edges(derivation), fn {parent, child} ->
        :digraph.add_edge(graph, parent, child)
      end)

      graph
      |> :digraph_utils.cyclic_strong_components()
      |> Enum.map(&in_order(&1, derivation.order))
      |> Enum.sort_by(&Enum.find_index(derivation.order, fn name -> name == hd(&1) end))
    after
      :digraph.delete(graph)
    end
  end

  @spec edges(t()) :: [{binary(), binary()}]
  defp edges(derivation) do
    for name <- derivation.order,
        parent <- parents_of(derivation, name),
        do: {parent, name}
  end

  @spec in_order([binary()], [binary()]) :: [binary()]
  defp in_order(names, order) do
    found = Map.new(names, &{&1, true})

    Enum.filter(order, &Map.has_key?(found, &1))
  end

  @spec parents_of(t(), binary()) :: [binary()]
  defp parents_of(derivation, name) do
    case Map.fetch(derivation.nodes, name) do
      {:ok, node} -> Enum.filter(node.parents, &Map.has_key?(derivation.nodes, &1))
      :error -> []
    end
  end

  @spec children(t()) :: %{binary() => [binary()]}
  defp children(derivation) do
    Enum.reduce(edges(derivation), %{}, fn {parent, child}, children ->
      Map.update(children, parent, [child], &[child | &1])
    end)
  end

  @spec reachable(t(), binary(), (binary() -> [binary()])) :: [binary()]
  defp reachable(derivation, name, next) do
    if Map.has_key?(derivation.nodes, name) do
      found = name |> next.() |> walk(next, %{}) |> Map.delete(name)

      in_order(Map.keys(found), derivation.order)
    else
      []
    end
  end

  # The visited set is a map rather than a `MapSet`: it is built and read here only,
  # and `MapSet.t/1` is opaque, which a private function cannot both construct and
  # declare.
  @spec walk([binary()], (binary() -> [binary()]), %{binary() => true}) :: %{binary() => true}
  defp walk([], _next, seen), do: seen

  defp walk([name | rest], next, seen) do
    if Map.has_key?(seen, name) do
      walk(rest, next, seen)
    else
      walk(next.(name) ++ rest, next, Map.put(seen, name, true))
    end
  end

  # Kahn's algorithm, with the ready nodes in a `:gb_sets` set keyed by position in
  # `order`: the next node is the earliest one whose parents are all out, and taking
  # the smallest of a set costs a logarithm rather than a scan.
  @spec kahn(t()) :: [binary()]
  defp kahn(derivation) do
    positions = derivation.order |> Enum.with_index() |> Map.new()
    degrees = Map.new(derivation.order, &{&1, length(parents_of(derivation, &1))})
    ready = for name <- derivation.order, degrees[name] == 0, do: {positions[name], name}

    %{
      ready: :gb_sets.from_list(ready),
      degrees: degrees,
      children: children(derivation),
      positions: positions,
      out: []
    }
    |> emit()
    |> Enum.reverse()
  end

  @spec emit(map()) :: [binary()]
  defp emit(state) do
    if :gb_sets.is_empty(state.ready), do: state.out, else: state |> take() |> emit()
  end

  @spec take(map()) :: map()
  defp take(state) do
    {{_position, name}, ready} = :gb_sets.take_smallest(state.ready)
    state = %{state | ready: ready, out: [name | state.out]}

    Enum.reduce(Map.get(state.children, name, []), state, &release/2)
  end

  @spec release(binary(), map()) :: map()
  defp release(child, state) do
    degrees = Map.update!(state.degrees, child, &(&1 - 1))

    case degrees[child] do
      0 -> %{state | degrees: degrees, ready: ready(state, child)}
      _positive -> %{state | degrees: degrees}
    end
  end

  @spec ready(map(), binary()) :: :gb_sets.set({non_neg_integer(), binary()})
  defp ready(state, child), do: :gb_sets.add({state.positions[child], child}, state.ready)

  @spec retained(t(), binary()) :: MapSet.t(binary())
  defp retained(derivation, name) do
    if Map.has_key?(derivation.nodes, name) do
      MapSet.new([name | ancestors(derivation, name)])
    else
      MapSet.new()
    end
  end

  @spec sub_file(t(), %{binary() => Vertex.t()}, [binary()]) :: Tptp.File.t()
  defp sub_file(derivation, nodes, order) do
    offsets = MapSet.new(order, &nodes[&1].statement.off)
    statements = Enum.filter(derivation.file.statements, &retained?(&1, offsets))

    %{
      derivation.file
      | statements: statements,
        comments: inside(derivation.file.comments, statements),
        diagnostics: []
    }
  end

  @spec retained?(Tptp.Statement.t(), MapSet.t(non_neg_integer())) :: boolean()
  defp retained?(%Annotated{off: off}, offsets), do: MapSet.member?(offsets, off)
  defp retained?(_statement, _offsets), do: false

  # Both lists are in source order, so one walk keeps the comments that fall inside a
  # retained statement. A comment between two statements belongs to neither.
  @spec inside([Tptp.Lexer.comment()], [Tptp.Statement.t()]) :: [Tptp.Lexer.comment()]
  defp inside(comments, statements), do: inside(comments, statements, [])

  @spec inside([Tptp.Lexer.comment()], [Tptp.Statement.t()], [Tptp.Lexer.comment()]) ::
          [Tptp.Lexer.comment()]
  defp inside([], _statements, kept), do: Enum.reverse(kept)
  defp inside(_comments, [], kept), do: Enum.reverse(kept)

  defp inside([{off, len, _where, _kind} = comment | rest], [statement | tail] = statements, kept) do
    cond do
      off >= statement.off + statement.len ->
        inside([comment | rest], tail, kept)

      off >= statement.off and off + len <= statement.off + statement.len ->
        inside(rest, statements, [comment | kept])

      true ->
        inside(rest, statements, kept)
    end
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # The derivation holds the file, which holds its whole source — see
    # `Tptp.File`'s implementation for why printing that is a hazard. The counts are
    # what identify a derivation; `inspect(derivation, structs: false)` still shows
    # the map.
    @impl true
    def inspect(derivation, _opts) do
      concat([
        "#Tptp.Derivation<",
        count(map_size(derivation.nodes), "node", "nodes"),
        ", ",
        count(length(derivation.leaves), "leaf", "leaves"),
        ", ",
        count(length(derivation.roots), "root", "roots"),
        ">"
      ])
    end

    defp count(1, singular, _plural), do: "1 #{singular}"
    defp count(n, _singular, plural), do: "#{n} #{plural}"
  end
end
