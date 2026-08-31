defmodule Tptp.Query do
  @moduledoc """
  Questions about a file or unit that a consumer asks before doing anything with it.

  Chiefly one: **which TPTP dialect is this?** That is what decides where a problem
  can be sent, and answering it by looking at the statement keywords alone is wrong
  in both directions — a `thf` file using nothing but first-order syntax is still
  THF to a prover, and a `tff` file using `!>` needs a TF1 prover rather than a TF0
  one.

  So the answer comes from the features the lint traversal already collected: what
  the file *uses*, not what it is labelled. It costs one walk, shared with the lint
  rules, rather than a pass of its own.
  """

  alias Tptp.Lint.Table
  alias Tptp.Statement.Annotated

  @typedoc """
  The TPTP dialects, narrowest first.

  `:unknown` is what an empty file gets — there is nothing to judge, and guessing
  `:cnf` would be a claim the file does not make.
  """
  @type dialect ::
          :unknown | :cnf | :fof | :tf0 | :tf1 | :tx0 | :tx1 | :tcf | :th0 | :th1 | :nxf | :nhf

  @order [:unknown, :cnf, :fof, :tcf, :tf0, :tf1, :tx0, :tx1, :th0, :th1, :nxf, :nhf]

  @doc """
  The narrowest dialect that accepts everything in the file.

      iex> {:ok, file, []} = Tptp.from_string("cnf(a, axiom, p | ~q).")
      iex> Tptp.Query.dialect(file)
      :cnf

      iex> {:ok, file, []} = Tptp.from_string("tff(a, type, f: $i > $o). tff(b, axiom, f(a)).")
      iex> Tptp.Query.dialect(file)
      :tf0

      iex> {:ok, file, []} = Tptp.from_string("thf(a, axiom, !! @ p).")
      iex> Tptp.Query.dialect(file)
      :th1
  """
  @spec dialect(Tptp.File.t() | Tptp.Unit.t()) :: dialect()
  def dialect(subject), do: subject |> features() |> from_features()

  @doc """
  Every feature the file uses, as the lint traversal saw them.

  Useful when the single dialect atom is too blunt — a consumer routing to a prover
  may care that a TF0 problem uses arithmetic even though that does not change its
  dialect.

      iex> {:ok, file, []} = Tptp.from_string("thf(a, type, g: !>[A: $tType]: (A > A)).")
      iex> file |> Tptp.Query.features() |> Enum.sort()
      [:polymorphic, :thf, :typed]
  """
  @spec features(Tptp.File.t() | Tptp.Unit.t()) :: [atom()]
  def features(subject), do: subject |> table() |> Map.fetch!(:features) |> MapSet.to_list()

  @doc """
  The symbol table, without running any rule.

  The same table `Tptp.Lint` builds, for a consumer that wants the declarations and
  the observed arities and none of the opinions.
  """
  @spec symbols(Tptp.File.t() | Tptp.Unit.t()) :: %{binary() => Table.symbol()}
  def symbols(subject), do: subject |> table() |> Map.fetch!(:symbols)

  @doc """
  The dialect a feature set implies.

  Separated from `dialect/1` so the mapping can be read, tested and disagreed with
  on its own.

      iex> Tptp.Query.from_features([:fof])
      :fof
      iex> Tptp.Query.from_features([:tff, :typed, :polymorphic])
      :tf1
  """
  @spec from_features(Enumerable.t()) :: dialect()
  def from_features(features) do
    set = MapSet.new(features)

    [
      {:nhf, has?(set, :thf) and has?(set, :non_classical)},
      {:nxf, has?(set, :non_classical)},
      {:th1, has?(set, :thf) and (has?(set, :th1) or has?(set, :polymorphic))},
      {:th0, has?(set, :thf)},
      {:tx1, tfx?(set) and has?(set, :polymorphic)},
      {:tx0, tfx?(set)},
      {:tf1, has?(set, :tff) and has?(set, :polymorphic)},
      {:tf0, has?(set, :tff)},
      {:tcf, has?(set, :tcf)},
      {:fof, has?(set, :fof)},
      {:cnf, has?(set, :cnf)}
    ]
    |> Enum.find_value(:unknown, fn {dialect, applies} -> applies && dialect end)
  end

  @doc """
  Whether one dialect is contained in another, by the ordering `dialect/1` uses.

      iex> Tptp.Query.within?(:fof, :th0)
      true
      iex> Tptp.Query.within?(:th1, :fof)
      false
  """
  @spec within?(dialect(), dialect()) :: boolean()
  def within?(inner, outer) do
    Enum.find_index(@order, &(&1 == inner)) <= Enum.find_index(@order, &(&1 == outer))
  end

  @doc """
  The roles a file uses, with how many statements carry each.

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
  The conjecture statements, which is what a prover is being asked about.

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
