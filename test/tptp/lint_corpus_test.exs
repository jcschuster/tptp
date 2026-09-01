defmodule Tptp.LintCorpusTest do
  @moduledoc """
  Gate 6: the lint rules against the real TPTP library.

  The assertion that matters is the plan's: **no rule fires at error severity on a
  conforming library file.** On a pull request this reads one file in eleven and one
  problem in seventeen; `$TPTP_CORPUS_FULL=1` reads all of them, which is what the
  nightly workflow sets and where every count below was taken. A lint rule is only worth having if its findings mean
  something, and a rule that calls the library wrong is wrong itself. Every finding
  below is a warning, and each of the two that survive was chased down to a real
  fact about TPTP rather than left as noise:

    * `TPTP0401` fires on the modal problems that carry a `logic` role, which the
      vendored BNF's `:==` list of the thirteen roles does not mention. A gap
      between the grammar version and the library.
    * `TPTP0503` fires on the machine-generated ITP axiom sets, which repeat
      declarations across files, so a problem pulling in thirty of them defines one
      name thirty times. Ambiguous, and true.
    * `TPTP0402` fires on the modal problems that specify `$modal_system_KB`, which
      the vendored BNF's `<ntf_modal_system>` list — `K`, `M`, `B`, `D`, `S4`, `S5`
      — does not include. The same gap as `TPTP0401`'s, in the other direction.
    * `TPTP0506` fires at `:info` on the problems that state no conjecture. That is
      not a finding about the file being wrong — a satisfiability problem asks
      nothing on purpose — it is the count a consumer would otherwise make itself.

  `TPTP0501` fires freely on an axiom file linted *alone*, because its declarations
  are in a file it does not include; that is why the gate lints units.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Lint
  alias Tptp.Query
  alias Tptp.Test.Corpus
  alias Tptp.Unit

  @moduletag :corpus
  @moduletag timeout: 900_000

  setup_all do
    root = Corpus.root()

    if root == nil do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    problems =
      Corpus.files(every: 17, max_bytes: 1_000_000)
      |> Enum.filter(&(Path.extname(&1) == ".p"))

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
      |> stream(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver)
        Enum.frequencies_by(Lint.run_unit(unit), & &1.code)
      end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _code, a, b -> a + b end))

    IO.puts("\n  #{length(problems)} problems linted as units: #{inspect(counts)}")

    for {code, _count} <- counts do
      assert code in ["TPTP0401", "TPTP0402", "TPTP0503", "TPTP0506"],
             "#{code} fires on the library; either the rule or our reading of TPTP is wrong"
    end
  end

  test "the undeclared-symbol rule is satisfied by an included signature", %{
    problems: problems,
    resolver: resolver
  } do
    noisy =
      problems
      |> stream(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver)

        case unit |> Lint.run_unit(only: [Tptp.Lint.Rules.Declaration]) |> Enum.take(2) do
          [] -> :ok
          found -> {path, Enum.map(found, & &1.message)}
        end
      end)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "the arity rule finds nothing in the library", %{files: files} do
    found =
      files
      |> stream(fn path ->
        {:ok, file, []} = Tptp.from_file(path)

        case Lint.run(file, only: [Tptp.Lint.Rules.Arity]) do
          [] -> :ok
          found -> {path, Enum.map(found, & &1.message)}
        end
      end)
      |> Enum.reject(&(&1 == :ok))

    assert found == []
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

  defp stream(files, fun) do
    files
    |> Task.async_stream(fun,
      max_concurrency: System.schedulers_online(),
      timeout: 900_000,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
