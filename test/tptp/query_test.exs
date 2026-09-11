defmodule Tptp.QueryTest do
  use ExUnit.Case, async: true

  doctest Tptp.Query

  alias Tptp.Query

  defp dialect(source) do
    {:ok, file, []} = Tptp.from_string(source)
    Query.dialect(file)
  end

  defp features(source) do
    {:ok, file, []} = Tptp.from_string(source)
    Query.features(file)
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

    test "FOOL makes a TFF file TXF, though none of its forms is a node of its own" do
      # TPTP's own SPC headers call 252 library problems under 1 MB TX0. 201 of them
      # read as TF0 while only tuples, `$let` and sequents were recognised.
      assert dialect("tff(a, axiom, ! [X: $o] : (X | ~ X)).") == :tx0
      assert dialect("tff(a, axiom, p((q))).") == :tx0
      assert dialect("tff(a, axiom, p(q & r)).") == :tx0
      assert dialect("tff(a, axiom, f(a) = (p | q)).") == :tx0
      assert dialect("tff(a, axiom, p($ite(q, a, b))).") == :tx0
      assert dialect("tff(a, axiom, p($true)).") == :tx0
      assert dialect("tff(t, type, says: ($i * $o) > $o).") == :tx0
      assert dialect("tff(t, type, p: $o > $o).") == :tx0

      assert dialect("tff(a, axiom, p(f(a), b) & (a = b)).") == :tf0
      assert dialect("tff(t, type, h: ($i * $i) > $o).") == :tf0
    end

    test "$distinct is TXF's and THF's, not TFF's" do
      # The library's one live use, `SYO561_1.p`, carries an SPC header of TX0.
      assert dialect("tff(a, axiom, $distinct(apple, microsoft)).") == :tx0
      assert dialect("tff(a, axiom, $less(1, 2)).") == :tf0
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
    test "containment runs from cnf outwards" do
      assert Query.within?(:cnf, :fof)
      assert Query.within?(:fof, :th1)
      assert Query.within?(:tf0, :tf1)
      refute Query.within?(:th1, :tf0)
      refute Query.within?(:nhf, :cnf)
    end

    test "a dialect is within itself" do
      for dialect <- Query.dialects() do
        assert Query.within?(dialect, dialect)
      end
    end

    test "unknown is within everything, since it claims nothing" do
      for dialect <- Query.dialects(), do: assert(Query.within?(:unknown, dialect))
    end

    test "the branches are incomparable, which is why this is not a line" do
      # The bug this pins: `within?/2` used to compare positions in a single list, so
      # every pair was related and `[:nxf]` gating accepted TH1 files.
      for {one, other} <- [{:th1, :nxf}, {:th0, :nxf}, {:tcf, :fof}, {:tf1, :tx0}] do
        refute Query.within?(one, other), "#{one} is not within #{other}"
        refute Query.within?(other, one), "#{other} is not within #{one}"
      end
    end

    test "the relation is transitive and antisymmetric" do
      dialects = Query.dialects()

      for a <- dialects, b <- dialects, c <- dialects do
        if Query.within?(a, b) and Query.within?(b, c) do
          assert Query.within?(a, c), "#{a} <= #{b} <= #{c} but not #{a} <= #{c}"
        end
      end

      for a <- dialects, b <- dialects, a != b, Query.within?(a, b) do
        refute Query.within?(b, a), "#{a} and #{b} contain each other"
      end
    end

    test "the typed dialects contain the untyped ones they extend" do
      assert Query.within?(:cnf, :tcf)
      assert Query.within?(:tcf, :tf0)
      assert Query.within?(:tf0, :tx0)
      assert Query.within?(:tx0, :nxf)
      assert Query.within?(:th0, :nhf)
    end
  end

  describe "dependent types are DH0 and DH1, not TH1" do
    # Verified against the TPTP's own SPC header over every THF problem in v9.3.1:
    # 85 DH0 and 46 DH1, detected exactly, with no TH0 or TH1 problem misread as either.
    @nat "thf(n, type, nat: $tType). thf(z, type, zero: nat)."

    test "a type constructor over a term is dependent" do
      assert dialect("#{@nat} thf(f, type, fin: nat > $tType).") == :dh0
    end

    test "a type quantifier over a term is dependent" do
      source =
        "#{@nat} thf(f, type, fin: nat > $tType). " <>
          "thf(x, type, f1: !>[A: nat] : (fin @ A))."

      assert dialect(source) == :dh0
    end

    test "dependent and polymorphic together is DH1" do
      source =
        "#{@nat} thf(f, type, fin: nat > $tType). " <>
          "thf(g, type, g: !>[A: $tType] : (A > A))."

      assert dialect(source) == :dh1
    end

    test "a type constructor over a type is polymorphism, not dependency" do
      assert dialect("thf(l, type, list: $tType > $tType).") == :th1
      refute :dependent in features("thf(l, type, list: $tType > $tType).")
    end

    test "several variables bound at once are still read one at a time" do
      # The bug this pins: two or more bound variables are wrapped in a variable list,
      # and reading the list itself as a binding made its second variable look like a
      # term type. It reported 443 TH1 problems as DH1.
      source = "thf(g, type, g: !>[A: $tType,B: $tType] : (A > B))."

      assert dialect(source) == :th1
      refute :dependent in features(source)
    end

    test "an ordinary term quantifier is neither" do
      source = "thf(p, type, p: $i > $o). thf(a, axiom, ![X: $i] : (p @ X))."

      assert dialect(source) == :th0
      refute :dependent in features(source)
      refute :polymorphic in features(source)
    end

    test "TFF spells $tType with a different node kind and is read the same way" do
      # `$tType` is a `defined_type` in TFF and a `defined_constant` in THF, because
      # THF has no separate type nonterminals. The text is what this asks about.
      assert dialect("tff(g, type, g: !>[A: $tType] : (A > A)).") == :tf1
      assert dialect("tff(g, type, g: !>[A: $tType,B: $tType] : ((A * B) > $o)).") == :tf1
    end
  end

  describe "rank/1" do
    test "is total, so it can sort a table the partial order cannot" do
      ranks = Enum.map(Query.dialects(), &Query.rank/1)

      assert ranks == Enum.sort(ranks)
      assert length(Enum.uniq(ranks)) == length(ranks)
    end

    test "ranks a dialect after everything it contains" do
      for a <- Query.dialects(), b <- Query.dialects(), a != b, Query.within?(a, b) do
        assert Query.rank(a) < Query.rank(b), "#{a} is within #{b} but ranks after it"
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
