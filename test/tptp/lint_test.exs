defmodule Tptp.LintTest do
  use ExUnit.Case, async: true

  doctest Tptp.Lint
  doctest Tptp.Lint.Collect
  doctest Tptp.Lint.Context
  doctest Tptp.Lint.Rules.Arity

  alias Tptp.Lint

  defp codes(source, options \\ []) do
    {:ok, file, []} = Tptp.from_string(source)
    file |> Lint.run(options) |> Enum.map(& &1.code)
  end

  defp found(source, options \\ []) do
    {:ok, file, []} = Tptp.from_string(source)
    Lint.run(file, options)
  end

  defp table(source) do
    {:ok, file, []} = Tptp.from_string(source)
    Lint.table(file)
  end

  describe "every rule has a positive and a negative case" do
    @cases [
      {Tptp.Lint.Rules.Role, "TPTP0401", "fof(a, wibble, p).", "fof(a, axiom, p)."},
      {Tptp.Lint.Rules.DefinedWord, "TPTP0402", "fof(a, axiom, $wibble(b)).",
       "fof(a, axiom, $less(1, 2))."},
      {Tptp.Lint.Rules.AtomTyping, "TPTP0405", "tff(a, type, p(X)).",
       "tff(a, type, p: $i > $o)."},
      {Tptp.Lint.Rules.Rank1, "TPTP0404", "thf(a, type, f: ($i > !>[A: $tType]: A) > $o).",
       "thf(a, type, g: !>[A: $tType]: (A > A))."},
      {Tptp.Lint.Rules.Declaration, "TPTP0501", "tff(a, axiom, p(b)).",
       "tff(t1, type, p: $i > $o). tff(t2, type, b: $i). tff(a, axiom, p(b))."},
      {Tptp.Lint.Rules.DuplicateName, "TPTP0503", "fof(a, axiom, p). fof(a, axiom, q).",
       "fof(a, axiom, p). fof(b, axiom, q)."},
      {Tptp.Lint.Rules.Parent, "TPTP0504", "fof(a, axiom, p, inference(r, [], [ghost])).",
       "fof(ghost, axiom, q). fof(a, axiom, p, inference(r, [], [ghost]))."},
      {Tptp.Lint.Rules.Arity, "TPTP0505", "fof(a, axiom, p(x)). fof(b, axiom, p(x, y)).",
       "fof(a, axiom, p(x)). fof(b, axiom, p(y))."}
    ]

    for {rule, code, positive, negative} <- @cases do
      @rule rule
      @code code
      @positive positive
      @negative negative

      test "#{inspect(rule)} fires on its positive fixture" do
        assert @code in codes(@positive, only: [@rule]),
               "#{inspect(@rule)} did not fire on #{inspect(@positive)}"
      end

      test "#{inspect(rule)} stays quiet on its negative fixture" do
        assert codes(@negative, only: [@rule]) == [],
               "#{inspect(@rule)} fired on #{inspect(@negative)}"
      end
    end

    test "no construct is reachable from a language that does not have it" do
      for body <- [
            "^[X: $i]: p",
            "f @ x",
            "!! @ p",
            "@@+ @ p"
          ],
          language <- ~w(tff tcf fof cnf) do
        assert {:error, _diagnostics} =
                 Tptp.Parser.statement_from_string("#{language}(a, axiom, #{body}).")
      end
    end

    test "every shipped rule is covered by a fixture pair" do
      covered = MapSet.new(@cases, &elem(&1, 0))

      assert MapSet.new(Lint.rules()) == covered
    end

    test "every shipped rule declares itself" do
      for rule <- Lint.rules() do
        assert is_binary(rule.code())
        assert rule.severity() in [:error, :warning, :info, :hint]
        assert is_binary(rule.describe())
      end
    end

    test "the codes are distinct" do
      codes = Enum.map(Lint.rules(), & &1.code())

      assert codes == Enum.uniq(codes)
    end
  end

  describe "clean input stays quiet" do
    test "an ordinary first-order problem" do
      assert codes("""
             fof(a, axiom, ![X]: (p(X) => q(X))).
             fof(b, axiom, p(c)).
             fof(g, conjecture, q(c)).
             """) == []
    end

    test "a typed problem that declares what it uses" do
      assert codes("""
             tff(p_type, type, p: $i > $o).
             tff(c_type, type, c: $i).
             tff(a, axiom, p(c)).
             """) == []
    end

    test "a higher-order problem with an apply spine" do
      assert codes("""
             thf(f_type, type, f: $i > $i > $o).
             thf(x_type, type, x: $i).
             thf(a, axiom, f @ x @ x).
             """) == []
    end

    test "a polymorphic problem" do
      assert codes("""
             thf(g_type, type, g: !>[A: $tType]: (A > A)).
             thf(a_type, type, a: $i).
             thf(a, axiom, (g @ $i @ a) = a).
             """) == []
    end

    test "an empty file" do
      assert codes("") == []
    end
  end

  describe "the arity rule and polymorphism" do
    test "a first-order clash is reported" do
      assert ["TPTP0505"] = codes("fof(a, axiom, p(x)). fof(b, axiom, p(x, y)).")
    end

    test "an apply spine at two lengths is not" do
      refute "TPTP0505" in codes("""
             thf(f_type, type, f: $i > $i > $o).
             thf(a, axiom, f @ x).
             thf(b, axiom, f @ x @ y).
             """)
    end

    test "a symbol with a polymorphic declared type is exempt" do
      source = """
      tff(g_type, type, g: !>[A: $tType]: (A > A)).
      tff(a, axiom, g(x)).
      tff(b, axiom, g(x, y)).
      """

      refute "TPTP0505" in codes(source)
    end

    test "the arities are recorded even where the rule declines" do
      table =
        table("""
        thf(f_type, type, f: $i > $i > $o).
        thf(a, axiom, f @ x).
        thf(b, axiom, f @ x @ y).
        """)

      assert table.symbols["f"].arities |> MapSet.to_list() |> Enum.sort() == [1, 2]
    end

    test "argument counting handles both list shapes" do
      assert table("fof(a, axiom, p(x, y, z)).").symbols["p"].arities == MapSet.new([3])
      assert table("tff(a, axiom, p(x, y, z)).").symbols["p"].arities == MapSet.new([3])
      assert table("thf(a, axiom, p(x, y, z)).").symbols["p"].arities == MapSet.new([3])
    end

    test "one occurrence is counted once, not once per node that mentions it" do
      assert table("fof(a, axiom, p(b)).").symbols["p"].arities == MapSet.new([1])
      assert table("fof(a, axiom, p).").symbols["p"].arities == MapSet.new([0])
    end
  end

  describe "the symbol table" do
    test "a declaration records the type node without interpreting it" do
      entry = table("tff(d, type, f: $i > $o).").symbols["f"]

      assert entry.declared_at != nil
      assert entry.declared_as.kind == :tff_mapping_type
    end

    test "a variable is never a symbol" do
      table = table("thf(a, axiom, ![X: $i]: (X @ y)).")

      refute Map.has_key?(table.symbols, "X")
    end

    test "atoms in annotations are not symbols" do
      table = table("fof(a, axiom, p, inference(resolution, [status(thm)], [b])).")

      refute Map.has_key?(table.symbols, "resolution")
      refute Map.has_key?(table.symbols, "status")
      assert Map.has_key?(table.symbols, "p")
    end

    test "parents are collected from the source slot" do
      table = table("fof(a, axiom, p, inference(r, [], [b, c])).")

      assert table.parents |> Enum.map(&elem(&1, 0)) |> Enum.sort() == ["b", "c"]
    end
  end

  describe "options" do
    test ":only runs just the named rules" do
      source = "fof(a, wibble, p). fof(a, axiom, q)."

      assert codes(source, only: [Tptp.Lint.Rules.Role]) == ["TPTP0401"]
      assert codes(source, only: [Tptp.Lint.Rules.DuplicateName]) == ["TPTP0503"]
    end

    test ":except drops one" do
      source = "fof(a, wibble, p)."

      assert codes(source) == ["TPTP0401"]
      assert codes(source, except: [Tptp.Lint.Rules.Role]) == []
    end

    test ":suppress drops by code" do
      assert codes("fof(a, wibble, p).", suppress: ["TPTP0401"]) == []
    end

    test ":severity overrides what the rule thinks" do
      [diagnostic] = found("fof(a, wibble, p).", severity: %{"TPTP0401" => :error})

      assert diagnostic.severity == :error
    end

    test "diagnostics come back in reading order" do
      source = "fof(z, wibble, p). fof(y, axiom, $nope). fof(x, alsowibble, r)."
      offsets = source |> found() |> Enum.map(& &1.span.offset)

      assert offsets == Enum.sort(offsets)
    end
  end

  describe "run_unit/2" do
    test "a declaration in an included file satisfies a use in the root" do
      resolver =
        {Tptp.Resolver.Map,
         files: %{
           "sig.ax" => "tff(p_type, type, p: $i > $o). tff(c_type, type, c: $i)."
         }}

      {:ok, unit, []} =
        Tptp.Unit.from_string("include('sig.ax'). tff(a, axiom, p(c)).", resolver: resolver)

      assert Lint.run_unit(unit) == []
    end

    test "linting the root alone reports what the include would have declared" do
      {:ok, file, []} = Tptp.from_string("include('sig.ax'). tff(a, axiom, p(c)).")

      assert "TPTP0501" in (file |> Lint.run() |> Enum.map(& &1.code))
    end

    test "one statement reached twice through a diamond is not a duplicate" do
      resolver =
        {Tptp.Resolver.Map,
         files: %{
           "left.ax" => "include('shared.ax').",
           "right.ax" => "include('shared.ax').",
           "shared.ax" => "fof(only_once, axiom, p)."
         }}

      {:ok, unit, []} =
        Tptp.Unit.from_string("include('left.ax'). include('right.ax').", resolver: resolver)

      assert Lint.run_unit(unit) == []
    end
  end

  describe "duplicate names" do
    test "one finding per name, however many repeats" do
      source = "fof(a, axiom, p). fof(a, axiom, q). fof(a, axiom, r). fof(a, axiom, s)."
      [diagnostic] = found(source, only: [Tptp.Lint.Rules.DuplicateName])

      assert diagnostic.message =~ "names 4 statements"
      assert length(diagnostic.related) == 3
    end

    test "the first occurrence is carried as related" do
      [diagnostic] =
        found("fof(a, axiom, p). fof(a, axiom, q).", only: [Tptp.Lint.Rules.DuplicateName])

      assert [{span, "first named here"}] = diagnostic.related
      assert span.offset == 4
    end
  end
end
