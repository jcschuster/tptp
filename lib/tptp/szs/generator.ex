defmodule Tptp.Szs.Generator do
  @moduledoc """
  Renders `Tptp.Szs.Ontology` from the vendored SZS ontology page.

  `mix tptp.gen` runs this; nothing at runtime does. It mirrors `Tptp.Bnf.Generator`
  in shape and in discipline: the whole vocabulary becomes multi-clause functions on
  binary literals, so every atom in the ontology is created at compile time and
  `Tptp.Szs.Ontology.from_string/1` can be a total function over a closed set
  without `String.to_atom/1` ever being reachable from input.

  ## The three checks it refuses to skip

  A generator that silently emits a short table is worse than one that fails, so
  this raises rather than writes if:

    * fewer than 100 values were recovered — the page has been restructured and
      the strict patterns in `Tptp.Szs.Extract` have stopped matching;
    * two values underscore to the same atom — the `OneWord` names are the identity
      of a value and two of them collapsing would silently merge two rows;
    * a `<status_value>` from the BNF is not a success-ontology mnemonic — the two
      vendored files disagree, which is a fact about the release, not about us.

  The third is the interesting one. `<status_value>` in the BNF is the lower-cased
  three-letter mnemonic, so the grammar and the ontology can be checked against each
  other mechanically, and all 34 of them do line up.

  ## Case is meaningful and is preserved

  `SAT` is `Satisfiable` in the success ontology; `Sat` is `Saturation` in the data
  ontology. `from_mnemonic/1` is therefore case-sensitive, and the lower-case form
  that appears inside a TPTP `status(...)` annotation gets its own entry point,
  `from_status_value/1`, which looks only in the success ontology because that is
  the only place the BNF draws from.
  """

  alias Tptp.Szs.Extract

  @minimum 100
  @source "https://tptp.org/UserDocs/SZSOntology"

  @doc """
  Render the ontology module, and say how many values went into it.
  """
  @spec ontology(Path.t()) :: {binary(), pos_integer()}
  def ontology(path) do
    values = Extract.values!(path)

    check!(values, path)

    {render(values, path), length(values)}
  end

  @spec check!([Extract.value()], Path.t()) :: :ok
  defp check!(values, path) do
    if length(values) < @minimum do
      raise "only #{length(values)} SZS values recovered from #{path}; the page has changed shape"
    end

    collisions =
      values
      |> Enum.group_by(&atom(&1.name))
      |> Enum.filter(fn {_atom, group} -> length(group) > 1 end)

    if collisions != [] do
      raise "SZS names collide as atoms: #{inspect(Enum.map(collisions, &elem(&1, 0)))}"
    end

    stray = Enum.reject(Tptp.Bnf.Vocabulary.status_value_values(), &(&1 in mnemonics(values)))

    if stray != [] do
      raise "BNF <status_value>s absent from the SZS success ontology: #{inspect(stray)}"
    end

    :ok
  end

  @spec mnemonics([Extract.value()]) :: [binary()]
  defp mnemonics(values) do
    for value <- values, value.ontology == :success, do: String.downcase(value.mnemonic)
  end

  @spec render([Extract.value()], Path.t()) :: binary()
  defp render(values, path) do
    """
    defmodule Tptp.Szs.Ontology do
      @moduledoc #{heredoc(moduledoc(values, path))}

    #{types(values)}

    #{constants(values, path)}

    #{lookups(values)}

    #{predicates(values)}
    end
    """
  end

  @spec moduledoc([Extract.value()], Path.t()) :: binary()
  defp moduledoc(values, path) do
    counts =
      for ontology <- [:success, :no_success, :data] do
        "  * `:#{ontology}` — #{Enum.count(values, &(&1.ontology == ontology))} values"
      end

    """
    The SZS status values, generated from the vendored ontology page.

    Do not edit: `mix tptp.gen` writes this from `priv/szs/#{Path.basename(path)}`,
    fetched from <#{@source}>. #{length(values)} values in three ontologies:

    #{Enum.join(counts, "\n")}

    Every atom here is created at compile time, so `from_string/1` and its siblings
    can turn untrusted prover output into an atom without `String.to_atom/1` being
    reachable from input. That is a security property of this library, not a style
    preference; see `Tptp.Token` for the same discipline and the Credo check that
    enforces it.

    ## The `isa` hierarchy is deliberately absent

    There is no `parent/1` or `descendant?/2`. The SZS ontologies are hierarchies —
    an `EquivalentTheorem` isa `Equivalent` isa `Satisfiable` — but that hierarchy is
    published only as three diagrams (`Success.png`, `NoSuccess.png`, `Data.png` at
    the URL above) and appears nowhere in the page's text. Copying a dense diagram
    out by eye would put unverifiable relations into a library whose contract is
    faithfulness to what the sources actually say, so what is here is the partition
    the text does state: which ontology a value belongs to, and which subontology of
    `Success`. If a machine-readable ontology is published, this module gains the
    hierarchy in one regeneration.

    ## Case is meaningful

    `SAT` is `Satisfiable`; `Sat` is `Saturation`. `from_mnemonic/1` is case
    sensitive for that reason. The lower-case three-letter form that appears inside
    a TPTP `status(...)` annotation has its own entry point, `from_status_value/1`,
    which searches only the success ontology — the only place `<status_value>` draws
    from, as the generator checks on every run.
    """
  end

  @spec types([Extract.value()]) :: binary()
  defp types(values) do
    union = values |> Enum.map(&atom_literal(&1.name)) |> Enum.join(" | ")

    """
      @typedoc "One SZS status value. A closed set of #{length(values)} compile-time atoms."
      @type t :: #{union}

      @typedoc "Which of the three SZS ontologies a value belongs to."
      @type ontology :: :success | :no_success | :data

      @typedoc \"\"\"
      The top-level grouping a value sits under.

      Only `Success` has subontologies; the other two sections of the page are flat,
      so their values report the section itself.
      \"\"\"
      @type subontology ::
              :success
              | :semantic_success
              | :type_check_success
              | :verify_success
              | :no_success
              | :data
    """
  end

  @spec constants([Extract.value()], Path.t()) :: binary()
  defp constants(values, path) do
    digest =
      path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    names = Enum.map_join(values, ", ", &atom_literal(&1.name))

    """
      @doc "Every status value, in the order the page lists them."
      @spec values() :: [t()]
      def values, do: [#{names}]

      @doc "How many status values there are."
      @spec count() :: pos_integer()
      def count, do: #{length(values)}

      @doc "Where the ontology was fetched from."
      @spec source() :: binary()
      def source, do: #{inspect(@source)}

      @doc "The vendored copy this module was generated from."
      @spec vendored() :: binary()
      def vendored, do: #{inspect(Path.basename(path))}

      @doc \"\"\"
      A SHA-256 of the vendored page, for consumers that cache across regenerations.

      The page carries no version number, so this stands in for one.
      \"\"\"
      @spec digest() :: binary()
      def digest, do: #{inspect(digest)}
    """
  end

  @spec lookups([Extract.value()]) :: binary()
  defp lookups(values) do
    Enum.join(
      [
        from_string(values),
        name(values),
        from_mnemonic(values),
        from_status_value(values),
        mnemonic(values),
        describe(values),
        ontology_clauses(values),
        subontology(values)
      ],
      "\n"
    )
  end

  @spec from_string([Extract.value()]) :: binary()
  defp from_string(values) do
    clauses =
      clauses(values, fn value ->
        "  def from_string(#{inspect(value.name)}), do: {:ok, #{atom_literal(value.name)}}"
      end)

    """
      @doc \"\"\"
      Turn a `OneWord` status value into an atom, without creating one.

          iex> Tptp.Szs.Ontology.from_string("Theorem")
          {:ok, :theorem}
          iex> Tptp.Szs.Ontology.from_string("NotAStatus")
          :error
      \"\"\"
      @spec from_string(binary()) :: {:ok, t()} | :error
    #{clauses}
      def from_string(word) when is_binary(word), do: :error
    """
  end

  @spec name([Extract.value()]) :: binary()
  defp name(values) do
    clauses =
      clauses(values, fn value ->
        "  def name(#{atom_literal(value.name)}), do: #{inspect(value.name)}"
      end)

    """
      @doc \"\"\"
      The `OneWord` spelling of a status value.

          iex> Tptp.Szs.Ontology.name(:counter_satisfiable)
          "CounterSatisfiable"
      \"\"\"
      @spec name(t()) :: binary()
    #{clauses}
    """
  end

  @spec from_mnemonic([Extract.value()]) :: binary()
  defp from_mnemonic(values) do
    clauses =
      values
      |> Enum.group_by(& &1.mnemonic)
      |> Enum.sort()
      |> Enum.map_join("\n", fn
        {mnemonic, [value]} ->
          "  def from_mnemonic(#{inspect(mnemonic)}), do: {:ok, #{atom_literal(value.name)}}"

        {mnemonic, shared} ->
          atoms = shared |> Enum.map(&atom_literal(&1.name)) |> Enum.join(", ")

          "  def from_mnemonic(#{inspect(mnemonic)}), do: {:ambiguous, [#{atoms}]}"
      end)

    """
      @doc \"\"\"
      Turn a three-letter mnemonic into an atom. Case sensitive, because case is
      meaningful: `SAT` is `Satisfiable` and `Sat` is `Saturation`.

      A mnemonic the page reuses answers `{:ambiguous, values}` rather than picking
      one — `IIn` is both `InfiniteInterpretation` and `IncompleteInterpretation`.

          iex> Tptp.Szs.Ontology.from_mnemonic("THM")
          {:ok, :theorem}
          iex> Tptp.Szs.Ontology.from_mnemonic("IIn")
          {:ambiguous, [:infinite_interpretation, :incomplete_interpretation]}
          iex> Tptp.Szs.Ontology.from_mnemonic("thm")
          :error
      \"\"\"
      @spec from_mnemonic(binary()) :: {:ok, t()} | {:ambiguous, [t()]} | :error
    #{clauses}
      def from_mnemonic(word) when is_binary(word), do: :error
    """
  end

  @spec from_status_value([Extract.value()]) :: binary()
  defp from_status_value(values) do
    clauses =
      values
      |> Enum.filter(&(&1.ontology == :success))
      |> clauses(fn value ->
        spelling = String.downcase(value.mnemonic)

        "  def from_status_value(#{inspect(spelling)}), do: {:ok, #{atom_literal(value.name)}}"
      end)

    """
      @doc \"\"\"
      Turn the lower-case mnemonic inside a TPTP `status(...)` annotation into an atom.

      `<status_value>` in the BNF is the success ontology's mnemonic, lower-cased, and
      `mix tptp.gen` checks on every run that all 34 of them are present here.

          iex> Tptp.Szs.Ontology.from_status_value("thm")
          {:ok, :theorem}
          iex> Tptp.Szs.Ontology.from_status_value("prf")
          :error
      \"\"\"
      @spec from_status_value(binary()) :: {:ok, t()} | :error
    #{clauses}
      def from_status_value(word) when is_binary(word), do: :error
    """
  end

  @spec mnemonic([Extract.value()]) :: binary()
  defp mnemonic(values) do
    clauses =
      clauses(values, fn value ->
        "  def mnemonic(#{atom_literal(value.name)}), do: #{inspect(value.mnemonic)}"
      end)

    """
      @doc \"\"\"
      The three-letter mnemonic for a status value.

          iex> Tptp.Szs.Ontology.mnemonic(:theorem)
          "THM"
      \"\"\"
      @spec mnemonic(t()) :: binary()
    #{clauses}
    """
  end

  @spec describe([Extract.value()]) :: binary()
  defp describe(values) do
    clauses =
      clauses(values, fn value ->
        "  def describe(#{atom_literal(value.name)}), do: #{inspect(value.description)}"
      end)

    """
      @doc \"\"\"
      What the page says a status value means, in its own words.

          iex> Tptp.Szs.Ontology.describe(:theorem)
          "All models of Ax are models of C."
      \"\"\"
      @spec describe(t()) :: binary()
    #{clauses}
    """
  end

  @spec ontology_clauses([Extract.value()]) :: binary()
  defp ontology_clauses(values) do
    clauses =
      clauses(values, fn value ->
        "  def ontology(#{atom_literal(value.name)}), do: :#{value.ontology}"
      end)

    """
      @doc \"\"\"
      Which of the three ontologies a value belongs to.

          iex> Tptp.Szs.Ontology.ontology(:theorem)
          :success
          iex> Tptp.Szs.Ontology.ontology(:timeout)
          :no_success
      \"\"\"
      @spec ontology(t()) :: ontology()
    #{clauses}
    """
  end

  @spec subontology([Extract.value()]) :: binary()
  defp subontology(values) do
    clauses =
      clauses(values, fn value ->
        "  def subontology(#{atom_literal(value.name)}), do: #{atom_literal(value.subontology)}"
      end)

    """
      @doc \"\"\"
      The top-level grouping a value sits under.

          iex> Tptp.Szs.Ontology.subontology(:theorem)
          :semantic_success
          iex> Tptp.Szs.Ontology.subontology(:verified_good)
          :verify_success
      \"\"\"
      @spec subontology(t()) :: subontology()
    #{clauses}
    """
  end

  @spec predicates([Extract.value()]) :: binary()
  defp predicates(values) do
    known = clauses(values, &"  def value?(#{atom_literal(&1.name)}), do: true")

    """
      @doc \"\"\"
      Whether a term is a status value at all.

          iex> Tptp.Szs.Ontology.value?(:theorem)
          true
          iex> Tptp.Szs.Ontology.value?(:banana)
          false
      \"\"\"
      @spec value?(term()) :: boolean()
    #{known}
      def value?(_other), do: false

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
    """
  end

  @spec clauses([Extract.value()], (Extract.value() -> binary())) :: binary()
  defp clauses(values, fun), do: Enum.map_join(values, "\n", fun)

  @spec atom(binary()) :: binary()
  defp atom(name), do: Macro.underscore(name)

  @spec atom_literal(binary()) :: binary()
  defp atom_literal(name), do: ":#{atom(name)}"

  @spec heredoc(binary()) :: binary()
  defp heredoc(body), do: ~s("""\n#{body}""")
end
