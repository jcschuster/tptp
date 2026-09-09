defmodule Tptp.LintCorpusTest do
  @moduledoc """
  Gate 6: the lint rules against the real TPTP library.

  The assertion that matters is the plan's: **no rule fires at error severity on a
  conforming library file.** On a pull request this reads one file in eleven and one
  problem in seventeen; `$TPTP_CORPUS_FULL=1` reads all of them, which is what the
  nightly workflow sets and where every count below was taken. A lint rule is only worth having if its findings mean
  something, and a rule that calls the library wrong is wrong itself. Every finding
  below is a warning, and each of the ones that survive was chased down to a real
  fact about TPTP rather than left as noise:

    * `TPTP0402` and `TPTP0503` below are the only two that fire on a conforming
      library at all. `TPTP0401` used to be a third, on the 354 problems carrying a
      `logic` role, until the role list was corrected against the TPTP page that
      defines that role; it now fires on nothing in the library.
    * `TPTP0503` fires on the machine-generated ITP axiom sets, which repeat
      declarations across files, so a problem pulling in thirty of them defines one
      name thirty times. Ambiguous, and true.
    * `TPTP0402` fires on the modal problems that specify `$modal_system_KB`, which
      the vendored BNF's `<ntf_modal_system>` list — `K`, `M`, `B`, `D`, `S4`, `S5`
      — does not include, and neither does the TPTP language page. Unlike the
      `logic` role, no published TPTP source defines it, so there is nothing to
      correct the list against and the warning stands.
    * `TPTP0506` fires at `:info` on the problems that state no conjecture. That is
      not a finding about the file being wrong — a satisfiability problem asks
      nothing on purpose — it is the count a consumer would otherwise make itself.

  `TPTP0501` fires freely on an axiom file linted *alone*, because its declarations
  are in a file it does not include; that is why the gate lints units. Over whole
  units it fires 517 times across seventeen files, listed in `@known_undeclared`
  with the reason for each — fourteen `TX0` problems that declare one symbol and
  use six, two modal problems, and the TCF syntax demonstration. It fired on 39
  more until `Tptp.Lint.Collect` learned that a `$let` binding declares the name it
  binds, which is the difference between a fact about TPTP and a bug in a rule. The
  full sweep is what found both: at `every: 17` not one of the 56 was ever sampled.

  `TPTP0505` is gone. It reported a symbol applied at two arities, and it fired on
  eleven library files, ten of which were doing something the TPTP explicitly permits
  — "Symbols may be overloaded with different arity signatures, and are treated as
  different symbols" — while the eleventh, `SYN000_4.p`, was a `$let` type binding this
  library was counting as an application at arity zero. Neither was a fact about TPTP.
  The exclusion list that used to sit here went with the rule.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Lint
  alias Tptp.Query
  alias Tptp.Test.Corpus
  alias Tptp.Unit

  @moduletag :corpus
  @moduletag timeout: Corpus.timeout()

  # The seventeen library files that really do use a symbol nothing declares — 517
  # occurrences between them, and every one of them true. The full sweep is what
  # found them: at `every: 17` not one was ever sampled.
  #
  #   * Fourteen are `TX0`. The `SWX` thirteen are SystemOnTPTP verification
  #     problems; they declare a symbol or two and then use `head`, `cons`, `pair2`,
  #     `proj1pair` and the rest with nothing declaring them, `SWX229_1.p` sixty-five
  #     times. `LCL977_1.p` applies `f(X)` the same way, and its own header agrees —
  #     "Number of functors : 0 ( 0 usr; 0 con)".
  #   * `MSC034_1.p` and `MSC035_1.p` are `$modal` problems whose propositional atoms
  #     are never declared. The non-classical extension is the same corner of the BNF
  #     the `TPTP0402` finding above comes from.
  #   * `SYN000-3.p` is the TCF syntax demonstration: eight `tcf` statements and no
  #     `type` statement at all. TCF is a typed dialect, so the rule is right about
  #     it, and the file is a demonstration of syntax rather than a problem.
  #
  # A further 39 `SWW` files were here until `Tptp.Lint.Collect` learned that a
  # `$let` binding declares its names. Those were the rule being wrong, and are
  # fixed rather than listed. The difference between the two groups is the whole
  # point of chasing each one down instead of excluding the lot.
  @known_undeclared ~w(
    LCL977_1.p
    MSC034_1.p MSC035_1.p
    SWX216+1.p SWX228_1.p SWX229_1.p SWX230_1.p SWX231_1.p SWX232_1.p SWX233_1.p
    SWX234_1.p SWX235_1.p SWX236_1.p SWX237_1.p SWX238_1.p SWX239_1.p
    SYN000-3.p
  )

  setup_all do
    root = Corpus.root()

    if root == nil do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    # `expandable/1` and not `files/1`: two of the tests below build units, and a
    # 2 KB problem that includes a 455 MB axiom set is under any root-size cap while
    # being far too large to expand. See `Tptp.Test.Corpus.expandable/1`.
    # Both known lists come out here rather than in one test, because both tests
    # that lint units see their findings: the tally as a code it cannot account for,
    # the undeclared test as a file to explain. The companion test below re-checks
    # every excluded file, so a stale exception fails rather than sits.
    problems =
      Corpus.expandable(every: 17, max_bytes: 1_000_000)
      |> Enum.filter(&(Path.extname(&1) == ".p"))
      |> Enum.reject(&(Path.basename(&1) in @known_undeclared))

    %{
      problems: problems,
      files: Corpus.files(every: 11, max_bytes: 1_000_000),
      resolver: {Tptp.Resolver.Fs, root: root, cwd: false}
    }
  end

  test "no rule reports an error on a library file", %{files: files} do
    errors =
      files
      |> stream(fn path ->
        {:ok, file, []} = Tptp.from_file(path)

        case Enum.filter(Lint.run(file), &(&1.severity == :error)) do
          [] -> :ok
          found -> {path, Enum.map(found, &{&1.code, &1.message})}
        end
      end)
      |> Enum.reject(&(&1 == :ok))

    assert errors == []
  end

  test "linting a whole unit reports only what is really there", %{
    problems: problems,
    resolver: resolver
  } do
    counts =
      problems
      |> expand(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)
        Enum.frequencies_by(Lint.run_unit(unit), & &1.code)
      end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _code, a, b -> a + b end))

    IO.puts("  #{length(problems)} problems selected, linted as units: #{inspect(counts)}")

    for {code, _count} <- counts do
      assert code in ["TPTP0402", "TPTP0503", "TPTP0506"],
             "#{code} fires on the library; either the rule or our reading of TPTP is wrong"
    end
  end

  test "the undeclared-symbol rule is satisfied by an included signature", %{
    problems: problems,
    resolver: resolver
  } do
    noisy =
      problems
      |> expand(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)

        case unit |> Lint.run_unit(only: [Tptp.Lint.Rules.Declaration]) |> Enum.take(2) do
          [] -> :ok
          found -> {path, Enum.map(found, & &1.message)}
        end
      end)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "the files excluded from that rule still have nothing declaring their symbols",
       %{resolver: resolver} do
    # The same guarantee `Mix.Tasks.Tptp.Corpus.known_failures/0` gets: an exception
    # that stopped being needed fails here rather than sitting above unnoticed.
    for name <- @known_undeclared do
      [path] = Path.wildcard(Path.join([Corpus.root(), "**", name]))
      {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)

      assert Lint.run_unit(unit, only: [Tptp.Lint.Rules.Declaration]) != [],
             "#{name} declares its symbols now — drop it from @known_undeclared"
    end
  end

  test "every library file is assigned a dialect", %{files: files} do
    counts =
      files
      |> stream(fn path ->
        {:ok, file, []} = Tptp.from_file(path)
        Query.dialect(file)
      end)
      |> Enum.frequencies()

    IO.puts("  dialects across #{length(files)} files: #{inspect(counts)}")

    assert Map.get(counts, :unknown, 0) < div(length(files), 10),
           "too many files could not be classified"

    for dialect <- [:cnf, :fof, :tf0, :th0] do
      assert Map.get(counts, dialect, 0) > 0, "the sample contains no #{dialect}"
    end
  end

  defp stream(files, fun), do: Corpus.values(files, fun, timeout: 900_000)

  # Only the two tests that build units use this. The others read one file each, so
  # a heap kill there would be a bug rather than a graph out of scope, and `stream/2`
  # is right to raise on it. See `Tptp.Test.Corpus.within_heap/3`.
  defp expand(files, fun) do
    {values, skipped} = Corpus.within_heap(files, fun, timeout: 900_000, concurrency: 1)

    if skipped != [] do
      IO.puts(
        "\n  #{length(skipped)} too large to hold: #{Enum.map_join(skipped, " ", &Path.basename/1)}"
      )
    end

    values
  end
end
