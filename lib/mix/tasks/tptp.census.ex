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

  A file counts as "outside the base languages" when its dialect is none of
  `cnf`, `fof`, `tf0`, `th0` — that is, it needs polymorphism, arithmetic or a
  higher-order feature to be what it is.

  ## Reading the library

  Each file is read with `Tptp.from_string/2` and nothing else, exactly as
  `mix tptp.corpus` does; the same 20 MB size cap keeps the enormous axiom sets
  out. Run it on its own — it is one heavy pass over the whole library.

  ## Options

    * `--every N` — sweep one file in N. The full sweep is the default.
    * `--timeout MS` — per-file budget, default #{60_000}.
    * `--max-bytes N` — skip files larger than this, default 20 MB.
    * `--concurrency N` — workers, default 4.
    * `--out PATH` — where to write, default `CENSUS.md`.
    * `--check` — write nothing; fail if the committed report's results differ
      from this run's.
  """

  use Mix.Task

  alias Mix.Tasks.Tptp.Corpus

  @default_out "CENSUS.md"
  @default_timeout 60_000
  @default_concurrency 4
  @base_dialects [:unknown, :cnf, :fof, :tf0, :th0]

  @open "<!-- results -->"
  @close "<!-- end results -->"

  @typedoc """
  What one sweep found.

    * `scanned` — files read, parse failures included.
    * `tff_applied` — files with at least one applied `<tff_atomic_type>`.
    * `thf_applied_heuristic` — files with an apply spine in a THF type position.
    * `applied_outside_base` — of the applied files, those whose dialect is not a
      base language.
    * `type_forall` — files using `!>`.
    * `constructors` — each TFF type constructor seen, with the arities it was
      applied at, the domains it appeared in, and how many files used it.
  """
  @type t :: %{
          scanned: non_neg_integer(),
          tff_applied: non_neg_integer(),
          thf_applied_heuristic: non_neg_integer(),
          applied_outside_base: non_neg_integer(),
          type_forall: non_neg_integer(),
          constructors: %{
            optional(binary()) => %{
              arities: [non_neg_integer()],
              domains: [binary()],
              files: non_neg_integer()
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
      render(totals, %{root: root, every: Keyword.get(options, :every, 1), elapsed: elapsed})

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
    timeout = Keyword.get(options, :timeout, @default_timeout)
    concurrency = Keyword.get(options, :concurrency, @default_concurrency)

    paths
    |> Task.async_stream(&per_file/1,
      max_concurrency: concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.reduce(blank(), fn
      {:ok, file}, totals -> merge(totals, file)
      {:exit, _reason}, totals -> %{totals | scanned: totals.scanned + 1}
    end)
    |> finish()
  end

  @doc """
  Render the committed report from a set of totals and the run metadata.
  """
  @spec render(t(), %{root: Path.t(), every: pos_integer(), elapsed: non_neg_integer()}) ::
          binary()
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

    Regenerate with `mix tptp.census`; `mix tptp.census --check` fails if the
    results below have gone stale against the library on this machine.

    #{@open}

    ## Results

    | | Files |
    |---|---:|
    | Scanned | #{totals.scanned} |
    | With an applied type constructor (TFF, exact) | #{totals.tff_applied} |
    | With an apply spine in a THF type (heuristic) | #{totals.thf_applied_heuristic} |
    | — of the applied files, outside the base languages | #{totals.applied_outside_base} |
    | Using `!>` | #{totals.type_forall} |

    ## Constructors

    | Constructor | Arities | Files | Domains |
    |---|---|---:|---|
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
        arity = arity(rest)

        %{
          acc
          | tff_applied: true,
            constructors:
              Map.update(acc.constructors, name, {[arity], acc.domain}, fn {as, ds} ->
                {[arity | as], ds}
              end)
        }

      _node, acc ->
        acc
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

  @spec arity([Tptp.Node.t()]) :: non_neg_integer()
  defp arity([%Tptp.Node{kind: :tff_type_arguments} = arguments]), do: count(arguments)
  defp arity(rest), do: length(rest)

  defp count(%Tptp.Node{kind: :tff_type_arguments, children: [_first, rest]}), do: 1 + count(rest)
  defp count(_node), do: 1

  @spec merge(t(), map()) :: t()
  defp merge(totals, file) do
    outside =
      if file.tff_applied and file.dialect not in @base_dialects, do: 1, else: 0

    %{
      totals
      | scanned: totals.scanned + 1,
        tff_applied: totals.tff_applied + bool(file.tff_applied),
        thf_applied_heuristic: totals.thf_applied_heuristic + bool(file.thf_applied),
        applied_outside_base: totals.applied_outside_base + outside,
        type_forall: totals.type_forall + bool(file.type_forall),
        constructors: merge_constructors(totals.constructors, file.constructors)
    }
  end

  defp merge_constructors(into, from) do
    Enum.reduce(from, into, fn {name, {arities, domain}}, acc ->
      Map.update(acc, name, {MapSet.new(arities), MapSet.new([domain]), 1}, fn {as, ds, files} ->
        {MapSet.union(as, MapSet.new(arities)), MapSet.put(ds, domain), files + 1}
      end)
    end)
  end

  @spec finish(map()) :: t()
  defp finish(totals) do
    constructors =
      Map.new(totals.constructors, fn {name, {arities, domains, files}} ->
        {name,
         %{
           arities: Enum.sort(MapSet.to_list(arities)),
           domains: Enum.sort(MapSet.to_list(domains)),
           files: files
         }}
      end)

    %{totals | constructors: constructors}
  end

  defp blank do
    %{
      scanned: 0,
      tff_applied: 0,
      thf_applied_heuristic: 0,
      applied_outside_base: 0,
      type_forall: 0,
      constructors: %{}
    }
  end

  defp blank_file(domain) do
    %{
      domain: domain,
      dialect: :unknown,
      tff_applied: false,
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

  defp constructor_rows(constructors) when map_size(constructors) == 0, do: "| — | | | |"

  defp constructor_rows(constructors) do
    constructors
    |> Enum.sort_by(fn {name, %{files: files}} -> {-files, name} end)
    |> Enum.map_join("\n", fn {name, entry} ->
      "| `#{name}` | #{Enum.join(entry.arities, ", ")} | #{entry.files} | #{Enum.join(entry.domains, ", ")} |"
    end)
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
