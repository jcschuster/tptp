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

    assert totals.tff_applied == 3
    assert totals.constructors["list"].arities == [1]
    assert totals.constructors["list"].files == 2
    assert totals.constructors["map"].arities == [2]
    assert totals.constructors["map"].files == 1
  end

  test "flags THF applied types by the heuristic, separately" do
    totals = Census.census(@fixtures)
    assert totals.thf_applied_heuristic == 1
  end

  test "counts files using !> and files whose dialect is outside the base languages" do
    totals = Census.census(@fixtures)
    assert totals.type_forall == 1
    assert totals.applied_outside_base == 1
  end

  test "the report carries a checked region and the provenance inside it" do
    totals = Census.census(@fixtures)
    report = Census.render(totals, %{root: "test/fixtures/census", every: 1, elapsed: 0})

    assert report =~ "<!-- results -->"
    assert report =~ "<!-- end results -->"

    [_before, checked, _after] =
      String.split(report, ["<!-- results -->", "<!-- end results -->"])

    assert checked =~ Tptp.bnf_version()
    assert checked =~ "list"
  end
end
