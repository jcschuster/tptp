defmodule Tptp.CensusTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tptp.Census

  @fixtures Path.wildcard("test/fixtures/census/*.p")

  test "counts every file it was handed, parse failures included" do
    totals = Census.census(@fixtures)
    assert totals.scanned == length(@fixtures)
  end

  test "counts TFF applied type constructors exactly, with their arities" do
    totals = Census.census(@fixtures)

    assert totals.tff_applied == 5
    assert totals.constructors["list"].arities == [1]
    assert totals.constructors["list"].files == 3
    assert totals.constructors["map"].arities == [2]
    assert totals.constructors["map"].files == 1
    assert totals.constructors["fun"].arities == [2]
    assert totals.constructors["fun"].files == 2
  end

  test "flags THF applied types by the heuristic, separately" do
    totals = Census.census(@fixtures)
    assert totals.thf_applied_heuristic == 1
  end

  test "splits the heuristic's files by dialect, because that is what says what it caught" do
    totals = Census.census(@fixtures)

    assert totals.thf_dialects == %{th0: 1}
    assert totals.thf_dialects |> Map.values() |> Enum.sum() == totals.thf_applied_heuristic
  end

  test "counts files using !> and files whose dialect is outside the base languages" do
    totals = Census.census(@fixtures)
    assert totals.type_forall == 3
    assert totals.applied_outside_base == 3
  end

  test "counts a constructor at arity >= 2 over a type variable, direct and nested" do
    totals = Census.census(@fixtures)

    # `fun(A, B)` only. `fun(list(A), $i)` hides its variable a level down, and
    # `list(A)` and `map($i, $i)` are each disqualified on one of the two counts.
    assert totals.var_direct == 1
    assert totals.var_nested == 2
    assert totals.var_direct <= totals.var_nested
  end

  test "attributes the arity >= 2 variable counts to the constructor that took one" do
    totals = Census.census(@fixtures)

    assert totals.constructors["fun"].var_direct == 1
    assert totals.constructors["fun"].var_nested == 2

    for name <- ["list", "map"] do
      assert totals.constructors[name].var_direct == 0
      assert totals.constructors[name].var_nested == 0
    end
  end

  test "the report carries a checked region and the provenance inside it" do
    totals = Census.census(@fixtures)
    report = Census.render(totals, run())

    assert report =~ "<!-- results -->"
    assert report =~ "<!-- end results -->"

    [_before, checked, _after] =
      String.split(report, ["<!-- results -->", "<!-- end results -->"])

    assert checked =~ Tptp.bnf_version()
    assert checked =~ "list"
  end

  test "the rendered constructor table says it is TFF, and carries both variable columns" do
    totals = Census.census(@fixtures)
    report = Census.render(totals, run())

    assert report =~ "## Constructors (TFF)"
    assert report =~ "| Constructor | Arities | Files | Var | Var nested | Domains |"
    assert report =~ "| `fun` | 2 | 2 | 1 | 2 |"
  end

  test "every — row in the rendered results refines the row above it" do
    totals = Census.census(@fixtures)
    report = Census.render(totals, run())

    rows =
      report
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| "))
      |> Enum.map(&String.trim/1)

    applied = Enum.find_index(rows, &String.contains?(&1, "(TFF, exact)"))
    heuristic = Enum.find_index(rows, &String.contains?(&1, "(heuristic)"))

    # The TFF refinements sit under the TFF row and above the heuristic's, and the
    # dialect split sits under the heuristic's. Row 3 used to refine row 1 from
    # under row 2, and read as a claim about the THF files.
    for label <- ["outside the base languages", "over a type variable"] do
      index = Enum.find_index(rows, &String.contains?(&1, label))
      assert index > applied and index < heuristic
    end

    assert Enum.find_index(rows, &String.contains?(&1, "TH0")) > heuristic
  end

  defp run do
    %{root: "test/fixtures/census", every: 1, elapsed: 0, tiers: [{1, 1_000_000, @fixtures}]}
  end
end
