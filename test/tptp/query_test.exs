defmodule Tptp.QueryTest do
  use ExUnit.Case, async: true

  doctest Tptp.Query

  alias Tptp.Query

  defp dialect(source) do
    {:ok, file, []} = Tptp.from_string(source)
    Query.dialect(file)
  end

  describe "dialect/1" do
    test "it reads what the file uses, not what it is labelled" do
      assert dialect("cnf(a, axiom, p | ~q).") == :cnf
      assert dialect("fof(a, axiom, ![X]: p(X)).") == :fof
      assert dialect("tcf(a, axiom, ![X: $i]: p(X)).") == :tcf
    end

    test "a typed first-order file is TF0 until it uses a type quantifier" do
      assert dialect("tff(t, type, f: $i > $o). tff(a, axiom, f(x)).") == :tf0
      assert dialect("tff(t, type, g: !>[A: $tType]: (A > A)).") == :tf1
    end

    test "a THF file using nothing higher-order is still THF" do
      assert dialect("thf(a, axiom, p).") == :th0
    end

    test "TH1 needs a TH1 construct, not just the thf keyword" do
      assert dialect("thf(t, type, f: $i > $o). thf(a, axiom, f @ x).") == :th0
      assert dialect("thf(a, axiom, !! @ p).") == :th1
      assert dialect("thf(t, type, g: !>[A: $tType]: (A > A)).") == :th1
    end

    test "a tuple or a $let makes a TFF file TXF" do
      assert dialect("tff(a, axiom, $let(b: $i, b := c, p(b))).") == :tx0
      assert dialect("tff(a, axiom, [x, y] = z).") == :tx0
    end

    test "a non-classical connective outranks everything" do
      assert dialect("tff(a, axiom, [.] p).") == :nxf
      assert dialect("thf(a, axiom, {$box} @ p).") == :nhf
    end

    test "the widest construct in the file decides" do
      source = """
      fof(a, axiom, p).
      thf(t, type, f: $i > $o).
      thf(b, axiom, !! @ f).
      """

      assert dialect(source) == :th1
    end

    test "an empty file claims nothing" do
      assert dialect("") == :unknown
      assert dialect("% just a comment\n") == :unknown
    end

    test "a unit is judged across everything it includes" do
      resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "thf(x, axiom, !! @ p)."}}

      {:ok, unit, []} =
        Tptp.Unit.from_string("include('a.ax'). fof(b, axiom, q).", resolver: resolver)

      assert Query.dialect(unit) == :th1
    end
  end

  describe "features/1" do
    test "it reports what was used, not one summary atom" do
      {:ok, file, []} = Tptp.from_string("tff(a, axiom, $let(b: $i, b := c, p(b))).")

      features = Query.features(file)

      assert :tff in features
      assert :typed in features
      assert :let_or_ite in features
    end

    test "features and dialect agree" do
      {:ok, file, []} = Tptp.from_string("thf(a, axiom, !! @ p).")

      assert file |> Query.features() |> Query.from_features() == Query.dialect(file)
    end
  end

  describe "within?/2" do
    test "the ordering runs from cnf outwards" do
      assert Query.within?(:cnf, :fof)
      assert Query.within?(:fof, :th1)
      assert Query.within?(:tf0, :tf1)
      refute Query.within?(:th1, :tf0)
      refute Query.within?(:nhf, :cnf)
    end

    test "a dialect is within itself" do
      for dialect <- [:cnf, :fof, :tf0, :th1] do
        assert Query.within?(dialect, dialect)
      end
    end
  end

  describe "the rest" do
    test "roles/1 counts what the file uses" do
      {:ok, file, []} =
        Tptp.from_string("fof(a,axiom,p). fof(b,axiom,q). fof(c,negated_conjecture,r).")

      assert Query.roles(file) == %{"axiom" => 2, "negated_conjecture" => 1}
    end

    test "conjectures/1 finds both spellings" do
      {:ok, file, []} =
        Tptp.from_string("fof(a,axiom,p). fof(b,conjecture,q). fof(c,negated_conjecture,r).")

      assert file |> Query.conjectures() |> Enum.map(& &1.name.text) == ["b", "c"]
    end

    test "symbols/1 hands back the table without opinions" do
      {:ok, file, []} = Tptp.from_string("tff(t, type, f: $i > $o). tff(a, axiom, f(x)).")

      symbols = Query.symbols(file)

      assert symbols["f"].declared_at != nil
      assert symbols["x"].declared_at == nil
    end

    test "an include contributes nothing to the roles of its own file" do
      {:ok, file, []} = Tptp.from_string("include('a.ax'). fof(b, axiom, p).")

      assert Query.roles(file) == %{"axiom" => 1}
    end
  end
end
