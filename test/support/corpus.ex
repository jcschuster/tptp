defmodule Tptp.Test.Corpus do
  @moduledoc """
  Locates a local TPTP library for the tests tagged `:corpus`.

  Those tests are excluded by default so that a contributor without the library
  can still run `mix test`. Point `$TPTP_ROOT` at a checkout to enable them, or
  rely on the conventional `/opt/TPTP`.

  ## Two sweeps, and which one is running

  A corpus test declares how far it thins the library for a pull request, where
  the whole point is to finish. `$TPTP_CORPUS_FULL=1` overrides every one of those
  to sweep the library entire, and that is what the nightly workflow sets: a check
  that skips four files in five is a check that never looks at four fifths of the
  library, and the only way that stops being a problem is to run the whole thing
  somewhere.

  `:max_bytes` is not thinning and is not overridden. It excludes the seventy files
  a complete TPTP holds above 20 MB — five axiom sets and sixty-five problems, 64 of
  them `HWV` and the last `LCL680+1.020.p`, 4.4 GB between them — which the streaming
  gate reads on purpose and in full.

  File selection itself is `Mix.Tasks.Tptp.Corpus`, so the committed report and
  these tests are describing the same set of files rather than two that drifted.

  ## The files this parser refuses

  `Corpus.known_failures/0` lists the library files that do not
  parse, each chased down to a gap between the vendored BNF release and the library
  that ships beside it. `files/1` leaves them out, because a sweep asserting "every
  file parses" cannot also carry an exception in its result, and
  `Tptp.CorpusTest` asserts separately that each of them still fails. An exception
  that stopped being needed would fail that test rather than sit here.
  """

  alias Mix.Tasks.Tptp.Corpus

  @doc """
  The library root, or `nil` when there is none to test against.
  """
  @spec root() :: Path.t() | nil
  defdelegate root(), to: Mix.Tasks.Tptp.Corpus

  @doc """
  Problem and axiom files, thinned for a pull request unless the full sweep is on.

  `:every` takes one file in n and is ignored when `$TPTP_CORPUS_FULL=1`.
  `:max_bytes` skips the enormous axiom files and always applies.
  """
  @spec files(keyword()) :: [Path.t()]
  def files(options \\ []) do
    options
    |> Keyword.put(:every, every(options))
    |> Corpus.files()
    |> Enum.reject(&Map.has_key?(known_failures(), Path.basename(&1)))
  end

  @doc """
  The library files this parser refuses, and why, keyed by base name.
  """
  @spec known_failures() :: %{binary() => binary()}
  defdelegate known_failures(), to: Mix.Tasks.Tptp.Corpus

  @doc """
  Whether the nightly full sweep is on.
  """
  @spec full?() :: boolean()
  def full?, do: System.get_env("TPTP_CORPUS_FULL") in ["1", "true"]

  @closure_cap 8_000_000

  @doc """
  `files/1`, keeping only those whose whole include closure fits.

  For a gate that calls `Tptp.Unit.from_file/2`. Expanding a unit reads every file
  in the closure and holds all of them, so `files/1`'s `:max_bytes` — which caps the
  root alone — is not the relevant limit and is not close to it: `CSR031+6.p` is
  2701 bytes and includes `CSR002+5.ax`, which is 455 MB. 51 problems include that
  one axiom set and 51 more include a 70 MB one. `:closure` sets the cap,
  #{div(@closure_cap, 1_000_000)} MB by default.

  The 455 MB file has a gate of its own, in `TptpCorpusTest`, which streams it and
  asserts the heap stays flat. That is where a file that size belongs. A gate that
  expands units is after depth, diamonds and name resolution, and can have all three
  from graphs that fit.

  `including: true` keeps only the files that actually include something, for a gate
  whose subject is the graph rather than the files. It is folded in here rather than
  left to the caller because the obvious `Enum.filter(&String.contains?(File.read!(&1), "include("))`
  reads every file in the library in one process, and that is the shape that took
  the machine down.

  A gate that expands units needs one more thing this cannot give it:
  `max_concurrency: 1` on the `from_file/2` call. `Tptp.Include` otherwise resolves
  at `System.schedulers_online()` in processes that `stream/3`'s ceiling does not
  reach, because `max_heap_size` is not inherited. Both gates that expand units
  learned that by taking the machine down.
  """
  @spec expandable(keyword()) :: [Path.t()]
  def expandable(options \\ []) do
    {cap, options} = Keyword.pop(options, :closure, @closure_cap)
    {only_including, options} = Keyword.pop(options, :including, false)
    root = root()

    # Through `stream/3` rather than `Enum.filter/2`, for the reason the sweeps use
    # it: the scan reads every problem and every axiom under the cap, and a file's
    # source is a refc binary that is only freed when the process holding it lets go.
    # Doing twenty thousand of those in the `setup_all` process accumulated all of
    # them and took the machine down before a single test ran. One short-lived
    # process per file frees each as it finishes.
    #
    # A scan that cannot itself be held is not expandable either, so `:heap` reads
    # the same as `false` here.
    scan = fn path ->
      (not only_including or includes(path) != []) and closure_within?(path, root, cap)
    end

    for {path, outcome} <- stream(files(options), scan, []),
        match?({:ok, true}, outcome),
        do: path
  end

  @doc """
  Whether everything `path` would pull in through `include` stays under `cap` bytes.

  The walk reads a file only after its size clears the cap, so the enormous axiom
  sets are excluded on a `stat` and never loaded. Discovery goes through
  `Tptp.stream_string!/2` rather than a regex, so a commented-out `include(...)` —
  and `CSR031+6.p` has one — is not mistaken for a real one.
  """
  @spec closure_within?(Path.t(), Path.t(), pos_integer()) :: boolean()
  def closure_within?(path, root, cap) do
    case closure(path, root, cap, MapSet.new(), 0) do
      :over -> false
      {_total, _seen} -> true
    end
  end

  defp closure(path, root, cap, seen, total) do
    cond do
      MapSet.member?(seen, path) -> {total, seen}
      not File.exists?(path) -> {total, seen}
      total + File.stat!(path).size > cap -> :over
      true -> descend(path, root, cap, MapSet.put(seen, path), total + File.stat!(path).size)
    end
  end

  defp descend(path, root, cap, seen, total) do
    Enum.reduce_while(includes(path), {total, seen}, fn name, {running, visited} ->
      case closure(Path.join(root, name), root, cap, visited, running) do
        :over -> {:halt, :over}
        carried -> {:cont, carried}
      end
    end)
  end

  defp includes(path) do
    path
    |> File.read!()
    |> Tptp.stream_string!()
    |> Enum.flat_map(fn
      {:ok, %Tptp.Statement.Include{file_name: name}, _diagnostics} -> [Tptp.Node.value(name)]
      _otherwise -> []
    end)
  end

  @doc """
  The ExUnit timeout a corpus module should carry: `:infinity`, in both modes.

  A wall-clock limit was never the right guard here, and the argument against it in
  the thinned mode turns out to be the same as in the full one. `stream/3` gives
  every file its own `:timeout` and its own heap ceiling and kills the ones that
  exceed either, so a sweep cannot hang. It can only be slow, and the number of files
  is finite and known, so "slow" has a bound that does not need restating as a clock.

  What finally settled it is that the clock was measuring the wrong interval. Sweeps
  take a lock and run one at a time, so a gate's ExUnit clock starts when the gate is
  *scheduled* and includes however long it waits for the lock. Three gates failed a
  30-minute limit having spent most of it queued, which reports a scheduling decision
  as a test failure and tells nobody anything.

  The outer bound belongs where it can see the whole run: `timeout-minutes` on the CI
  job, which is 330 for the corpus workflow. Locally, the sweep prints as it goes.
  """
  @spec timeout() :: :infinity
  def timeout, do: :infinity

  @budget 6 * 1024 * 1024 * 1024

  @doc """
  Sweep `paths` through `fun` under the same tiered, heap-bounded scheduler the
  report uses, returning `{path, {:ok, value}}` or `{path, {:exit, reason}}`.

  ## Why this and not a bare `Task.async_stream`

  Every corpus module used to open its own stream at `System.schedulers_online()`,
  which meant the suite's real concurrency was ExUnit's `max_cases` *times* that —
  `--max-cases 4` on eight schedulers is thirty-two files being parsed at once, not
  four. Peak heap for a parse runs to gigabytes on the library's denser files, so
  that product is what took the machine down rather than any one file.

  ## One sweep at a time, and why the arithmetic leaves no choice

  A sweep here holds a global lock for its duration, so exactly one runs at a time
  and it gets the whole #{div(@budget, 1024 * 1024 * 1024)} GB. That is not caution.
  It is what the measurements allow, and the measurement is easy to take: run a file
  under a `max_heap_size` and see whether it survives.

  | File | Bytes | Lexes under | Parses under |
  |---|---:|---:|---:|
  | `SWV535-1.010.p` | 8.1 MB | 768 MB | 4 GB |
  | `SYN852-1.p` | 15.7 MB | 1.5 GB | 3 GB |
  | `HWV090-1.p` | 17.2 MB | 1 GB | 1.5 GB |
  | `SWW778_1.p` | 17.6 MB | 128 MB | 384 MB |

  One file under the 20 MB cap wants 4 GB to parse. Two gates sweeping that tier at
  once want 8 GB, and there are six. No division of a 6 GB budget between
  concurrently running modules can be both honest and large enough, so the budget is
  not divided: it is taken.

  ## What the previous scheme got wrong

  It divided both the heap ceiling and the worker ceiling by `max_cases`, on the
  reasoning that dividing both leaves each worker the share it would have had alone.
  The arithmetic is right and the premise is not: `concurrency/0` floors at one, and
  `max_cases` defaults to twice the scheduler count, so the worker count was already
  at the floor and could not divide while the heap kept halving. The share therefore
  *shrank as the machine grew* — 375 MB on a two-core runner, 96 MB on eight cores,
  48 MB on sixteen — and `mix test --only corpus` failed thirteen of twenty-nine
  gates on any developer machine worth having. Nothing about `max_cases` is
  consulted now.

  ## A gate may lower the heap, never raise it

  `:heap` is clamped to the budget rather than defaulted to it, so a gate that knows
  it needs little can say so and no gate can ask for more than is being held. Lowering
  is always safe — it can only tighten the bound the lock is there to keep — while
  raising is the one thing that would make the lock a decoration. A gate that wants
  more parallelism passes `:concurrency` instead, which
  `Mix.Tasks.Tptp.Corpus.tiers/2` divides the budget across — and divides again for
  the larger size tiers, so the biggest files run fewest-at-a-time with the most heap
  each. That tiering is what lets one sweep read both a 2 KB puzzle and a 17 MB
  hardware verification problem without a ceiling that is wrong for both.

  ## The ceiling is not inherited

  `max_heap_size` is a property of one process and says nothing about what that
  process spawns. Library code that opens a stream of its own — `Tptp.Include`
  resolves at `System.schedulers_online()` by default — therefore runs *outside*
  the ceiling, however tightly the caller is bounded. A gate that expands includes
  has to pass `max_concurrency: 1` to keep that work inside the guarded process,
  and the include-graph gate does.
  """
  @spec stream([Path.t()], (Path.t() -> term()), keyword()) :: [{Path.t(), term()}]
  def stream(paths, fun, options \\ []) do
    options =
      options
      |> Keyword.update(:heap, heap(), &min(&1, heap()))
      |> Keyword.put_new(:concurrency, concurrency())

    exclusively(fn -> Corpus.stream(paths, fun, options) end)
  end

  @doc """
  The heap ceiling a corpus sweep may use: the whole budget, because it holds it alone.
  """
  @spec heap() :: pos_integer()
  def heap, do: budget()

  # `$TPTP_CORPUS_HEAP_MB` lowers the whole budget, for a machine with less to give
  # than the one these numbers were taken on. The sweep gets slower — more files are
  # killed on their share and retried alone — rather than wrong.
  defp budget do
    case System.get_env("TPTP_CORPUS_HEAP_MB") do
      nil -> @budget
      megabytes -> String.to_integer(megabytes) * 1024 * 1024
    end
  end

  # `:global.trans/2` is a cluster-wide mutex that ships with OTP, so the lock needs
  # no process to supervise and no entry in `test_helper.exs` that someone can forget.
  # It blocks and retries until the lock is free, which is what a queue of sweeps
  # wants; `timeout/0` is sized to cover the waiting as well as the sweeping.
  @spec exclusively((-> result)) :: result when result: term()
  defp exclusively(fun), do: :global.trans({__MODULE__, self()}, fun)

  @doc """
  The workers one corpus sweep gets by default.

  One per scheduler, the same default `mix tptp.corpus` uses, since the sweep has the
  machine to itself while it holds the lock.
  """
  @spec concurrency() :: pos_integer()
  def concurrency, do: System.schedulers_online()

  @doc """
  `stream/3`, unwrapped to the values, raising if any file did not come back.

  A dropped file must not read as a passing sweep: a gate that asserts "every file
  does X" is worthless if the files that failed to be read at all are silently not
  among them. Timing out or exceeding the heap ceiling is a result the report is
  entitled to record and a test is not entitled to ignore, so it raises here.

  A sweep function that asserts is re-raised with its own stacktrace rather than
  wrapped, so an `ExUnit.AssertionError` from inside the sweep still reports the
  expression that failed instead of an inspected exit reason.
  """
  @spec values([Path.t()], (Path.t() -> term()), keyword()) :: [term()]
  def values(paths, fun, options \\ []) do
    paths
    |> stream(fun, options)
    |> Enum.map(fn
      {_path, {:ok, value}} -> value
      {path, outcome} -> raise_outcome(path, outcome)
    end)
  end

  @doc """
  `values/3`, returning the files too large to hold rather than raising on them.

  Returns `{values, skipped}`. Only the heap ceiling counts as a skip: a timeout or
  a raise still raises, because those are bugs rather than scope.

  For the gates that expand `include` graphs, and only those. A graph that does not
  fit is outside such a gate's scope in the same way an oversized root already is —
  the gate is after depth, diamonds and name resolution, and the 455 MB axiom set
  has a streaming gate of its own. The difference is that no cheap measure of the
  source predicts it, so the ceiling is what discovers it.

  `expandable/1`'s byte cap is a pre-filter, not the guarantee, and it cannot be
  made into one: `CSR025+4.p` includes a 6 MB axiom of 203,713 statements and
  cannot be held, while files several times that size expand comfortably. Source
  bytes predict what a parse costs about as well here as they do in
  `mix tptp.census` — which is to say, across a 44-fold spread, not at all. The
  caller is expected to report what it skipped so that the coverage it gave up is a
  number somebody can read rather than a silence.
  """
  @spec within_heap([Path.t()], (Path.t() -> term()), keyword()) ::
          {[term()], [Path.t()]}
  def within_heap(paths, fun, options \\ []) do
    {values, skipped} =
      paths
      |> stream(fun, options)
      |> Enum.reduce({[], []}, fn
        {_path, {:ok, value}}, {values, skipped} -> {[value | values], skipped}
        {path, {:exit, :heap}}, {values, skipped} -> {values, [path | skipped]}
        {path, outcome}, _acc -> raise_outcome(path, outcome)
      end)

    {Enum.reverse(values), Enum.reverse(skipped)}
  end

  @spec raise_outcome(Path.t(), {:exit, term()}) :: no_return()
  defp raise_outcome(_path, {:exit, {exception, stacktrace}}) when is_exception(exception) do
    reraise(exception, stacktrace)
  end

  defp raise_outcome(path, {:exit, reason}) do
    raise "#{path} did not come back: #{inspect(reason)}"
  end

  defp every(options), do: if(full?(), do: 1, else: Keyword.get(options, :every, 1))
end
