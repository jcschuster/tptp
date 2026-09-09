defmodule Tptp.Lint.Table do
  @moduledoc """
  The information accumulated by the traversal, for rules requiring more than one
  statement.

  ## Syntactic content only

  A symbol's entry records the unelaborated `Tptp.Node` its type was declared as.
  No unification or substitution is performed and `$i` is not interpreted as a
  type. The questions asked of `declared_as` are syntactic: whether it contains a
  `!>`, how many arrows its spine has. Anything further requires a signature and
  belongs to the consumer.

  ## Keys

  Every key — symbol, statement name, inference parent — is a `Tptp.Node.value/1`
  rather than a `text`. `'p'` and `p` are one atomic word by the BNF's definition
  and therefore one entry, and `name` in a symbol holds the unquoted word. A caller
  reporting the spelling has the spans from which to read it.

  ## Arities

  `arities` records every application arity observed for a symbol. No rule reads it
  to derive a finding, because arity overloading is well formed. The TPTP language
  page states:

  > Symbols may be overloaded with different arity signatures, and are treated as
  > different symbols.

  So `color/1` alongside `color/2` denotes two symbols in every dialect. A rule
  reporting such pairs was shipped for a period and was incorrect on every file it
  applied to; see the CHANGELOG.

  Two consequences follow. Arity forms part of a symbol's identity in TPTP, and
  this table is keyed on the name alone, so `sqrt/1` and `sqrt/2` occupy one entry.
  That suffices for the rules reading this table, each of which asks only whether a
  name was declared, and is recorded here because a consumer deriving a signature
  from `Tptp.Query.symbols/1` must account for it. Further, the arity condition
  TPTP does state — "If a symbol's type is declared more than once, and the types
  are not the same, that's an error" — concerns a single symbol and therefore
  compares two declarations at the same arity, which this table cannot presently
  distinguish.
  """

  alias Tptp.Node
  alias Tptp.Span

  defstruct symbols: %{},
            names: %{},
            parents: [],
            conjectures: [],
            features: MapSet.new(),
            counted: MapSet.new()

  @typedoc """
  One symbol, as the traversal saw it.

  `name` is the canonical atomic word, so a symbol written `'p'` in one statement
  and `p` in the next is this one entry. `declared_as` is `nil` for a symbol that
  was used but never declared, which is legal in FOF and CNF and a finding in the
  typed dialects.
  """
  @type symbol :: %{
          name: binary(),
          kind: atom(),
          declared_as: Node.t() | nil,
          declared_at: Span.t() | nil,
          used_at: [Span.t()],
          arities: MapSet.t(non_neg_integer())
        }

  @typedoc "Which of the two spellings of a conjecture a statement used."
  @type conjecture :: :conjecture | :negated_conjecture

  @typedoc "Everything the single walk accumulated: symbols, names, parents, conjectures, dialect features and counts."
  @type t :: %__MODULE__{
          symbols: %{binary() => symbol()},
          names: %{binary() => [Span.t()]},
          parents: [{binary(), Span.t()}],
          conjectures: [{conjecture(), Span.t()}],
          features: MapSet.t(atom()),
          counted: MapSet.t({Span.file_id(), non_neg_integer()})
        }

  @doc """
  Record a symbol declaration — a `type`-role statement's subject.
  """
  @spec declare(t(), binary(), atom(), Node.t() | nil, Span.t()) :: t()
  def declare(%__MODULE__{} = table, name, kind, declared_as, span) do
    entry =
      table.symbols
      |> Map.get(name, blank(name, kind))
      |> Map.merge(%{kind: kind, declared_as: declared_as, declared_at: span})

    %{table | symbols: Map.put(table.symbols, name, entry)}
  end

  @doc """
  Record a symbol occurrence, at the arity it was applied with.

  One position counts once. `p(b)` reaches this twice — the traversal offers the
  `fof_plain_term` before its `functor` child, so the application arrives with
  arity 1 and the head leaf arrives again with arity 0 — and counting both would
  report every applied symbol in the library as having two arities. The application
  comes first because the walk is top-down, so first writer wins and the leaf's
  second look is dropped.
  """
  @spec use(t(), binary(), atom(), non_neg_integer(), Span.t()) :: t()
  def use(%__MODULE__{} = table, name, kind, arity, span) do
    position = {:use, span.file, span.offset}

    if MapSet.member?(table.counted, position) do
      table
    else
      entry = Map.get(table.symbols, name, blank(name, kind))

      entry = %{
        entry
        | used_at: [span | entry.used_at],
          arities: MapSet.put(entry.arities, arity)
      }

      %{
        table
        | symbols: Map.put(table.symbols, name, entry),
          counted: MapSet.put(table.counted, position)
      }
    end
  end

  @doc """
  Claim a position without recording anything, so nothing else counts it.

  For a subtree whose atoms are labels rather than uses — the term of an
  `<ntf_index>`, where `#agent` names a modality rather than applying a symbol.
  `use/5` drops a position it has already seen, so claiming the position first is
  how a top-down walk with no way to look up says "not this one".
  """
  @spec ignore(t(), Span.t()) :: t()
  def ignore(%__MODULE__{} = table, span) do
    %{table | counted: MapSet.put(table.counted, {:use, span.file, span.offset})}
  end

  @doc """
  Record a statement's name, so a second one can be reported against the first.

  One position counts once, for the same reason `use/5` says so and a sharper one:
  `Tptp.Unit.statements/1` expands an `include` wherever it stands, so a file
  reached down two paths of a diamond is walked twice. Counting both would report
  every name in every shared axiom set as a duplicate — 46,724 of them across a
  quarter of the library, none of them a real finding. Two *different* statements
  sharing a name still are, and still are reported.
  """
  @spec name(t(), binary(), Span.t()) :: t()
  def name(%__MODULE__{} = table, name, span) do
    position = {:name, span.file, span.offset}

    if MapSet.member?(table.counted, position) do
      table
    else
      %{
        table
        | names: Map.update(table.names, name, [span], &[span | &1]),
          counted: MapSet.put(table.counted, position)
      }
    end
  end

  @doc """
  Record a name used as an inference parent, to be checked against `names` later.
  """
  @spec parent(t(), binary(), Span.t()) :: t()
  def parent(%__MODULE__{} = table, name, span) do
    position = {:parent, span.file, span.offset}

    if MapSet.member?(table.counted, position) do
      table
    else
      %{
        table
        | parents: [{name, span} | table.parents],
          counted: MapSet.put(table.counted, position)
      }
    end
  end

  @doc """
  Record a conjecture, in whichever of the two spellings it was written.

  `conjecture` and `negated_conjecture` are kept apart because they do not count
  the same way: one conjecture negated into clause normal form becomes many
  `negated_conjecture` clauses, so counting those would call every CNF problem in
  the library over-specified.

  One position counts once, for the reason `use/5` gives.
  """
  @spec conjecture(t(), conjecture(), Span.t()) :: t()
  def conjecture(%__MODULE__{} = table, form, span) do
    position = {:conjecture, span.file, span.offset}

    if MapSet.member?(table.counted, position) do
      table
    else
      %{
        table
        | conjectures: [{form, span} | table.conjectures],
          counted: MapSet.put(table.counted, position)
      }
    end
  end

  @doc """
  Record a dialect feature the traversal saw.
  """
  @spec feature(t(), atom()) :: t()
  def feature(%__MODULE__{} = table, feature) do
    %{table | features: MapSet.put(table.features, feature)}
  end

  @doc """
  Whether a feature was seen anywhere.
  """
  @spec feature?(t(), atom()) :: boolean()
  def feature?(%__MODULE__{} = table, feature), do: MapSet.member?(table.features, feature)

  @doc """
  Every dialect feature the traversal saw, as a list.

  `Tptp.Query.from_features/1` turns this into a dialect.
  """
  @spec features(t()) :: [atom()]
  def features(%__MODULE__{features: features}), do: MapSet.to_list(features)

  @doc """
  Put every accumulated list back into reading order.

  The traversal prepends, because prepending is what a list is for; this is the one
  place that matters, called once when the walk is done.
  """
  @spec finish(t()) :: t()
  def finish(%__MODULE__{} = table) do
    %{
      table
      | symbols:
          Map.new(table.symbols, fn {k, v} -> {k, %{v | used_at: Enum.reverse(v.used_at)}} end),
        names: Map.new(table.names, fn {k, v} -> {k, Enum.reverse(v)} end),
        parents: Enum.reverse(table.parents),
        conjectures: Enum.reverse(table.conjectures)
    }
  end

  defp blank(name, kind) do
    %{
      name: name,
      kind: kind,
      declared_as: nil,
      declared_at: nil,
      used_at: [],
      arities: MapSet.new()
    }
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # The table carries every symbol in the unit, each with its spans. On a large axiom
    # set that is hundreds of thousands of entries. `Tptp.Query.symbols/1` is how to
    # read them.
    @impl true
    def inspect(table, opts) do
      concat([
        "#Tptp.Lint.Table<",
        count(map_size(table.symbols), "symbol"),
        ", ",
        count(map_size(table.names), "name"),
        ", ",
        to_doc(Enum.sort(MapSet.to_list(table.features)), opts),
        ">"
      ])
    end

    defp count(1, noun), do: "1 #{noun}"
    defp count(n, noun), do: "#{n} #{noun}s"
  end
end
