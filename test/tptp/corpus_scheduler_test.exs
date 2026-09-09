defmodule Tptp.CorpusSchedulerTest do
  @moduledoc """
  The tiered, heap-bounded scheduler `mix tptp.corpus` and `mix tptp.census` sweep
  through, and that the corpus gates run under.

  These do not need a TPTP library. The scheduler takes an arbitrary function, so
  the heap cases drive it with one that allocates a known amount — a parse's peak
  depends on the file and would make the assertion a measurement rather than a test.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Tptp.Corpus

  @megabyte 1_048_576

  # Roughly 24 MB of live list, well clear of both margins below.
  defp hog(_path), do: length(Enum.to_list(1..1_500_000))

  defp fixtures, do: Path.wildcard("test/fixtures/census/*.p")

  describe "tiers/2" do
    test "groups by size, scales workers down, and divides one heap between them" do
      heap = 6 * 1024 * @megabyte

      tiers =
        Corpus.tiers(["test/fixtures/census/list.p"] ++ fixtures(),
          concurrency: 8,
          heap: heap
        )

      assert [{workers, share, paths}] = tiers
      assert workers == 8, "fixtures are all under 1 MB, so they are all the smallest tier"
      assert share == div(heap, 8)
      assert length(paths) == length(fixtures()) + 1
    end

    test "every tier's workers times its share is the same heap" do
      # Synthesised rather than found: the repo has no 4 MB fixture and should not
      # grow one just to check arithmetic.
      heap = 8 * 1024 * @megabyte

      for ceiling <- [1, 2, 4, 8, 16] do
        [{workers, share, _paths}] = Corpus.tiers(fixtures(), concurrency: ceiling, heap: heap)

        assert workers == ceiling
        assert workers * share <= heap
        assert workers * share > heap - workers
      end
    end

    test "a tier is never given fewer than one worker" do
      [{workers, share, _paths}] = Corpus.tiers(fixtures(), concurrency: 1, heap: @megabyte)

      assert workers == 1
      assert share == @megabyte
    end
  end

  describe "stream/3" do
    test "returns one result per path, in the order given" do
      paths = fixtures()

      results = Corpus.stream(paths, &Path.basename/1, concurrency: 4)

      assert Enum.map(results, &elem(&1, 0)) == paths
      assert Enum.map(results, &elem(&1, 1)) == Enum.map(paths, &{:ok, Path.basename(&1)})
    end

    @tag :capture_log
    test "carries a raise out as an exit rather than taking the sweep down" do
      results =
        Corpus.stream(fixtures(), fn path ->
          if String.ends_with?(path, "broken.p"), do: raise("no"), else: :fine
        end)

      assert Enum.count(results, &match?({_path, {:ok, :fine}}, &1)) == length(fixtures()) - 1
      assert [{path, {:exit, {%RuntimeError{}, _stack}}}] = Enum.reject(results, &ok?/1)
      assert Path.basename(path) == "broken.p"
    end
  end

  describe "the heap ceiling" do
    test "kills the file that exceeds it rather than the sweep, and says so" do
      results = Corpus.stream(fixtures(), &hog/1, concurrency: 1, heap: 4 * @megabyte)

      assert Enum.all?(results, &match?({_path, {:exit, :heap}}, &1)),
             "every file should exceed a 4 MB ceiling, and none should crash the run"
    end

    test "retries alone, against the whole heap, a file its tier share could not hold" do
      # One worker's share is a third of the heap and too small; the whole heap is
      # not. Every file must therefore come back, by way of the retry.
      heap = 96 * @megabyte

      [{workers, share, _paths}] = Corpus.tiers(fixtures(), concurrency: 3, heap: heap)
      assert workers == 3 and share == div(heap, 3)

      results = Corpus.stream(fixtures(), &hog/1, concurrency: 3, heap: heap)

      assert Enum.all?(results, &ok?/1),
             "a file killed on its share must be retried against the whole heap, not lost"
    end

    test "counts the bytes a binary points into, not only the tree" do
      # A refc binary lives off the process heap, so an unqualified ceiling cannot
      # see it — and a file's source is exactly that, with every leaf's `text` a
      # sub-binary of it. A ceiling blind to binaries would let a sweep hold the
      # whole library's megabytes while reporting a small heap.
      results =
        Corpus.stream(fixtures(), fn _path -> byte_size(:binary.copy("x", 64 * @megabyte)) end,
          concurrency: 1,
          heap: 8 * @megabyte
        )

      assert Enum.all?(results, &match?({_path, {:exit, :heap}}, &1))
    end

    test "a file that cannot be read even alone is reported, not retried forever" do
      results = Corpus.stream(fixtures(), &hog/1, concurrency: 3, heap: 6 * @megabyte)

      assert Enum.all?(results, &match?({_path, {:exit, :heap}}, &1))
    end
  end

  describe "the budget the gates hold" do
    test "a gate cannot raise its ceiling by asking for a bigger one" do
      # The regression this pins: two gates were once let out of the division with a
      # ceiling of their own, and the sum across concurrently running modules went
      # from 6 GB to 11 GB. Asking for 64 GB gets the budget and nothing more.
      results =
        Tptp.Test.Corpus.stream(
          Enum.take(fixtures(), 1),
          fn _path -> :ok end,
          heap: 64 * 1024 * @megabyte,
          concurrency: 1
        )

      assert [{_path, {:ok, :ok}}] = results
      assert Tptp.Test.Corpus.heap() == 6 * 1024 * @megabyte
    end

    @tag :capture_log
    test "a gate may lower its ceiling, and the lower one is enforced" do
      # Lowering can only tighten the bound the lock exists to keep, so it is allowed
      # — and it is what lets these tests exercise a kill without allocating 6 GB.
      results =
        Tptp.Test.Corpus.stream(
          Enum.take(fixtures(), 1),
          fn _path -> byte_size(:binary.copy("x", 160 * @megabyte)) end,
          heap: 64 * @megabyte,
          concurrency: 1
        )

      assert [{_path, {:exit, :heap}}] = results
    end

    @tag :capture_log
    test "within_heap separates what would not fit, and still raises on everything else" do
      {values, skipped} =
        Tptp.Test.Corpus.within_heap(
          fixtures(),
          fn _path -> byte_size(:binary.copy("x", 160 * @megabyte)) end,
          heap: 64 * @megabyte,
          concurrency: 1
        )

      assert values == []
      assert skipped == fixtures(), "a heap kill is scope for an expanding gate, not a failure"

      # A raise is a bug wherever it happens, so it is not swallowed as a skip.
      assert_raise RuntimeError, "no", fn ->
        Tptp.Test.Corpus.within_heap(fixtures(), fn _path -> raise "no" end, concurrency: 1)
      end
    end

    test "the budget does not depend on max_cases or on the scheduler count" do
      # The bug this pins: the share used to be the budget over `max_cases`, which
      # defaults to twice the scheduler count — so it shrank as the machine grew, from
      # 375 MB on a two-core runner to 48 MB on sixteen cores, and thirteen of the
      # twenty-nine corpus gates failed on any developer machine worth having.
      assert Tptp.Test.Corpus.heap() == 6 * 1024 * @megabyte
      assert Tptp.Test.Corpus.concurrency() == System.schedulers_online()
    end

    test "sweeps take the lock one at a time" do
      # What replaces the division: the budget is not shared out, it is held, so two
      # sweeps can never be inside `stream/3` at once however many modules ExUnit runs.
      parent = self()

      tasks =
        for id <- 1..4 do
          Task.async(fn ->
            Tptp.Test.Corpus.stream(Enum.take(fixtures(), 1), fn _path ->
              send(parent, {:enter, id})
              Process.sleep(20)
              send(parent, {:leave, id})
              :ok
            end)
          end)
        end

      Task.await_many(tasks, 30_000)

      assert overlapped?(drain([])) == false
    end
  end

  defp drain(seen) do
    receive do
      event -> drain([event | seen])
    after
      0 -> Enum.reverse(seen)
    end
  end

  defp overlapped?(events) do
    Enum.reduce_while(events, 0, fn
      {:enter, _id}, 1 -> {:halt, :overlap}
      {:enter, _id}, 0 -> {:cont, 1}
      {:leave, _id}, depth -> {:cont, max(depth - 1, 0)}
    end) == :overlap
  end

  defp ok?({_path, {:ok, _value}}), do: true
  defp ok?({_path, {:exit, _reason}}), do: false
end
