defmodule Tptp.PrinterTest do
  use ExUnit.Case, async: true

  doctest Tptp.Printer.Canonical
  doctest Tptp.Printer.Format
  doctest Tptp.Printer.Pretty

  alias Tptp.Node
  alias Tptp.Printer.Canonical
  alias Tptp.Printer.Format
  alias Tptp.Printer.Pretty
  alias Tptp.Statement

  defp print(source) do
    {:ok, statement, []} = Tptp.Parser.statement_from_string(source)
    Canonical.to_string(statement)
  end

  defp shape(statement) do
    {statement.__struct__, statement |> Statement.roots() |> Enum.map(&Node.shape/1)}
  end

  defp round_trips?(source) do
    {:ok, one, []} = Tptp.Parser.statement_from_string(source)

    case Tptp.Parser.statement_from_string(Canonical.to_string(one)) do
      {:ok, two, []} -> shape(one) == shape(two)
      _otherwise -> false
    end
  end

  describe "canonical spelling" do
    test "white space is normalised" do
      assert print("fof( a , axiom , p ).") == "fof(a, axiom, p)."
      assert print("fof(a,axiom,p&q).") == "fof(a, axiom, p & q)."
    end

    test "application needs no space" do
      assert print("fof(a, axiom, p ( b , c )).") == "fof(a, axiom, p(b, c))."
    end

    test "a quantifier keeps its bracket close" do
      assert print("fof(a, axiom, ! [X] : p(X)).") == "fof(a, axiom, ![X]: p(X))."
    end

    test "parentheses in the source survive, because the tree kept them" do
      assert print("fof(a, axiom, (p & q) | r).") == "fof(a, axiom, (p & q) | r)."
      assert print("fof(a, axiom, p & (q | r)).") == "fof(a, axiom, p & (q | r))."
    end

    test "an empty collection prints as an empty collection" do
      assert print("fof(a, axiom, p, inference(r, [], [])).") ==
               "fof(a, axiom, p, inference(r, [], []))."
    end

    test "a list of any length keeps its separators" do
      assert print("tff(a, axiom, p(w,x,y,z)).") == "tff(a, axiom, p(w, x, y, z))."
      assert print("fof(a, axiom, p(w,x,y,z)).") == "fof(a, axiom, p(w, x, y, z))."
      assert print("thf(a, axiom, p(w,x,y,z)).") == "thf(a, axiom, p(w, x, y, z))."
    end

    test "annotations keep their commas" do
      assert print("fof(a,axiom,p,unknown,[b]).") == "fof(a, axiom, p, unknown, [b])."
      assert print("fof(a,axiom,p,file('x.p',y)).") == "fof(a, axiom, p, file('x.p', y))."
    end

    test "an include prints its selection" do
      assert print("include('a.ax').") == "include('a.ax')."
      assert print("include('a.ax',[b,c]).") == "include('a.ax', [b, c])."
      assert print("include('a.ax',*,space).") == "include('a.ax', *, space)."
    end

    test "a file prints one statement per line, without comments" do
      {:ok, file, []} = Tptp.from_string("% a comment\nfof(a,axiom,p).\nfof(b,axiom,q).\n")

      assert Canonical.to_string(file) == "fof(a, axiom, p).\nfof(b, axiom, q).\n"
    end

    test "a unit prints its includes expanded" do
      resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(x, axiom, p)."}}

      {:ok, unit, []} =
        Tptp.Unit.from_string("include('a.ax'). fof(b,axiom,q).", resolver: resolver)

      assert Canonical.to_string(unit) == "fof(x, axiom, p).\nfof(b, axiom, q).\n"
    end
  end

  describe "the round-trip contract" do
    @formulae [
      "fof(a, axiom, p).",
      "fof(a, axiom, ~p).",
      "fof(a, axiom, (p & q) | r).",
      "fof(a, axiom, p & (q | r)).",
      "fof(a, axiom, ![X]: ?[Y]: p(X, Y, f(Z))).",
      "fof(a, axiom, a = b).",
      "fof(a, axiom, a != b).",
      "fof(a, axiom, p <=> (q => r)).",
      "cnf(c, axiom, p | ~q).",
      "cnf(c, axiom, ~(p)).",
      "tcf(c, axiom, ![X: $i]: (p(X) | q)).",
      "thf(t, type, f: $i > $o).",
      "thf(p, axiom, f @ $i @ a).",
      "thf(q, axiom, !! @ (^[X: $i]: p @ X)).",
      "thf(g, type, g: !>[A: $tType]: (A > A)).",
      "thf(n, axiom, {$box} @ p).",
      "tff(x, axiom, $let(b: $i, b := c, p(b))).",
      "tff(t, axiom, [x, y] = z).",
      "tff(n, axiom, [.] p).",
      "tff(a, axiom, $less(1, 2.5)).",
      "tff(a, axiom, p(-1/2)).",
      "fof(a, axiom, p('quoted name', \"distinct\")).",
      "fof(a, assumption-[1], p).",
      "fof(z, axiom, p, inference(rule, [status(thm)], [b, c])).",
      "fof(w, axiom, p, unknown, [$fof(q), description('why')]).",
      "fof(v, axiom, p, introduced(definition, [], [])).",
      "fof(u, axiom, p, inference(r, [], [a : foo, b])).",
      "include('Axioms/SET007+0.ax', [b], space).",
      "tpi(t, axiom, p)."
    ]

    for source <- @formulae do
      @source source

      test "round-trips #{inspect(source)}" do
        assert round_trips?(@source), "printed as #{inspect(print(@source))}"
      end
    end

    test "printing is idempotent" do
      for source <- @formulae do
        once = print(source)
        {:ok, again, []} = Tptp.Parser.statement_from_string(once)

        assert Canonical.to_string(again) == once, "#{inspect(source)} is not stable"
      end
    end
  end

  describe "format-preserving printing" do
    defp tokens_of(source) do
      {statements, _comments, _diagnostics} = Tptp.Lexer.statements(source)
      statements |> List.flatten() |> Enum.map(&Tptp.Lexer.text(&1, source))
    end

    defp preserves_tokens?(source) do
      tokens_of(source) == source |> Format.to_string() |> tokens_of()
    end

    test "the tokens are exactly the same, in the same order" do
      for source <- [
            "fof( a,axiom,p&q ).\n",
            "%----head\nfof(a,axiom,p).\n\nfof(b,axiom,q). % tail\n",
            "thf(a,axiom,!![X:$i]:(p@X)).\n",
            "include('a.ax',[b,c]).\n"
          ] do
        assert preserves_tokens?(source), "#{inspect(source)} lost or changed a token"
      end
    end

    test "a trailing comment stays on its line" do
      assert Format.to_string("fof(a,axiom,p). % why\n") == "fof(a, axiom, p).  % why\n"
    end

    test "a leading comment keeps its own line" do
      assert Format.to_string("% why\nfof(a,axiom,p).\n") == "% why\nfof(a, axiom, p).\n"
    end

    test "one blank line between statements is kept" do
      assert Format.to_string("fof(a,axiom,p).\n\nfof(b,axiom,q).\n") ==
               "fof(a, axiom, p).\n\nfof(b, axiom, q).\n"
    end

    test "several blank lines collapse to one" do
      assert Format.to_string("fof(a,axiom,p).\n\n\n\nfof(b,axiom,q).\n") ==
               "fof(a, axiom, p).\n\nfof(b, axiom, q).\n"
    end

    test "no blank line stays no blank line" do
      assert Format.to_string("fof(a,axiom,p).\nfof(b,axiom,q).\n") ==
               "fof(a, axiom, p).\nfof(b, axiom, q).\n"
    end

    test "it is idempotent" do
      for source <- [
            "fof( a,axiom,p&q ).  % why\n",
            "%----head\nfof(a,axiom,p).\n\n\nfof(b,axiom,q).\n%----foot\n",
            "/* block */\nfof(a,axiom,p).\n"
          ] do
        once = Format.to_string(source)

        assert Format.to_string(once) == once, "#{inspect(source)} is not stable"
      end
    end

    test "a file it cannot lex is returned untouched" do
      broken = "fof(a, axiom, 'unterminated).\n"

      assert Format.to_string(broken) == broken
    end

    test "an empty file stays empty" do
      assert Format.to_string("") == ""
    end

    test "comments survive, all of them" do
      source = "% one\nfof(a,axiom,p). % two\n/* three */\nfof(b,axiom,q).\n% four\n"
      formatted = Format.to_string(source)

      for comment <- ["% one", "% two", "/* three */", "% four"] do
        assert formatted =~ comment
      end
    end
  end

  describe "format_file/1" do
    @tmp Path.join(System.tmp_dir!(), "tptp-format-test")

    setup do
      File.mkdir_p!(@tmp)
      on_exit(fn -> File.rm_rf!(@tmp) end)
      %{dir: @tmp}
    end

    test "reports whether it changed anything", %{dir: dir} do
      path = Path.join(dir, "x.p")
      File.write!(path, "fof( a,axiom,p ).\n")

      assert Format.format_file(path) == {:ok, :changed}
      assert File.read!(path) == "fof(a, axiom, p).\n"
      assert Format.format_file(path) == {:ok, :unchanged}
    end

    test "an unreadable file is an error, not a crash", %{dir: dir} do
      assert {:error, :enoent} = Format.format_file(Path.join(dir, "absent.p"))
    end
  end

  describe "pretty printing" do
    @wide 1_000_000

    defp pretty(source, width) do
      {:ok, statement, []} = Tptp.Parser.statement_from_string(source)
      Pretty.to_string(statement, width: width)
    end

    test "at a width nothing can exceed, it is the canonical printer" do
      for source <- @formulae do
        {:ok, statement, []} = Tptp.Parser.statement_from_string(source)

        assert Pretty.to_string(statement, width: @wide) == Canonical.to_string(statement),
               "#{inspect(source)} disagrees with the canonical form when it fits"
      end
    end

    test "no width changes a token" do
      for source <- @formulae, width <- [1, 8, 20, 40, 80] do
        {:ok, statement, []} = Tptp.Parser.statement_from_string(source)

        assert tokens_of(Pretty.to_string(statement, width: width)) ==
                 Canonical.tokens(statement),
               "#{inspect(source)} lost a token at width #{width}"
      end
    end

    test "output at any width reparses to the same tree" do
      for source <- @formulae, width <- [1, 12, 33, 80] do
        {:ok, one, []} = Tptp.Parser.statement_from_string(source)

        {:ok, two, []} =
          one |> Pretty.to_string(width: width) |> Tptp.Parser.statement_from_string()

        assert shape(one) == shape(two), "#{inspect(source)} changed shape at width #{width}"
      end
    end

    test "a connective starts its line, it does not end the one before" do
      printed = pretty("fof(a, axiom, alpha & beta & gamma).", 20)

      assert printed == """
             fof(
               a,
               axiom,
               alpha
               & beta
               & gamma
             ).\
             """
    end

    test "an application spine breaks at the @" do
      printed = pretty("thf(a, axiom, f @ alpha @ beta @ gamma).", 20)

      assert printed =~ "\n  @ alpha"
      assert printed =~ "\n  @ beta"
    end

    test "a type signature breaks at the arrow" do
      printed = pretty("thf(t, type, f: alpha > beta > gamma > $o).", 20)

      assert printed =~ "\n  > beta"
    end

    test "a list breaks one element per line, indented" do
      printed = pretty("include('a.ax', [alpha, beta, gamma]).", 20)

      assert printed == """
             include(
               'a.ax',
               [
                 alpha,
                 beta,
                 gamma
               ]
             ).\
             """
    end

    test "a group that fits stays on one line even when its parent broke" do
      printed = pretty("fof(a, axiom, p(alpha, beta) & q(gamma, delta)).", 30)

      assert printed =~ "p(alpha, beta)"
      assert printed =~ "& q(gamma, delta)"
    end

    test "a quoted atom is never broken, whatever the width" do
      printed = pretty("fof('a name with spaces', axiom, p).", 1)

      assert printed =~ "'a name with spaces'"
    end

    test "a file prints one statement per line" do
      {:ok, file, []} = Tptp.from_string("fof(a,axiom,p). fof(b,axiom,q).")

      assert Pretty.to_string(file) == "fof(a, axiom, p).\nfof(b, axiom, q).\n"
    end

    test "a unit prints its includes expanded" do
      resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(x, axiom, p)."}}

      {:ok, unit, []} =
        Tptp.Unit.from_string("include('a.ax'). fof(b,axiom,q).", resolver: resolver)

      assert Pretty.to_string(unit) == "fof(x, axiom, p).\nfof(b, axiom, q).\n"
    end

    test "printing is idempotent at a given width" do
      for source <- @formulae, width <- [16, 80] do
        once = pretty(source, width)
        {:ok, again, []} = Tptp.Parser.statement_from_string(once)

        assert Pretty.to_string(again, width: width) == once,
               "#{inspect(source)} is not stable at width #{width}"
      end
    end

    test "it writes to a file" do
      path = Path.join(System.tmp_dir!(), "tptp-pretty-test.p")
      on_exit(fn -> File.rm(path) end)
      {:ok, file, []} = Tptp.from_string("fof(a,axiom,p&q).")

      assert Pretty.to_file(file, path, width: 12) == :ok
      assert File.read!(path) =~ "& q"
    end
  end

  describe "the canonical token list" do
    test "is flat binaries for both kinds of statement" do
      for source <- ["fof(a, axiom, p, inference(r, [], [b])).", "include('a.ax', [b], c)."] do
        {:ok, statement, []} = Tptp.Parser.statement_from_string(source)
        tokens = Canonical.tokens(statement)

        assert Enum.all?(tokens, &is_binary/1), "#{inspect(source)} produced a nested list"
        assert tokens == tokens_of(Canonical.to_string(statement))
      end
    end
  end
end
