defmodule Tptp.UnitCorpusTest do
  @moduledoc """
  Gate 5: the include graph against the real TPTP library.

  A quarter of the problems in the library include something, and their axiom sets
  include further axiom sets, so this is the only place the graph walk meets real
  diamonds, real depth and real names. What it asserts is silence: a conforming
  library resolves without a single diagnostic, and anything else means either the
  search order or our reading of an include name is wrong.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Test.Corpus
  alias Tptp.Unit

  @moduletag :corpus
  @moduletag timeout: Corpus.timeout()

  setup_all do
    root = Corpus.root()

    if root == nil do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    # `expandable/1` and not `files/1`: `:max_bytes` caps the root and not its
    # closure, and a 2 KB problem that includes a 455 MB axiom set is under any root
    # cap while being far too large to expand. `including: true` is the graphs-only
    # filter, done in the same pass rather than by reading every file again here.
    files = Corpus.expandable(every: 5, max_bytes: 2_000_000, including: true)

    IO.puts("\n  #{length(files)} include graphs selected")

    %{files: files, resolver: {Tptp.Resolver.Fs, root: root, cwd: false}}
  end

  test "every include in the library resolves", %{files: files, resolver: resolver} do
    noisy =
      files
      |> stream(fn path ->
        {:ok, unit, diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)

        if diagnostics == [], do: :ok, else: {path, Unit.format_diagnostics(unit)}
      end)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "expansion produces more statements than the root files hold", %{
    files: files,
    resolver: resolver
  } do
    counted =
      files
      |> stream(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)
        root = unit.files[unit.root]

        %{
          roots: length(Tptp.File.formulae(root)),
          expanded: length(Unit.formulae(unit)),
          reads: map_size(unit.files)
        }
      end)

    roots = total(counted, :roots)
    expanded = total(counted, :expanded)
    reads = total(counted, :reads)

    IO.puts(
      "\n  #{length(files)} problems with includes: " <>
        "#{reads} files read, #{roots} root formulae, #{expanded} after expansion"
    )

    assert expanded > roots
    assert reads > length(files)
  end

  test "every span in an expanded unit names a file the unit holds", %{
    files: files,
    resolver: resolver
  } do
    stray =
      files
      |> Enum.take_every(3)
      |> stream(fn path ->
        {:ok, unit, _diagnostics} = Unit.from_file(path, resolver: resolver, max_concurrency: 1)

        unknown =
          for {id, statement} <- Unit.statements(unit),
              not Map.has_key?(unit.files, id),
              do: {id, statement.name.text}

        if unknown == [], do: :ok, else: {path, unknown}
      end)
      |> Enum.reject(&(&1 == :ok))

    assert stray == []
  end

  test "concurrency does not change the graph", %{files: files, resolver: resolver} do
    disagreed =
      files
      |> Enum.take_every(11)
      |> stream(fn path ->
        one = Unit.from_file!(path, resolver: resolver, max_concurrency: 1)
        many = Unit.from_file!(path, resolver: resolver, max_concurrency: 8)

        same =
          one.resolutions == many.resolutions and
            Map.new(one.files, fn {id, file} -> {id, file.path} end) ==
              Map.new(many.files, fn {id, file} -> {id, file.path} end) and
            Unit.statements(one) == Unit.statements(many)

        if same, do: :ok, else: {path, :disagreement}
      end)
      |> Enum.reject(&(&1 == :ok))

    assert disagreed == []
  end

  @spec total([map()], atom()) :: non_neg_integer()
  defp total(counted, key) do
    counted
    |> Enum.reduce(0, fn row, acc -> acc + Map.fetch!(row, key) end)
    |> whole()
  end

  @spec whole(non_neg_integer()) :: non_neg_integer()
  defp whole(number) when is_integer(number) and number >= 0, do: number

  # One worker, not the usual share of them. Expanding a graph is the largest single
  # piece of work in the suite: a unit holds every file in the closure, source and
  # tree. Every call above also passes `max_concurrency: 1`, because `max_heap_size`
  # is not inherited — `Tptp.Include`'s own stream would otherwise resolve at
  # `System.schedulers_online()` in processes outside the ceiling entirely, which is
  # how this gate got past it.
  #
  # A graph that will not fit is reported and skipped rather than failing the gate.
  # See `Tptp.Test.Corpus.within_heap/3` for why no size filter can find those in
  # advance.
  defp stream(files, fun) do
    {values, skipped} = Corpus.within_heap(files, fun, timeout: 600_000, concurrency: 1)

    if skipped != [] do
      IO.puts("\n  #{length(skipped)} too large to hold: #{names(skipped)}")
    end

    values
  end

  defp names(paths), do: paths |> Enum.map_join(" ", &Path.basename/1)
end
