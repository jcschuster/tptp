defmodule Tptp.AnalysisTest do
  use ExUnit.Case, async: true

  doctest Tptp.Analysis

  alias Tptp.Analysis

  test "analyze/2 from a binary carries the file, its diagnostics and the table" do
    analysis = Tptp.analyze("tff(t, type, p: $i > $o). tff(a, axiom, p(x)).")

    assert %Analysis{file: %Tptp.File{}, table: %Tptp.Lint.Table{}, line_index: nil} = analysis
    assert is_list(analysis.diagnostics)
  end

  test "a binary that does not parse still returns an Analysis with the explaining diagnostics" do
    analysis = Tptp.analyze("fof(a, axiom, p q).")

    assert %Analysis{} = analysis
    assert Enum.any?(analysis.diagnostics, &(&1.severity == :error))
  end

  test "diagnostics are the sorted union of parse and lint" do
    analysis = Tptp.analyze("fof(a, wibble, p). fof(a, axiom, q).")
    codes = Enum.map(analysis.diagnostics, & &1.code)

    assert "TPTP0401" in codes
    assert "TPTP0503" in codes
    assert analysis.diagnostics == Tptp.Diagnostic.sort(analysis.diagnostics)
  end

  test "analyze/2 accepts an already parsed file and a unit" do
    {:ok, file, []} = Tptp.from_string("fof(a, axiom, p).")
    assert %Analysis{file: ^file} = Tptp.analyze(file)

    {:ok, unit, []} = Tptp.Unit.from_string("fof(a, axiom, p).")
    assert %Analysis{file: %Tptp.Unit{}} = Tptp.analyze(unit)
  end

  describe "dialect/1" do
    test "reads the table without walking again" do
      assert Analysis.dialect(Tptp.analyze("thf(a, axiom, !! @ p).")) == :th1
      assert Analysis.dialect(Tptp.analyze("cnf(a, axiom, p | ~q).")) == :cnf
    end

    test "agrees with Tptp.Query.dialect/1" do
      source = "tff(t, type, f: !>[A: $tType]: (A > A))."
      {:ok, file, []} = Tptp.from_string(source)

      assert Analysis.dialect(Tptp.analyze(source)) == Tptp.Query.dialect(file)
    end
  end

  describe "line index" do
    @two_lines "fof(a, axiom, p).\nfof(b, axiom, q)."

    test "with_line_index/1 fills the field and is idempotent" do
      analysis = Tptp.analyze(@two_lines)
      assert analysis.line_index == nil

      filled = Analysis.with_line_index(analysis)
      assert filled.line_index != nil
      assert Analysis.with_line_index(filled) == filled
    end

    test "line_column/2 works with and without the memoised index" do
      analysis = Tptp.analyze(@two_lines)

      assert Analysis.line_column(analysis, 18) == {2, 1}
      assert Analysis.line_column(Analysis.with_line_index(analysis), 18) == {2, 1}
    end
  end
end
