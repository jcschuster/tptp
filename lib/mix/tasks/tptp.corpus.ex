defmodule Mix.Tasks.Tptp.Corpus do
  @shortdoc "Sweep a local TPTP library through the parser and write the report"

  @moduledoc """
  Reads every problem and axiom file of a local TPTP library and writes a report.

      mix tptp.corpus
      mix tptp.corpus --every 5
      mix tptp.corpus --check

  This is a measurement rather than a test. A parser for a standardised language is
  characterised by what it reads, and the report is committed so that a change
  reducing coverage appears as a diff.

  ## Scope

  Each file is read with `Tptp.from_string/2` alone. No `include` is resolved, no
  lint rule is applied and no unit is constructed. Include resolution would read
  further files and count one axiom set once per problem including it, and lint
  findings do not bear on whether the input was parsed. The question is whether a
  file parses, and at what cost.

  A file counts as parsed when the result carries no error-severity diagnostic.
  Warnings do not count against it: an empty quoted atom is TPTP this library reads
  and reports.

  ## Time budget

  Each file is allowed `--timeout` milliseconds of wall clock; one exceeding it is
  terminated and recorded as a timeout rather than allowed to block the sweep. The
  budget is wall time under `--concurrency` workers and is therefore a property of
  the machine as much as of the file. The report records both.

  ## Memory budget

  A file's size does not predict the cost of parsing it. Across the library the
  source ranges from 2.5 to 111 bytes per tree node, a 44-fold spread, since
  `p(a,b)` and a paragraph of prose occupy comparable numbers of bytes and
  different numbers of nodes. Peak heap tracks nodes, at a more uniform 400–950
  bytes each. Budgeting by file size therefore bounds the wrong quantity:
  `SWV535-1.010.p` is 8.1 MB and peaks at 3.2 GB, while `SWW778_1.p` is twice its
  size and peaks at a ninth of that.

  Since the cost is not known in advance, it is bounded during the parse. Each file
  is parsed in its own process under a `max_heap_size` flag, so the ceiling is
  enforced by the VM. The flag counts shared binaries, without which it would
  exclude the source itself: a single reference-counted binary into which every
  leaf's `text` points, and the larger part of what a parse retains. `--heap` is the
  total, divided equally among the workers of a tier, so peak heap across the sweep
  is that total by construction.

  Size determines concurrency, since it predicts wall time adequately: paths are
  grouped into tiers at 1 MB and 4 MB, and each tier runs at its own worker count,
  the largest files at the fewest workers. This is scheduling rather than a bound.

  A file whose parse would exceed its worker's share is terminated and retried alone
  against the whole of `--heap`, so tiering costs no coverage. A file exceeding the
  budget when run alone is reported as `:heap` in the failure table.

  ## Options

    * `--every N` — sweep one file in N. The full sweep is the default; thinning is
      for a local check and its counts are not comparable.
    * `--timeout MS` — per-file budget, default #{60_000}.
    * `--max-bytes N` — skip files larger than this, default 20 MB. In a complete
      TPTP this excludes seventy files, five axiom sets and sixty-five problems,
      which the streaming benchmark reads instead.
    * `--concurrency N` — workers in the smallest tier, default one per scheduler.
      Larger tiers scale down from it.
    * `--heap BYTES` — peak heap across all workers, default 6 GB. Lowering it on a
      smaller machine makes the sweep slower rather than incorrect.
    * `--out PATH` — output path, default `reports/CORPUS.md`.
    * `--check` — write nothing and fail if the committed report's results differ
      from this run. Timings are excluded from the comparison, so only a change in
      what parses can fail it.
  """

  use Mix.Task

  @default_out "reports/CORPUS.md"
  @conventional "/opt/TPTP"
  @default_timeout 60_000
  @default_max_bytes 20_000_000
  @default_heap 6 * 1024 * 1024 * 1024
  @tier_bounds [1_048_576, 4_194_304]
  @theory "use `theory(equality)` as an inference parent. v9.3.1.2 expanded " <>
            "`<source> ::= <general_term>` into a list of alternatives and `theory(...)` " <>
            "is not among them, so the shipped grammar does not admit it. A gap between " <>
            "the BNF release and the library, not a parser one. These are the same " <>
            "demonstration of the annotated-formula syntax written once per dialect, " <>
            "and all four carry the same two statements."

  @known %{
    "SYN000-2.p" => @theory,
    "SYN000+2.p" => @theory,
    "SYN000_2.p" => @theory,
    "SYN000^2.p" => @theory
  }

  @open "<!-- results -->"
  @close "<!-- end results -->"

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

    root = root() || Mix.raise("no TPTP library found; set $TPTP_ROOT to a checkout")
    paths = files(options)

    if paths == [], do: Mix.raise("no problem or axiom files under #{root}")

    report = report(root, paths, options)
    out = Keyword.get(options, :out, @default_out)

    if Keyword.get(options, :check, false), do: check(report, out), else: write(report, out)
  end

  @doc """
  Returns the library files this parser rejects, with the reason for each.

  Keyed by base name. An entry is added only once the failure has been resolved to
  a property of the sources. Every entry is a discrepancy between the vendored BNF
  release and the library distributed alongside it, which a parser generated from
  that BNF is expected to report.

  The report renders each reason beside the failure it explains. The corpus tests
  exclude these files and then assert that each still fails, so an entry that has
  become unnecessary is reported rather than retained.
  """
  @spec known_failures() :: %{binary() => binary()}
  def known_failures, do: @known

  @doc """
  Returns the library root: `$TPTP_ROOT`, `$TPTP` or `/opt/TPTP`, whichever names a
  directory.

  Returns `nil` where none does, which allows the corpus tests to be skipped rather
  than fail on a machine without a copy of the library.
  """
  @spec root() :: Path.t() | nil
  def root do
    candidate = System.get_env("TPTP_ROOT") || System.get_env("TPTP") || @conventional
    if File.dir?(candidate), do: candidate
  end

  @doc """
  Problem and axiom files under `root/0`, thinned and size-capped.

  `:every` takes one file in n and `:max_bytes` skips the enormous axiom sets. The
  sweep and the corpus tests both come through here so that the report and the
  tests are describing the same set of files.
  """
  @spec files(keyword()) :: [Path.t()]
  def files(options \\ []) do
    case root() do
      nil ->
        []

      root ->
        every = Keyword.get(options, :every, 1)
        max_bytes = Keyword.get(options, :max_bytes, @default_max_bytes)

        (Path.wildcard(Path.join([root, "Problems", "*", "*.p"])) ++
           Path.wildcard(Path.join([root, "Axioms", "*.ax"])) ++
           Path.wildcard(Path.join([root, "Axioms", "*", "*.ax"])))
        |> Enum.sort()
        |> Enum.take_every(every)
        |> Enum.filter(&(File.stat!(&1).size <= max_bytes))
    end
  end

  @doc """
  Group paths into size tiers, each with the workers and heap share it runs under.

  Sizes are grouped at `#{inspect(@tier_bounds)}` bytes, ascending, empty tiers
  dropped. The smallest tier gets `:concurrency` workers and each larger one half
  of the tier below, down to one, because a file eight times the size is worth
  proportionally fewer simultaneous parses. Every tier divides the same `:heap`
  between its workers, so peak heap is the same number whichever tier is running.

  Returns `{workers, heap_per_worker, paths}` per tier.
  """
  @spec tiers([Path.t()], keyword()) :: [{pos_integer(), pos_integer(), [Path.t()]}]
  def tiers(paths, options \\ []) do
    ceiling = Keyword.get(options, :concurrency, System.schedulers_online())
    heap = Keyword.get(options, :heap, @default_heap)

    paths
    |> Enum.group_by(&tier(File.stat!(&1).size))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {tier, tier_paths} ->
      workers = max(1, div(ceiling, Bitwise.bsl(1, tier)))
      {workers, div(heap, workers), tier_paths}
    end)
  end

  @doc """
  Run `fun` over `paths`, tier by tier, under a heap ceiling the VM enforces.

  Each file is parsed in its own monitored process carrying a `max_heap_size` flag,
  so a parse that would blow the budget is killed rather than the sweep. A killed
  file is retried alone against the whole `:heap` before being reported as
  `{:exit, :heap}`, so the tiering costs coverage only for a file that cannot be
  read at all.

  Returns `{path, {:ok, value}}` or `{path, {:exit, reason}}` in the order given.
  """
  @spec stream([Path.t()], (Path.t() -> term()), keyword()) :: [{Path.t(), term()}]
  def stream(paths, fun, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    heap = Keyword.get(options, :heap, @default_heap)

    swept =
      paths
      |> tiers(options)
      |> Enum.flat_map(fn {workers, share, tier_paths} ->
        tier_paths
        |> Task.async_stream(&{&1, guarded(&1, fun, share)},
          max_concurrency: workers,
          timeout: timeout,
          on_timeout: :kill_task,
          ordered: true
        )
        |> Enum.zip(tier_paths)
        |> Enum.map(fn
          {{:ok, {path, outcome}}, _path} -> {path, outcome}
          {{:exit, reason}, path} -> {path, {:exit, reason}}
        end)
      end)
      |> Map.new()

    Enum.map(paths, &{&1, retry(&1, Map.fetch!(swept, &1), fun, heap, timeout)})
  end

  @spec retry(Path.t(), term(), (Path.t() -> term()), pos_integer(), timeout()) :: term()
  defp retry(path, {:exit, :killed}, fun, heap, timeout) do
    task = Task.async(fn -> guarded(path, fun, heap) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:exit, :killed}} -> {:exit, :heap}
      {:ok, outcome} -> outcome
      nil -> {:exit, :timeout}
    end
  end

  defp retry(_path, outcome, _fun, _heap, _timeout), do: outcome

  # `include_shared_binaries` is required for the ceiling to bound what the parse
  # retains. A file's source is one reference-counted binary and every leaf's `text`
  # is a sub-binary of it, so an unqualified `max_heap_size` measures the tree and
  # not the source it indexes; a consumer resolving `include` holds one such binary
  # per file in the graph. Counting them overestimates, a shared binary being charged
  # to each process referencing it, which is the conservative direction for a bound
  # intended to keep the machine responsive.
  #
  # The parse runs in a child process so that `max_heap_size` terminates the parse
  # alone: `:kill` is untrappable, and a linked termination would take the sweep with
  # it. The child is therefore monitored, and also linked so that the relationship
  # holds in both directions — when the per-file timeout terminates this worker, the
  # link delivers `:killed` to the child rather than leaving a parse running for a
  # result no longer awaited and still holding its share of the heap. Trapping exits
  # is what prevents the link from defeating the monitor.
  @spec guarded(Path.t(), (Path.t() -> term()), pos_integer()) :: {:ok, term()} | {:exit, term()}
  defp guarded(path, fun, heap) do
    parent = self()
    words = div(heap, :erlang.system_info(:wordsize))
    Process.flag(:trap_exit, true)

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{
          size: words,
          kill: true,
          error_logger: false,
          include_shared_binaries: true
        })

        send(parent, {:swept, self(), fun.(path)})
      end)

    Process.link(pid)

    receive do
      {:swept, ^pid, value} ->
        Process.demonitor(ref, [:flush])
        {:ok, value}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:exit, reason}
    end
  end

  @spec tier(non_neg_integer()) :: non_neg_integer()
  defp tier(size), do: Enum.count(@tier_bounds, &(size > &1))

  defp report(root, paths, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)

    Mix.shell().info("sweeping #{length(paths)} files under #{root} ...")

    started = System.monotonic_time(:millisecond)
    results = sweep(paths, options)
    elapsed = System.monotonic_time(:millisecond) - started

    render(results, %{
      root: root,
      version: version(paths),
      elapsed: elapsed,
      timeout: timeout,
      tiers: tiers(paths, options),
      heap: Keyword.get(options, :heap, @default_heap),
      every: Keyword.get(options, :every, 1),
      max_bytes: Keyword.get(options, :max_bytes, @default_max_bytes)
    })
  end

  defp sweep(paths, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)

    paths
    |> stream(&measure/1, options)
    |> Enum.map(fn
      {_path, {:ok, result}} ->
        result

      {path, {:exit, reason}} ->
        %{
          path: path,
          outcome: if(reason == :heap, do: :heap, else: :timeout),
          micros: timeout * 1000,
          bytes: File.stat!(path).size
        }
    end)
  end

  defp measure(path) do
    source = File.read!(path)
    started = System.monotonic_time(:microsecond)
    outcome = parse(source)

    %{
      path: path,
      outcome: outcome,
      micros: System.monotonic_time(:microsecond) - started,
      bytes: byte_size(source)
    }
  end

  defp parse(source) do
    {:ok, file, _diagnostics} = Tptp.from_string(source)

    if Tptp.File.any_errors?(file), do: {:error, codes(file.diagnostics)}, else: :ok
  end

  defp codes(diagnostics) do
    diagnostics
    |> Enum.filter(&(&1.severity == :error))
    |> Enum.map(& &1.code)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp version(paths) do
    with path when is_binary(path) <- Enum.find(paths, &(Path.extname(&1) == ".p")),
         {:ok, source} <- File.read(path),
         [_whole, version] <- Regex.run(~r/TPTP v([0-9]+(?:\.[0-9]+)*)/, source) do
      version
    else
      _otherwise -> "unknown"
    end
  end

  defp render(results, run) do
    {problems, axioms} = Enum.split_with(results, &(Path.extname(&1.path) == ".p"))

    """
    # Corpus report

    Every problem and axiom file of a local TPTP library, read with
    `Tptp.from_string/2` and nothing else — no `include` resolved, no lint rule run.
    A file counts as parsed when the result carries no error-severity diagnostic;
    warnings do not count against it.

    A file that did not parse is listed below with the diagnostic code that refused
    it, because "did not parse" and "is not TPTP" are different claims and only the
    code says which one this is. Where the answer is known it is written out below
    the table, once per explanation rather than once per file, and it disappears
    from the report along with the failures it explains.

    Regenerate with `mix tptp.corpus`; `mix tptp.corpus --check` fails if the
    results below have gone stale against the library on this machine. The nightly
    workflow sweeps a freshly downloaded release and keeps its own report as an
    artifact, because a count taken from one snapshot of the library says nothing
    about another.

    ## Against the previous toolchain

    The measurement this replaces ran the TH0/TH1 problem set — 5109 problems as it
    counted them — through the toolchain that preceded this library, and recorded
    **628** files that exceeded its parse budget and **221** it could not parse.
    Those are the two numbers the `Timed out` and `Failed` columns below are to be
    read against. The comparison is of coverage, not of speed: the budget, the
    machine and the TPTP release are not the same.

    #{@open}

    ## Results

    | Set | Files | Parsed | Failed | Timed out |
    |---|---:|---:|---:|---:|
    #{row("Problems", problems)}
    #{row("Axioms", axioms)}
    #{row("Total", results)}

    #{higher_order(problems)}

    #{failures(results)}
    #{@close}

    ## This run

    | | |
    |---|---|
    | TPTP | v#{run.version}, at `#{run.root}` |
    | Elixir | #{System.version()} |
    | OTP | #{:erlang.system_info(:otp_release)} |
    | Schedulers | #{System.schedulers_online()} |
    | Workers | #{workers(run.tiers)} |
    | Heap ceiling | #{Float.round(run.heap / 1_073_741_824, 1)} GB |
    | Per-file budget | #{run.timeout / 1000} s |
    | Size cap | #{Float.round(run.max_bytes / 1_048_576, 1)} MB |
    | Thinning | #{thinning(run.every)} |
    | Wall clock | #{Float.round(run.elapsed / 1000, 1)} s |
    | Read | #{megabytes(results)} MB |
    | Throughput | #{throughput(results, run.elapsed)} MB/s |

    ### Slowest files

    | File | Bytes | ms |
    |---|---:|---:|
    #{slowest(results)}
    """
  end

  defp higher_order(problems) do
    marked = Enum.count(problems, &String.contains?(Path.basename(&1.path), "^"))

    """
    The TPTP names a problem's form in its file name, and `^` marks a THF problem:
    #{marked} of the #{length(problems)} problems swept are named that way. That is
    a fact about the names rather than about the contents — only
    `Tptp.Query.dialect/1` answers that — and it is here because the TH0/TH1 set is
    what the comparison above is over.\
    """
  end

  defp workers(tiers) do
    Enum.map_join(tiers, ", ", fn {workers, _share, paths} -> "#{workers} on #{length(paths)}" end)
  end

  defp row(label, results) do
    parsed = Enum.count(results, &(&1.outcome == :ok))
    timed_out = Enum.count(results, &(&1.outcome == :timeout))
    failed = length(results) - parsed - timed_out

    "| #{label} | #{length(results)} | #{parsed} | #{failed} | #{timed_out} |"
  end

  defp failures(results) do
    failed = Enum.reject(results, &(&1.outcome == :ok))

    if failed == [] do
      "Every file parsed."
    else
      rows =
        failed
        |> Enum.sort_by(& &1.path)
        |> Enum.map_join("\n", fn result ->
          "| `#{Path.basename(result.path)}` | #{describe(result.outcome)} |"
        end)

      "### What did not parse\n\n| File | Why |\n|---|---|\n" <> rows <> notes(failed)
    end
  end

  defp thinning(1), do: "none — every file"
  defp thinning(every), do: "one file in #{every}"

  defp notes(failed) do
    known =
      failed
      |> Enum.map(&Path.basename(&1.path))
      |> Enum.sort()
      |> Enum.filter(&Map.has_key?(known_failures(), &1))
      |> Enum.group_by(&Map.fetch!(known_failures(), &1))

    if known == %{} do
      ""
    else
      "\n\n" <>
        Enum.map_join(known, "\n\n", fn {why, names} ->
          "**#{Enum.map_join(names, ", ", &"`#{&1}`")}** #{why}"
        end)
    end
  end

  defp describe(:timeout), do: "timed out"
  defp describe(:heap), do: "exceeded the heap ceiling, alone"
  defp describe({:error, codes}), do: Enum.join(codes, ", ")

  defp megabytes(results) do
    results |> Enum.reduce(0, &(&1.bytes + &2)) |> Kernel./(1_048_576) |> Float.round(1)
  end

  defp throughput(_results, elapsed) when elapsed <= 0, do: "n/a"

  defp throughput(results, elapsed) do
    results
    |> Enum.reduce(0, &(&1.bytes + &2))
    |> Kernel./(1_048_576 * elapsed / 1000)
    |> Float.round(1)
  end

  defp slowest(results) do
    results
    |> Enum.sort_by(&(-&1.micros))
    |> Enum.take(10)
    |> Enum.map_join("\n", fn result ->
      "| `#{Path.basename(result.path)}` | #{result.bytes} | #{Float.round(result.micros / 1000, 1)} |"
    end)
  end

  defp write(report, out) do
    File.write!(out, report)
    Mix.shell().info(summary(report) <> "\nwritten to #{out}")
  end

  defp check(report, out) do
    case File.read(out) do
      {:ok, committed} ->
        if results_of(committed) == results_of(report) do
          Mix.shell().info(summary(report) <> "\n#{out} is current")
        else
          Mix.shell().info(results_of(report))
          Mix.raise("#{out} is stale. Run 'mix tptp.corpus' and commit the result.")
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

  defp summary(report) do
    report
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| Problems |"))
    |> Enum.join("\n")
  end
end
