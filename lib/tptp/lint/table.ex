defmodule Tptp.Lint.Table do
  @moduledoc """
  What the traversal learned, for the rules that need more than one statement.

  ## Syntactic only

  A symbol's entry records the *node* its type was declared as, unelaborated. There
  is no unification here, no substitution, no notion that `$i` is a type and `a` is
  not. That is the boundary the whole library is built around: TPTP's typed
  dialects annotate everything, so nothing needs inferring, and a table that
  started inferring would be a type checker wearing a lint rule's clothes.

  So `declared_as` is a `Tptp.Node`, and the only questions asked of it are
  syntactic — does it contain a `!>`, how many arrows does its spine have. Anything
  further belongs to a consumer with a signature in hand.

  ## Arities are recorded, not judged

  `arities` collects every spine length a symbol was applied at. Inconsistency is
  a finding in CNF and FOF and *not* a finding in TH1, because instantiating a type
  variable raises arity — `ar(t[b]) >= ar(t)` — so a polymorphic symbol is applied
  at several arities as a matter of course. The table records; `Tptp.Lint.Rules.Arity`
  decides, and knows the difference.
  """

  alias Tptp.Node
  alias Tptp.Span

  defstruct symbols: %{}, names: %{}, parents: [], features: MapSet.new(), counted: MapSet.new()

  @typedoc """
  One symbol, as the traversal saw it.

  `declared_as` is `nil` for a symbol that was used but never declared, which is
  legal in FOF and CNF and a finding in the typed dialects.
  """
  @type symbol :: %{
          name: binary(),
          kind: atom(),
          declared_as: Node.t() | nil,
          declared_at: Span.t() | nil,
          used_at: [Span.t()],
          arities: MapSet.t(non_neg_integer())
        }

  @typedoc "Everything the single walk accumulated: symbols, names, parents, dialect features and counts."
  @type t :: %__MODULE__{
          symbols: %{binary() => symbol()},
          names: %{binary() => [Span.t()]},
          parents: [{binary(), Span.t()}],
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
        parents: Enum.reverse(table.parents)
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
end
