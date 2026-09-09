defmodule Tptp.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Tptp.Analyzer
  alias Tptp.Test.Analyzers.{Boom, ExactlyTf0, FirstOrderOnly, HigherOrderCap}

  defp analysis(source), do: Tptp.analyze(source)

  test "Tptp.Lint implements the behaviour" do
    assert Tptp.Lint.id() == :tptp_lint
    assert Tptp.Lint.dialects() == :any
    assert is_binary(Tptp.Lint.label())
  end

  test "run_all/3 returns {id, outcome} pairs in the given order" do
    results =
      Analyzer.run_all(analysis("fof(a, axiom, p). fof(a, axiom, q)."), [
        Tptp.Lint,
        FirstOrderOnly
      ])

    assert [{:tptp_lint, lint}, {:test_fof_only, [%{code: "TEST0001"}]}] = results
    assert Enum.any?(lint, &(&1.code == "TPTP0503"))
  end

  test "a [:fof] analyzer runs on FOF and is skipped on TF1" do
    assert [{:test_fof_only, [_]}] =
             Analyzer.run_all(analysis("fof(a, axiom, p)."), [FirstOrderOnly])

    tf1 = analysis("tff(t, type, f: !>[A: $tType]: (A > A)).")
    assert [{:test_fof_only, :skipped}] = Analyzer.run_all(tf1, [FirstOrderOnly])
  end

  test "a [:th0] analyzer accepts a FOF file" do
    assert [{:test_th0_cap, []}] =
             Analyzer.run_all(analysis("fof(a, axiom, p)."), [HigherOrderCap])
  end

  test "a [:th0] analyzer is not offered a non-classical file" do
    # The bug this pins: containment used to be a single line, so every dialect was
    # comparable and an analyzer scoped to one branch was handed the other's files.
    nxf = analysis("tff(spec, logic, $modal == [$modalities == $modal_system_S5]).")

    assert [{:test_th0_cap, :skipped}] = Analyzer.run_all(nxf, [HigherOrderCap])
  end

  test "{:exactly, dialects} declines the containment reasoning" do
    # FOF *is* within TF0, so the bare-list form would run. The exact form is for an
    # analyzer that means the dialect it named and nothing near it.
    assert [{:test_exactly_tf0, :skipped}] =
             Analyzer.run_all(analysis("fof(a, axiom, p)."), [ExactlyTf0])

    tf0 = analysis("tff(t, type, p: $i > $o). tff(a, axiom, p(c)).")
    assert [{:test_exactly_tf0, []}] = Analyzer.run_all(tf0, [ExactlyTf0])
  end

  test "per-analyzer options are keyed by id" do
    source = "fof(a, wibble, p(x)). fof(a, axiom, q)."

    results =
      Analyzer.run_all(analysis(source), [Tptp.Lint], tptp_lint: [only: [Tptp.Lint.Rules.Role]])

    assert [{:tptp_lint, [%{code: "TPTP0401"}]}] = results
  end

  test "an analyzer that raises is caught and named" do
    assert [{:test_boom, [diagnostic]}] = Analyzer.run_all(analysis("fof(a, axiom, p)."), [Boom])
    assert diagnostic.code == "TPTP0800"
    assert diagnostic.severity == :error
    assert diagnostic.message =~ "Boom"
  end
end
