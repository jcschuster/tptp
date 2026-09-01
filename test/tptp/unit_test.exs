defmodule Tptp.UnitTest do
  use ExUnit.Case, async: true

  doctest Tptp.Unit

  alias Tptp.Unit

  defp resolver(files), do: {Tptp.Resolver.Map, files: files}

  defp unit(source, files, options \\ []) do
    {:ok, unit, diagnostics} =
      Unit.from_string(source, Keyword.put(options, :resolver, resolver(files)))

    {unit, diagnostics}
  end

  defp names(unit) do
    unit |> Unit.statements() |> Enum.map(fn {_id, statement} -> statement.name.text end)
  end

  defp codes(diagnostics), do: Enum.map(diagnostics, & &1.code)

  describe "expansion" do
    test "an include is replaced by what it names, where it stands" do
      {unit, []} =
        unit("fof(before, axiom, p). include('a.ax'). fof(after_, axiom, r).", %{
          "a.ax" => "fof(inside, axiom, q)."
        })

      assert names(unit) == ["before", "inside", "after_"]
    end

    test "includes nest" do
      {unit, []} =
        unit("include('a.ax').", %{
          "a.ax" => "fof(a, axiom, p). include('b.ax').",
          "b.ax" => "fof(b, axiom, q)."
        })

      assert names(unit) == ["a", "b"]
    end

    test "every included file gets its own id, and spans keep it" do
      {unit, []} = unit("include('a.ax').", %{"a.ax" => "fof(a, axiom, p)."})

      assert map_size(unit.files) == 2
      assert [{included_id, _statement}] = Unit.statements(unit)
      refute included_id == unit.root
    end

    test "the directives themselves are not in the expansion" do
      {unit, []} = unit("include('a.ax').", %{"a.ax" => "fof(a, axiom, p)."})

      refute Enum.any?(Unit.statements(unit), fn {_id, statement} ->
               match?(%Tptp.Statement.Include{}, statement)
             end)
    end

    test "an unresolved include contributes nothing but says so" do
      {unit, diagnostics} = unit("fof(a, axiom, p). include('absent.ax').", %{})

      assert names(unit) == ["a"]
      assert codes(diagnostics) == ["TPTP0601"]
      assert hd(diagnostics).hint =~ "not in the resolver's map"
    end

    test "the default resolver follows nothing, and complains about nothing" do
      {:ok, unit, []} = Unit.from_string("include('a.ax'). fof(b, axiom, p).")

      assert names(unit) == ["b"]
      assert map_size(unit.files) == 1
    end
  end

  describe "the file graph" do
    test "a diamond reads the shared file once" do
      {unit, []} =
        unit("include('left.ax'). include('right.ax').", %{
          "left.ax" => "fof(l, axiom, p). include('shared.ax').",
          "right.ax" => "fof(r, axiom, q). include('shared.ax').",
          "shared.ax" => "fof(s, axiom, t)."
        })

      assert map_size(unit.files) == 4
    end

    test "but expands it wherever it is named" do
      {unit, []} =
        unit("include('left.ax'). include('right.ax').", %{
          "left.ax" => "fof(l, axiom, p). include('shared.ax').",
          "right.ax" => "fof(r, axiom, q). include('shared.ax').",
          "shared.ax" => "fof(s, axiom, t)."
        })

      assert names(unit) == ["l", "s", "r", "s"]
    end

    test "a direct cycle is cut and named" do
      {unit, diagnostics} =
        unit("include('a.ax').", %{"a.ax" => "include('a.ax'). fof(a, axiom, p)."})

      assert names(unit) == ["a"]
      assert codes(diagnostics) == ["TPTP0602"]
      assert hd(diagnostics).hint =~ "->"
    end

    test "an indirect cycle is cut too" do
      {unit, diagnostics} =
        unit("include('a.ax').", %{
          "a.ax" => "fof(a, axiom, p). include('b.ax').",
          "b.ax" => "fof(b, axiom, q). include('a.ax')."
        })

      assert names(unit) == ["a", "b"]
      assert codes(diagnostics) == ["TPTP0602"]
    end

    test "a chain deeper than max_depth stops and says so" do
      files =
        for level <- 1..10, into: %{} do
          {"#{level}.ax", "fof(f#{level}, axiom, p). include('#{level + 1}.ax')."}
        end

      {unit, diagnostics} = unit("include('1.ax').", files, max_depth: 3)

      assert names(unit) == ["f1", "f2", "f3"]
      assert codes(diagnostics) == ["TPTP0605"]
      assert hd(diagnostics).message =~ "nested more than 3 deep"
    end

    test "a resolver that raises becomes a diagnostic, not a crash" do
      defmodule Exploding do
        @behaviour Tptp.Resolver
        @impl true
        def resolve(_name, _from, _options), do: raise("resolver went wrong")
      end

      {:ok, unit, diagnostics} =
        Unit.from_string("fof(a, axiom, p). include('x.ax').", resolver: Exploding)

      assert names(unit) == ["a"]
      assert codes(diagnostics) == ["TPTP0601"]
      assert hd(diagnostics).hint =~ "resolver went wrong"
    end
  end

  describe "selections" do
    test "a selection keeps only the named formulae" do
      {unit, []} =
        unit("include('a.ax', [wanted]).", %{
          "a.ax" => "fof(wanted, axiom, p). fof(unwanted, axiom, q)."
        })

      assert names(unit) == ["wanted"]
    end

    test "a star selection keeps everything" do
      {unit, []} =
        unit("include('a.ax', *).", %{"a.ax" => "fof(one, axiom, p). fof(two, axiom, q)."})

      assert names(unit) == ["one", "two"]
    end

    test "the selection reaches into nested includes" do
      {unit, []} =
        unit("include('a.ax', [deep]).", %{
          "a.ax" => "fof(shallow, axiom, p). include('b.ax').",
          "b.ax" => "fof(deep, axiom, q)."
        })

      assert names(unit) == ["deep"]
    end

    test "a name that is not there is a warning, not an error" do
      {unit, [diagnostic]} =
        unit("include('a.ax', [absent]).", %{"a.ax" => "fof(present, axiom, p)."})

      assert names(unit) == []
      assert diagnostic.code == "TPTP0603"
      assert diagnostic.severity == :warning
      refute Unit.any_errors?(unit)
    end

    test "a quoted selection name selects the unquoted statement, and back" do
      {unit, []} =
        unit("include('a.ax', ['wanted']).", %{
          "a.ax" => "fof(wanted, axiom, p). fof(unwanted, axiom, q)."
        })

      assert names(unit) == ["wanted"]

      {other, []} =
        unit("include('a.ax', [wanted]).", %{
          "a.ax" => "fof('wanted', axiom, p). fof(unwanted, axiom, q)."
        })

      assert names(other) == ["'wanted'"]
    end

    test "the same file may be included twice with different selections" do
      {unit, []} =
        unit("include('a.ax', [one]). include('a.ax', [two]).", %{
          "a.ax" => "fof(one, axiom, p). fof(two, axiom, q)."
        })

      assert names(unit) == ["one", "two"]
      assert map_size(unit.files) == 2
    end
  end

  describe "reporting" do
    test "diagnostics from included files come through, with their own file id" do
      {unit, diagnostics} = unit("include('a.ax').", %{"a.ax" => "wibble."})

      assert codes(diagnostics) == ["TPTP0201"]
      refute hd(diagnostics).span.file == unit.root
    end

    test "format_diagnostics renders each against its own file" do
      {unit, _diagnostics} =
        unit("fof(a, axiom, p).\ninclude('a.ax').\n", %{"a.ax" => "fof(b, axiom, q).\nwibble.\n"})

      assert [line] = Unit.format_diagnostics(unit)
      assert line =~ "a.ax:2:1: error"
    end

    test "text/2 resolves a span in whichever file it names" do
      {unit, diagnostics} = unit("include('a.ax').", %{"a.ax" => "wibble."})

      assert Unit.text(unit, hd(diagnostics).span) == "wibble"
    end

    test "file/2 takes an id or a span" do
      {unit, _diagnostics} = unit("include('a.ax').", %{"a.ax" => "fof(a, axiom, p)."})

      assert Unit.file(unit, unit.root).path == nil
      assert Unit.file(unit, Tptp.Span.new(unit.root, 0, 0)).id == unit.root
      assert Unit.file(unit, 99) == nil
    end

    test "formulae/1 drops nothing but includes" do
      {unit, []} =
        unit("fof(a, axiom, p). include('x.ax').", %{"x.ax" => "cnf(b, axiom, q)."})

      assert unit |> Unit.formulae() |> Enum.map(fn {_id, s} -> s.language end) == [:fof, :cnf]
    end
  end

  describe "from_name/2" do
    test "reads the root through the resolver too" do
      files = %{
        "root.p" => "include('a.ax'). fof(r, conjecture, p).",
        "a.ax" => "fof(a, axiom, p)."
      }

      {:ok, unit, []} = Unit.from_name("root.p", resolver: resolver(files))

      assert names(unit) == ["a", "r"]
    end

    test "a name the resolver does not know is an error" do
      assert {:error, [diagnostic]} = Unit.from_name("absent.p", resolver: resolver(%{}))
      assert diagnostic.code == "TPTP0601"
    end

    test "the default resolver cannot fetch anything, and says why" do
      assert {:error, [diagnostic]} = Unit.from_name("anything.p")
      assert diagnostic.code == "TPTP0606"
      assert diagnostic.hint =~ "Tptp.Resolver.Fs"
    end
  end

  describe "from_file/2 and from_file!/2" do
    @tmp Path.join(System.tmp_dir!(), "tptp-unit-test")

    setup do
      File.rm_rf!(@tmp)
      File.mkdir_p!(Path.join(@tmp, "Axioms"))
      on_exit(fn -> File.rm_rf!(@tmp) end)
      %{dir: @tmp}
    end

    test "resolves relative to the including file", %{dir: dir} do
      File.write!(Path.join([dir, "Axioms", "a.ax"]), "fof(a, axiom, p).\n")
      root = Path.join(dir, "problem.p")
      File.write!(root, "include('Axioms/a.ax').\nfof(r, conjecture, p).\n")

      {:ok, unit, []} = Unit.from_file(root, resolver: {Tptp.Resolver.Fs, cwd: false})

      assert names(unit) == ["a", "r"]
    end

    test "two names for one file memoise to one entry", %{dir: dir} do
      File.write!(Path.join([dir, "Axioms", "a.ax"]), "fof(a, axiom, p).\n")
      File.write!(Path.join([dir, "Axioms", "b.ax"]), "include('a.ax').\n")
      root = Path.join(dir, "problem.p")
      File.write!(root, "include('Axioms/a.ax').\ninclude('Axioms/b.ax').\n")

      {:ok, unit, []} = Unit.from_file(root, resolver: {Tptp.Resolver.Fs, cwd: false})

      assert map_size(unit.files) == 3
      assert names(unit) == ["a", "a"]
    end

    test "an unreadable root is the one failure case", %{dir: dir} do
      assert {:error, [%{code: "TPTP0001"}]} = Unit.from_file(Path.join(dir, "absent.p"))
    end

    test "from_file! raises on an unresolved include", %{dir: dir} do
      root = Path.join(dir, "problem.p")
      File.write!(root, "include('absent.ax').\n")

      error =
        assert_raise(Tptp.Error, fn ->
          Unit.from_file!(root, resolver: {Tptp.Resolver.Fs, cwd: false})
        end)

      assert [%{code: "TPTP0601"}] = error.diagnostics
    end

    test "from_file! returns the unit when everything resolves", %{dir: dir} do
      File.write!(Path.join([dir, "Axioms", "a.ax"]), "fof(a, axiom, p).\n")
      root = Path.join(dir, "problem.p")
      File.write!(root, "include('Axioms/a.ax').\n")

      assert %Unit{} = Unit.from_file!(root, resolver: {Tptp.Resolver.Fs, cwd: false})
    end
  end

  describe "concurrency" do
    test "the graph is the same however many siblings are parsed at once" do
      files = for n <- 1..20, into: %{}, do: {"#{n}.ax", "fof(f#{n}, axiom, p)."}
      source = Enum.map_join(1..20, " ", &"include('#{&1}.ax').")

      {sequential, []} = unit(source, files, max_concurrency: 1)
      {parallel, []} = unit(source, files, max_concurrency: 8)

      assert names(sequential) == names(parallel)
      assert sequential.resolutions == parallel.resolutions

      assert Map.new(sequential.files, fn {id, f} -> {id, f.path} end) ==
               Map.new(parallel.files, fn {id, f} -> {id, f.path} end)
    end

    test "file ids follow source order, not completion order" do
      files = for n <- 1..10, into: %{}, do: {"#{n}.ax", "fof(f#{n}, axiom, p)."}
      source = Enum.map_join(1..10, " ", &"include('#{&1}.ax').")

      {unit, []} = unit(source, files, max_concurrency: 8)

      assert names(unit) == Enum.map(1..10, &"f#{&1}")
    end
  end
end
