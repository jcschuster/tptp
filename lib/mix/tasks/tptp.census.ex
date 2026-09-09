defmodule Mix.Tasks.Tptp.Census do
  @shortdoc "Count where a local TPTP library uses applied type constructors"

  @moduledoc """
  Read every problem and axiom file of a local TPTP library and count where it
  applies a type constructor — `list($i)`, `map(A, B)`, `tree @ $i` — and in which
  dialects.

      mix tptp.census
      mix tptp.census --check

  TPTP's type grammar admits type application: `<tff_atomic_type> ::=
  <type_functor>(<tff_type_arguments>)` and, in THF, an apply spine in type
  position. Whether the library actually uses it, how widely and in which
  dialects, is a fact worth having written down rather than guessed. The report is
  committed and kept current the way `CORPUS.md` is: counts, not conclusions.

  ## What is exact and what is a heuristic

  A `<tff_atomic_type>` node is only ever built for an application, so the TFF
  count is exact. THF does not separate a type from a term —
  `<thf_unitary_type> ::= <thf_unitary_formula>` — so the THF figure is a
  heuristic: an apply spine inside a `type`-role statement. It is reported on its
  own line.

  A file counts as outside the base languages when its dialect is none of `cnf`,
  `fof`, `tf0` and `th0`, that is, when it requires polymorphism, arithmetic or a
  higher-order feature. That count refines the TFF row and only
  the TFF row: it is taken over the files an exact `<tff_atomic_type>` was found
  in, so it says nothing about the heuristic's files.

  The heuristic's files are instead broken down by dialect, which indicates whether
  it is identifying types. An all-TH1 distribution indicates that it is; any TH0 in
  the distribution indicates that it is matching something other than polymorphism.

  ## The constructor table is TFF only

  `record_thf/3` sets a boolean and never populates `constructors`. The names,
  arities and domains below therefore come from the exact TFF walk alone, and the
  heuristic's files contribute none of them — `fun`, `list` and `option` are not a
  census of the library's type constructors, they are a census of the ones TFF
  spells in a form the grammar makes unambiguous.

  ## Arity 2 over a type variable

  A constructor applied at arity 1, or at any arity over ground arguments, can be
  monomorphised into a fresh sort by an elaborator: `list($i)` is a sort. A
  constructor applied at arity ≥ 2 with a type variable among its arguments cannot
  be — `fun(A, B)` has to enter type unification as a constructor. That is a fork
  in the road for anything built on this library, so it is counted, twice: once for
  a variable as a direct argument, once for a variable anywhere beneath one, since
  `fun(list(A), $i)` is no more monomorphisable than `fun(A, B)` and the gap
  between the two counts is how much nesting the library actually does.

  ## Reading the library

  Each file is read with `Tptp.from_string/2` and nothing else, exactly as
  `mix tptp.corpus` does; the same 20 MB size cap keeps the enormous axiom sets
  out. Run it separately: it performs one pass over the whole library.

  ## Options

    * `--every N` — sweep one file in N. The full sweep is the default.
    * `--timeout MS` — per-file budget, default 60 s, as `mix tptp.corpus`.
    * `--max-bytes N` — skip files larger than this, default 20 MB.
    * `--concurrency N` — workers in the smallest size tier, default 4.
    * `--heap BYTES` — peak heap across all workers, default 6 GB. See
      `mix help tptp.corpus` for why the budget is heap rather than bytes of source.
    * `--out PATH` — where to write, default `CENSUS.md`.
    * `--check` — write nothing; fail if the committed report's results differ
      from this run's.
  """

  use Mix.Task

  alias Mix.Tasks.Tptp.Corpus

  @default_out "CENSUS.md"
  @default_concurrency 4
  @base_dialects [:unknown, :cnf, :fof, :tf0, :th0]

  @open "<!-- results -->"
  @close "<!-- end results -->"

  @typedoc """
  What one sweep found.

    * `scanned` — files read, parse failures included.
    * `tff_applied` — files with at least one applied `<tff_atomic_type>`.
    * `applied_outside_base` — of the TFF applied files, those whose dialect is not
      a base language.
    * `var_direct` — of the TFF applied files, those applying a constructor at
      arity ≥ 2 with a type variable as a direct argument.
    * `var_nested` — the same, counting a type variable anywhere beneath an
      argument. `var_direct` is a subset of it.
    * `thf_applied_heuristic` — files with an apply spine in a THF type position.
    * `thf_dialects` — those files by dialect, indicating whether the heuristic is
      identifying types.
    * `type_forall` — files using `!>`.
    * `constructors` — each TFF type constructor seen, with the arities it was
      applied at, the domains it appeared in, how many files used it, and in how
      many of those it took a type variable at arity ≥ 2, directly and nested.
  """
  @type t :: %{
          scanned: non_neg_integer(),
          tff_applied: non_neg_integer(),
          applied_outside_base: non_neg_integer(),
          var_direct: non_neg_integer(),
          var_nested: non_neg_integer(),
          thf_applied_heuristic: non_neg_integer(),
          thf_dialects: %{optional(Tptp.Query.dialect()) => non_neg_integer()},
          type_forall: non_neg_integer(),
          constructors: %{
            optional(binary()) => %{
              arities: [non_neg_integer()],
              domains: [binary()],
              files: non_neg_integer(),
              var_direct: non_neg_integer(),
              var_nested: non_neg_integer()
            }
          }
        }

  @impl Mix.Task
  def run(argv) do
    {options, []} =
      OptionParser.parse!(argv,
        strict: [
          every: :integer,
          timeout: :integer,
          max_bytes: :integer,
          concurrency: :integer,
          heap: :integer,
          out: :string,
          check: :boolean
        ]
      )

    Mix.Task.run("app.start")

    root = Corpus.root() || Mix.raise("no TPTP library found; set $TPTP_ROOT to a checkout")
    paths = Corpus.files(options)

    if paths == [], do: Mix.raise("no problem or axiom files under #{root}")

    Mix.shell().info("reading #{length(paths)} files under #{root} ...")

    started = System.monotonic_time(:millisecond)
    totals = census(paths, options)
    elapsed = System.monotonic_time(:millisecond) - started

    report =
      render(totals, %{
        root: root,
        every: Keyword.get(options, :every, 1),
        elapsed: elapsed,
        tiers: Corpus.tiers(paths, Keyword.put_new(options, :concurrency, @default_concurrency))
      })

    out = Keyword.get(options, :out, @default_out)

    if Keyword.get(options, :check, false), do: check(report, out), else: write(report, out)
  end

  @doc """
  Sweep a list of problem and axiom paths and total up the type application in
  them.

  Each path is read with `Tptp.from_string/2`; a file that does not parse still
  counts toward `scanned` and contributes nothing else.
  """
  @spec census([Path.t()], keyword()) :: t()
  def census(paths, options \\ []) do
    options = Keyword.put_new(options, :concurrency, @default_concurrency)

    paths
    |> Corpus.stream(&per_file/1, options)
    |> Enum.reduce(blank(), fn
      {_path, {:ok, file}}, totals -> merge(totals, file)
      {_path, {:exit, _reason}}, totals -> %{totals | scanned: totals.scanned + 1}
    end)
    |> finish()
  end

  @doc """
  Render the committed report from a set of totals and the run metadata.
  """
  @spec render(t(), %{
          root: Path.t(),
          every: pos_integer(),
          elapsed: non_neg_integer(),
          tiers: [{pos_integer(), pos_integer(), [Path.t()]}]
        }) :: binary()
  def render(totals, run) do
    """
    # Type application census

    Where a local TPTP library applies a type constructor, and in which dialects.
    Every problem and axiom file is read with `Tptp.from_string/2` and nothing
    else, under the same 20 MB size cap as `mix tptp.corpus`.

    The TFF count is exact — a `<tff_atomic_type>` node is only ever built for an
    application. The THF count is a heuristic, an apply spine in a `type`-role
    statement, because THF does not separate a type from a term. "Outside the base
    languages" means a dialect other than `cnf`, `fof`, `tf0` or `th0`.

    Each `—` row refines the row above it. The TFF rows are taken over the exact
    set and do not describe the heuristic's; the heuristic's files are instead
    divided by dialect, which indicates whether it is identifying types.

    A constructor applied at arity ≥ 2 over a type variable is the one shape an
    elaborator cannot monomorphise into a fresh sort: `list($i)` is a sort,
    `fun(A, B)` is a constructor that has to enter type unification. It is counted
    for a variable as a direct argument and again for a variable anywhere beneath
    one, since `fun(list(A), $i)` is no more monomorphisable than `fun(A, B)`.

    Regenerate with `mix tptp.census`; `mix tptp.census --check` fails if the
    results below have gone stale against the library on this machine.

    #{@open}

    ## Results

    | | Files |
    |---|---:|
    | Scanned | #{totals.scanned} |
    | With an applied type constructor (TFF, exact) | #{totals.tff_applied} |
    | — of those, outside the base languages | #{totals.applied_outside_base} |
    | — of those, at arity ≥ 2 over a type variable | #{totals.var_direct} |
    | — of those, at arity ≥ 2 over a nested type variable | #{totals.var_nested} |
    | With an apply spine in a THF type (heuristic) | #{totals.thf_applied_heuristic} |
    #{dialect_rows(totals.thf_dialects)}
    | Using `!>` | #{totals.type_forall} |

    ## Constructors (TFF)

    From the exact TFF walk alone. `record_thf/3` sets a boolean and never
    populates `constructors`, so the files the THF heuristic found contribute no
    names, no arities and no domains here — this is a census of the constructors
    TFF spells unambiguously, not of the library's constructors. `Var` counts the
    files where the constructor took a type variable as a direct argument at
    arity ≥ 2, `Var nested` where one appeared anywhere beneath an argument.

    | Constructor | Arities | Files | Var | Var nested | Domains |
    |---|---|---:|---:|---:|---|
    #{constructor_rows(totals.constructors)}

    ## Provenance

    | | |
    |---|---|
    | BNF | #{Tptp.bnf_version()} |

    #{@close}

    ## This run

    | | |
    |---|---|
    | Library | `#{run.root}` |
    | Elixir | #{System.version()} |
    | OTP | #{:erlang.system_info(:otp_release)} |
    | Schedulers | #{System.schedulers_online()} |
    | Workers | #{workers(run.tiers)} |
    | Thinning | #{thinning(run.every)} |
    | Wall clock | #{Float.round(run.elapsed / 1000, 1)} s |
    """
  end

  @spec per_file(Path.t()) :: map()
  defp per_file(path) do
    {:ok, file, _diagnostics} = Tptp.from_string(File.read!(path))

    file.statements
    |> Enum.reduce(blank_file(domain(path)), &observe/2)
    |> Map.put(:dialect, Tptp.Query.dialect(file))
  end

  @spec observe(Tptp.Statement.t(), map()) :: map()
  defp observe(%Tptp.Statement.Annotated{} = statement, acc) do
    nodes = Tptp.Node.reduce(statement.formula, [], &[&1 | &2])

    acc
    |> record_tff(nodes)
    |> record_thf(statement, nodes)
    |> record_forall(nodes)
  end

  defp observe(_statement, acc), do: acc

  defp record_tff(acc, nodes) do
    Enum.reduce(nodes, acc, fn
      %Tptp.Node{
        kind: :tff_atomic_type,
        children: [%Tptp.Node{kind: :type_functor} = head | rest]
      },
      acc ->
        name = Tptp.Node.value(head)
        arguments = arguments(rest)
        arity = length(arguments)

        direct = arity >= 2 and Enum.any?(arguments, &(&1.kind == :variable))
        nested = arity >= 2 and Enum.any?(arguments, &variable?/1)

        %{
          acc
          | tff_applied: true,
            var_direct: acc.var_direct or direct,
            var_nested: acc.var_nested or nested,
            constructors:
              Map.update(
                acc.constructors,
                name,
                {[arity], acc.domain, direct, nested},
                fn {as, ds, was_direct, was_nested} ->
                  {[arity | as], ds, was_direct or direct, was_nested or nested}
                end
              )
        }

      _node, acc ->
        acc
    end)
  end

  @spec variable?(Tptp.Node.t()) :: boolean()
  defp variable?(node) do
    Tptp.Node.reduce(node, false, fn
      %Tptp.Node{kind: :variable}, _found -> true
      _node, found -> found
    end)
  end

  defp record_thf(
         acc,
         %Tptp.Statement.Annotated{formula: %Tptp.Node{kind: :thf_atom_typing}},
         nodes
       ) do
    if Enum.any?(nodes, &(&1.kind == :thf_apply_formula)),
      do: %{acc | thf_applied: true},
      else: acc
  end

  defp record_thf(acc, _statement, _nodes), do: acc

  defp record_forall(acc, nodes) do
    if Enum.any?(nodes, &(&1.kind == :type_forall)), do: %{acc | type_forall: true}, else: acc
  end

  @doc false
  @spec arguments([Tptp.Node.t()]) :: [Tptp.Node.t()]
  def arguments([%Tptp.Node{kind: :tff_type_arguments} = arguments]), do: flatten(arguments)
  def arguments(rest), do: rest

  defp flatten(%Tptp.Node{kind: :tff_type_arguments, children: [first, rest]}),
    do: [first | flatten(rest)]

  defp flatten(node), do: [node]

  @spec merge(t(), map()) :: t()
  defp merge(totals, file) do
    outside =
      if file.tff_applied and file.dialect not in @base_dialects, do: 1, else: 0

    thf_dialects =
      if file.thf_applied,
        do: Map.update(totals.thf_dialects, file.dialect, 1, &(&1 + 1)),
        else: totals.thf_dialects

    %{
      totals
      | scanned: totals.scanned + 1,
        tff_applied: totals.tff_applied + bool(file.tff_applied),
        applied_outside_base: totals.applied_outside_base + outside,
        var_direct: totals.var_direct + bool(file.var_direct),
        var_nested: totals.var_nested + bool(file.var_nested),
        thf_applied_heuristic: totals.thf_applied_heuristic + bool(file.thf_applied),
        thf_dialects: thf_dialects,
        type_forall: totals.type_forall + bool(file.type_forall),
        constructors: merge_constructors(totals.constructors, file.constructors)
    }
  end

  defp merge_constructors(into, from) do
    Enum.reduce(from, into, fn {name, {arities, domain, direct, nested}}, acc ->
      blank = {MapSet.new(arities), MapSet.new([domain]), 1, bool(direct), bool(nested)}

      Map.update(acc, name, blank, fn {as, ds, files, ds_direct, ds_nested} ->
        {MapSet.union(as, MapSet.new(arities)), MapSet.put(ds, domain), files + 1,
         ds_direct + bool(direct), ds_nested + bool(nested)}
      end)
    end)
  end

  @spec finish(map()) :: t()
  defp finish(totals) do
    constructors =
      Map.new(totals.constructors, fn {name, {arities, domains, files, direct, nested}} ->
        {name,
         %{
           arities: Enum.sort(MapSet.to_list(arities)),
           domains: Enum.sort(MapSet.to_list(domains)),
           files: files,
           var_direct: direct,
           var_nested: nested
         }}
      end)

    %{totals | constructors: constructors}
  end

  defp blank do
    %{
      scanned: 0,
      tff_applied: 0,
      applied_outside_base: 0,
      var_direct: 0,
      var_nested: 0,
      thf_applied_heuristic: 0,
      thf_dialects: %{},
      type_forall: 0,
      constructors: %{}
    }
  end

  defp blank_file(domain) do
    %{
      domain: domain,
      dialect: :unknown,
      tff_applied: false,
      var_direct: false,
      var_nested: false,
      thf_applied: false,
      type_forall: false,
      constructors: %{}
    }
  end

  defp bool(true), do: 1
  defp bool(false), do: 0

  defp domain(path) do
    case Regex.run(~r/^[A-Z]{3}/, Path.basename(path)) do
      [code] -> code
      nil -> "?"
    end
  end

  defp constructor_rows(constructors) when map_size(constructors) == 0, do: "| — | | | | | |"

  defp constructor_rows(constructors) do
    constructors
    |> Enum.sort_by(fn {name, %{files: files}} -> {-files, name} end)
    |> Enum.map_join("\n", fn {name, entry} ->
      "| `#{name}` | #{Enum.join(entry.arities, ", ")} | #{entry.files} | " <>
        "#{entry.var_direct} | #{entry.var_nested} | #{Enum.join(entry.domains, ", ")} |"
    end)
  end

  @spec dialect_rows(%{optional(Tptp.Query.dialect()) => non_neg_integer()}) :: binary()
  defp dialect_rows(dialects) when map_size(dialects) == 0, do: "| — of those, by dialect | 0 |"

  defp dialect_rows(dialects) do
    dialects
    # `rank/1` and not `within?/2`: the containment relation is partial, so it is not
    # a comparator, and a table needs a total order. `rank/1` is the listing one.
    |> Enum.sort_by(fn {dialect, _count} -> Tptp.Query.rank(dialect) end)
    |> Enum.map_join("\n", fn {dialect, count} ->
      "| — of those, #{dialect |> Atom.to_string() |> String.upcase()} | #{count} |"
    end)
  end

  defp workers(tiers) do
    Enum.map_join(tiers, ", ", fn {workers, _share, paths} -> "#{workers} on #{length(paths)}" end)
  end

  defp thinning(1), do: "none — every file"
  defp thinning(every), do: "one file in #{every}"

  defp write(report, out) do
    File.write!(out, report)
    Mix.shell().info("written to #{out}")
  end

  defp check(report, out) do
    case File.read(out) do
      {:ok, committed} ->
        if results_of(committed) == results_of(report) do
          Mix.shell().info("#{out} is current")
        else
          Mix.shell().info(results_of(report))
          Mix.raise("#{out} is stale. Run 'mix tptp.census' and commit the result.")
        end

      {:error, reason} ->
        Mix.raise("cannot read #{out}: #{:file.format_error(reason)}")
    end
  end

  defp results_of(report) do
    case String.split(report, [@open, @close]) do
      [_before, results, _after] -> String.trim(results)
      _otherwise -> report
    end
  end
end
