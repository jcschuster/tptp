defmodule Tptp.Query do
  @moduledoc """
  Properties of a file or unit, determined before further processing.

  The principal one is the dialect, which determines where a problem may be sent.
  Deriving it from the statement keywords alone is inadequate in both directions: a
  `thf` file using only first-order syntax remains THF to a prover, and a `tff`
  file using `!>` requires a TF1 rather than a TF0 implementation. The keyword is
  least informative in the higher-order family, where `thf` covers TH0, TH1, DH0,
  DH1 and NHF alike.

  ## Derivation

  The dialect is derived from the features accumulated by the lint traversal — from
  the constructs a file uses rather than from its statement keywords — and requires
  no traversal of its own.

  It is validated against the TPTP's own classification rather than asserted. Over
  the 26,021 problems of TPTP v9.3.1 that carry an `SPC` header and fall within the
  sweep's size limit, it agrees with that header except where the evidence lies in
  an unread file. `dialect/1` observes a single `Tptp.File`, so a problem whose type
  constructors are supplied by an included axiom set is classified by what is
  present: 220 `TH1` problems are reported as `:th0` until the same call is made on
  a `Tptp.Unit`, which reports `:th1` for each of them.
  """

  alias Tptp.Lint.Table
  alias Tptp.Statement.Annotated

  @typedoc """
  The TPTP dialects, in `rank/1` order.

  `:unknown` is returned for an empty file, which provides no evidence of a
  dialect.
  """
  @type dialect ::
          :unknown
          | :cnf
          | :fof
          | :tcf
          | :tf0
          | :tf1
          | :tx0
          | :tx1
          | :th0
          | :th1
          | :dh0
          | :dh1
          | :nxf
          | :nhf

  @order [
    :unknown,
    :cnf,
    :fof,
    :tcf,
    :tf0,
    :tf1,
    :tx0,
    :tx1,
    :th0,
    :th1,
    :dh0,
    :dh1,
    :nxf,
    :nhf
  ]

  # Immediate containments only; `within?/2` takes the closure. Each edge says the
  # outer language's grammar has everything the inner one's does, so a file in the
  # inner is a file in the outer. See `within?/2` for where this comes from and what
  # it is allowed to be used for.
  @extends %{
    unknown: [:cnf, :fof, :tcf, :tf0, :tf1, :tx0, :tx1, :th0, :th1, :dh0, :dh1, :nxf, :nhf],
    cnf: [:fof, :tcf],
    fof: [:tf0],
    tcf: [:tf0],
    tf0: [:tf1, :tx0, :th0],
    tf1: [:tx1, :th1],
    tx0: [:tx1, :nxf],
    tx1: [:nxf],
    th0: [:th1, :dh0, :nhf],
    th1: [:dh1, :nhf],
    dh0: [:dh1],
    dh1: [],
    nxf: [:nhf],
    nhf: []
  }

  # Plain sorted lists rather than a `MapSet`: a set literal in a module attribute
  # inlines its internal representation and defeats the opacity Dialyzer checks for.
  # Twelve dialects make membership a list scan either way.
  @closure Map.new(@order, fn dialect ->
             {dialect,
              [dialect]
              |> Stream.iterate(fn seen ->
                seen
                |> Enum.flat_map(&Map.fetch!(@extends, &1))
                |> Enum.concat(seen)
                |> Enum.uniq()
                |> Enum.sort()
              end)
              |> Enum.reduce_while(nil, fn seen, previous ->
                if seen == previous, do: {:halt, seen}, else: {:cont, seen}
              end)}
           end)

  @doc """
  Returns the narrowest dialect admitting every construct in the file.

      iex> {:ok, file, []} = Tptp.from_string("cnf(a, axiom, p | ~q).")
      iex> Tptp.Query.dialect(file)
      :cnf

      iex> {:ok, file, []} = Tptp.from_string("tff(a, type, f: $i > $o). tff(b, axiom, f(a)).")
      iex> Tptp.Query.dialect(file)
      :tf0

      iex> {:ok, file, []} = Tptp.from_string("thf(a, axiom, !! @ p).")
      iex> Tptp.Query.dialect(file)
      :th1

  A `!>` that binds a *term* is a dependent type rather than a polymorphic one, which
  is DH0 or DH1 and not TH1:

      iex> source = "thf(n, type, nat: $tType). thf(f, type, fin: nat > $tType)."
      iex> {:ok, file, []} = Tptp.from_string(source)
      iex> Tptp.Query.dialect(file)
      :dh0
  """
  @spec dialect(Tptp.File.t() | Tptp.Unit.t()) :: dialect()
  def dialect(subject), do: subject |> features() |> from_features()

  @doc """
  Returns the features the file uses, as recorded by the lint traversal.

  A type quantifier produces either `:polymorphic` or `:dependent` according to
  what it binds rather than to the quantifier itself; see `Tptp.Lint.Collect`.

  Use this where the dialect alone is insufficiently specific. A consumer selecting
  a prover may need to know that a TF0 problem uses arithmetic, which does not
  affect its dialect.

      iex> {:ok, file, []} = Tptp.from_string("thf(a, type, g: !>[A: $tType]: (A > A)).")
      iex> file |> Tptp.Query.features() |> Enum.sort()
      [:polymorphic, :thf, :typed]
  """
  @spec features(Tptp.File.t() | Tptp.Unit.t()) :: [atom()]
  def features(subject), do: subject |> table() |> Map.fetch!(:features) |> MapSet.to_list()

  @doc """
  Returns the symbol table without applying any rule.

  The table constructed by `Tptp.Lint`, for consumers requiring the declarations and
  observed arities without the diagnostics.

  Keyed by `Tptp.Node.value/1`, the atomic word, rather than by the spelling, so
  that `'p'` and `p` are the single symbol the BNF defines them to be. A signature
  derived from this table inherits that identity; keying on the spelling instead
  yields two constants that never unify.

      iex> {:ok, file, []} = Tptp.from_string("tff(t, type, 'p': $i > $o). tff(a, axiom, p(x)).")
      iex> file |> Tptp.Query.symbols() |> Map.keys() |> Enum.sort()
      ["p", "x"]
  """
  @spec symbols(Tptp.File.t() | Tptp.Unit.t()) :: %{binary() => Table.symbol()}
  def symbols(subject), do: subject |> table() |> Map.fetch!(:symbols)

  @doc """
  Returns the dialect implied by a set of features.

  Separated from `dialect/1` so that the mapping can be read and tested
  independently.

      iex> Tptp.Query.from_features([:fof])
      :fof
      iex> Tptp.Query.from_features([:tff, :typed, :polymorphic])
      :tf1
  """
  @spec from_features(Enumerable.t()) :: dialect()
  def from_features(features) do
    set = MapSet.new(features)

    (non_classical(set) ++ higher_order(set) ++ first_order(set))
    |> Enum.find_value(:unknown, fn {dialect, applies} -> applies && dialect end)
  end

  # Each family is listed widest first, and the families in the order a file is
  # claimed: a non-classical higher-order file is NHF rather than TH1, and a THF file
  # using nothing but first-order syntax is still THF.
  defp non_classical(set) do
    [
      {:nhf, has?(set, :thf) and has?(set, :non_classical)},
      {:nxf, has?(set, :non_classical)}
    ]
  end

  defp higher_order(set) do
    [
      {:dh1, has?(set, :thf) and has?(set, :dependent) and has?(set, :polymorphic)},
      {:dh0, has?(set, :thf) and has?(set, :dependent)},
      {:th1, has?(set, :thf) and (has?(set, :th1) or has?(set, :polymorphic))},
      {:th0, has?(set, :thf)}
    ]
  end

  defp first_order(set) do
    [
      {:tx1, tfx?(set) and has?(set, :polymorphic)},
      {:tx0, tfx?(set)},
      {:tf1, has?(set, :tff) and has?(set, :polymorphic)},
      {:tf0, has?(set, :tff)},
      {:tcf, has?(set, :tcf)},
      {:fof, has?(set, :fof)},
      {:cnf, has?(set, :cnf)}
    ]
  end

  @doc """
  Returns whether every file of one dialect is also a file of another.

  A partial order. The TPTP dialects are not linearly ordered: TCF is typed clause
  form, and TXF and the non-classical languages are separate branches, so there
  exist incomparable pairs. A TH1 file is not an NXF file and an NXF file is not a
  TH1 file.

      iex> Tptp.Query.within?(:fof, :th0)
      true
      iex> Tptp.Query.within?(:th1, :fof)
      false

      iex> {Tptp.Query.within?(:th1, :nxf), Tptp.Query.within?(:nxf, :th1)}
      {false, false}

  ## Provenance

  The vendored BNF does not state this relation. Each language has its own
  nonterminals and the grammar makes no claim about containment, so the relation is
  a hand-written table: `@extends` records immediate edges only and is closed
  transitively at compile time.

  It is therefore a judgement of the same kind as the SZS `isa` hierarchy, which
  `Tptp.Szs.Ontology` declines to model. The distinction is the use to which the
  answer is put. An SZS precedence would constitute a claim about the meaning of a
  prover's result. This relation determines only which analyzers
  `Tptp.Analyzer.run_all/3` offers a file to, where an error causes an analyzer to
  run that should have been skipped. An analyzer requiring no such inference can
  decline it; see `t:Tptp.Analyzer.gate/0` and its `{:exactly, dialects}` form.

  It is not a basis for deciding whether a given prover accepts a file.

  Being partial, it is not a comparator. Use `rank/1` for ordering.
  """
  @spec within?(dialect(), dialect()) :: boolean()
  def within?(inner, outer) do
    outer in Map.fetch!(@closure, inner)
  end

  @doc """
  Returns a dialect's position in a stable listing order, approximately narrowest
  to widest.

  Intended for ordering a table of dialects. Unlike `within?/2` it is total, and it
  asserts nothing about containment: `rank(:tcf) < rank(:tf1)` determines their
  order in a report only.

      iex> Tptp.Query.rank(:cnf) < Tptp.Query.rank(:th1)
      true
  """
  @spec rank(dialect()) :: non_neg_integer()
  def rank(dialect), do: Enum.find_index(@order, &(&1 == dialect))

  @doc """
  Returns the dialects in `rank/1` order.

      iex> Tptp.Query.dialects() |> Enum.take(3)
      [:unknown, :cnf, :fof]
  """
  @spec dialects() :: [dialect()]
  def dialects, do: @order

  @doc """
  Returns the roles the file uses, with the number of statements carrying each.

      iex> {:ok, file, []} = Tptp.from_string("fof(a,axiom,p). fof(b,axiom,q). fof(c,conjecture,r).")
      iex> Tptp.Query.roles(file)
      %{"axiom" => 2, "conjecture" => 1}
  """
  @spec roles(Tptp.File.t() | Tptp.Unit.t()) :: %{binary() => pos_integer()}
  def roles(subject) do
    subject
    |> statements()
    |> Enum.flat_map(fn
      {_id, %Annotated{role: role}} -> [role.text]
      {_id, _include} -> []
    end)
    |> Enum.frequencies()
  end

  @doc """
  Returns the conjecture statements.

      iex> {:ok, file, []} = Tptp.from_string("fof(a,axiom,p). fof(g,conjecture,q).")
      iex> file |> Tptp.Query.conjectures() |> Enum.map(& &1.name.text)
      ["g"]
  """
  @spec conjectures(Tptp.File.t() | Tptp.Unit.t()) :: [Annotated.t()]
  def conjectures(subject) do
    subject
    |> statements()
    |> Enum.flat_map(fn
      {_id, %Annotated{role: %{text: text}} = statement}
      when text in ["conjecture", "negated_conjecture"] ->
        [statement]

      {_id, _other} ->
        []
    end)
  end

  defp has?(set, feature), do: MapSet.member?(set, feature)

  defp tfx?(set) do
    has?(set, :tff) and (has?(set, :tuple) or has?(set, :let_or_ite) or has?(set, :subtype))
  end

  defp statements(subject), do: Tptp.Lint.statements(subject)

  defp table(subject), do: Tptp.Lint.table(subject)
end
