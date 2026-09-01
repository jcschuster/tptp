defmodule Mix.Tasks.Tptp.Corpus do
  @shortdoc "Sweep a local TPTP library through the parser and write the report"

  @moduledoc """
  Read every problem and axiom file of a local TPTP library, and write down what
  happened.

      mix tptp.corpus
      mix tptp.corpus --every 5
      mix tptp.corpus --check

  This is the library's headline measurement rather than a test: a parser for a
  standardised language is worth exactly what it reads, and the honest way to say
  so is a number over the whole published corpus. The report it writes is committed,
  so a change to the parser that costs coverage shows up as a diff rather than as a
  line of CI output nobody reads.

  ## The parser alone

  Each file is read with `Tptp.from_string/2` and nothing else. No `include` is
  resolved, no lint rule runs, no unit is built. That is deliberate: `include`
  resolution reads other files and would count one axiom set once per problem that
  pulls it in, and lint findings are opinions rather than a statement about whether
  the bytes were understood. The question this answers is narrow — *does this file
  parse, and how fast* — and it is the question the rest of the library rests on.

  A file counts as parsed when the result carries no error-severity diagnostic.
  Warnings do not count against it: an empty quoted atom is real TPTP that this
  library reads and complains about, and refusing it would be wrong.

  ## The budget

  Each file gets `--timeout` milliseconds of wall clock, and a file that exceeds it
  is killed and counted as a timeout rather than allowed to stall the sweep. The
  budget is wall time under `--concurrency` workers, so it is a property of the
  machine as much as of the file; the report records both.

  ## Options

    * `--every N` — sweep one file in N. The full sweep is the default and the
      only one whose number means anything; thinning is for a quick local check.
    * `--timeout MS` — per-file budget, default #{60_000}.
    * `--max-bytes N` — skip files larger than this, default 20 MB. In a complete
      TPTP that is seventy files — five axiom sets and sixty-five `HWV` problems,
      3.4 GB between them — and they belong in the streaming benchmark, which
      measures what they are there to measure.
    * `--concurrency N` — workers, default one per scheduler.
    * `--out PATH` — where to write, default `CORPUS.md`.
    * `--check` — write nothing; fail if the committed report's results differ from
      this run's. For CI. Timings are excluded from the comparison, so only a real
      change in what parses can fail it.
  """

  use Mix.Task

  @default_out "CORPUS.md"
  @conventional "/opt/TPTP"
  @default_timeout 60_000
  @default_max_bytes 20_000_000
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
  The library files this parser refuses, and why.

  Keyed by base name. A file lands here only once it has been chased down to a fact
  about the sources rather than left as a failure — every entry so far is a gap
  between the vendored BNF release and the library that ships alongside it, which
  is a thing a parser generated from that BNF is *supposed* to report.

  The report renders these beside the failure they explain, and the corpus tests
  exclude them and then assert that each one still fails, so a stale exception
  cannot sit here quietly.
  """
  @spec known_failures() :: %{binary() => binary()}
  def known_failures, do: @known

  @doc """
  The library root: `$TPTP_ROOT`, `$TPTP`, or `/opt/TPTP`, whichever is a directory.

  `nil` when there is none, which is what lets the corpus tests skip rather than
  fail on a machine that has no copy of the library.
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

  defp report(root, paths, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    concurrency = Keyword.get(options, :concurrency, System.schedulers_online())

    Mix.shell().info("sweeping #{length(paths)} files under #{root} ...")

    started = System.monotonic_time(:millisecond)
    results = sweep(paths, timeout, concurrency)
    elapsed = System.monotonic_time(:millisecond) - started

    render(results, %{
      root: root,
      version: version(paths),
      elapsed: elapsed,
      timeout: timeout,
      concurrency: concurrency,
      every: Keyword.get(options, :every, 1),
      max_bytes: Keyword.get(options, :max_bytes, @default_max_bytes)
    })
  end

  defp sweep(paths, timeout, concurrency) do
    paths
    |> Task.async_stream(&measure/1,
      max_concurrency: concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(paths)
    |> Enum.map(fn
      {{:ok, result}, _path} ->
        result

      {{:exit, :timeout}, path} ->
        %{path: path, outcome: :timeout, micros: timeout * 1000, bytes: File.stat!(path).size}
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
    | Workers | #{run.concurrency} |
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
