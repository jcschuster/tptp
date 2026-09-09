defmodule Tptp.InspectTest do
  @moduledoc """
  What `inspect/1` prints, and what it must not.

  The derived implementations were a hazard rather than a nicety here. A
  `Tptp.File` holds its whole source and every node that points into it, so
  `inspect/1` on one printed a 455 MB binary and several million nodes — into an IEx
  prompt, a `Logger` line, or an exception report, none of which asked for it and one
  of which is already handling a failure.

  So each of these prints a summary, and the tests below pin the two properties that
  matter: the output is short whatever the input, and it costs nothing to produce.
  `inspect(term, structs: false)` still shows the underlying map, which is the escape
  hatch for anyone who actually wants the tree.
  """

  use ExUnit.Case, async: true

  alias Tptp.Statement.Include
  alias Tptp.Test.Corpus

  @source """
  fof(one, axiom, ![X] : (p(X) => q(X))).
  fof(two, conjecture, q(a)).
  include('Axioms/SET007+0.ax', [key_lemma, other]).
  """

  defp file do
    {:ok, file, _diagnostics} = Tptp.from_string(@source, path: "demo.p")
    file
  end

  describe "a summary, not a tree" do
    test "a file names itself and says what it holds" do
      rendered = inspect(file())

      assert rendered =~ ~s(#Tptp.File<"demo.p")
      assert rendered =~ "3 statements"
      assert rendered =~ "B>" or rendered =~ "KB"
      refute rendered =~ "fof(one"
    end

    test "a node says what it is without printing what is under it" do
      [statement | _rest] = file().statements
      rendered = inspect(statement.formula)

      assert rendered =~ "#Tptp.Node<"
      assert rendered =~ "children" or rendered =~ "child"
      refute rendered =~ "%Tptp.Node{"
    end

    test "a leaf shows its spelling" do
      [statement | _rest] = file().statements

      assert inspect(statement.name) == ~s(#Tptp.Node<:name "one" 4..7>)
    end

    test "an annotated statement is one line naming its language, name and role" do
      [statement | _rest] = file().statements

      assert inspect(statement) =~ ~s(#Tptp.Statement.Annotated<:fof "one": axiom,)
    end

    test "an include names its file and how much of it was selected" do
      include = Enum.find(file().statements, &match?(%Include{}, &1))

      assert inspect(include) =~ "#Tptp.Statement.Include<"
      assert inspect(include) =~ "selected"

      # The count is deliberately not shown: the names sit under a list node and
      # counting them is a walk. `selected/1` is what answers with the names.
      assert Include.selected(include) == ["key_lemma", "other"]
    end

    test "an analysis nests the file's summary and counts what it found" do
      rendered = @source |> Tptp.analyze() |> inspect()

      assert rendered =~ "#Tptp.Analysis<#Tptp.File<"
      assert rendered =~ "symbol"
    end

    test "an analysis says whether the line index has been paid for" do
      analysis = Tptp.analyze(@source)

      refute inspect(analysis) =~ "line index"
      assert analysis |> Tptp.Analysis.with_line_index() |> inspect() =~ "line index"
    end

    test "a symbol table counts rather than lists" do
      table = @source |> Tptp.analyze() |> Map.fetch!(:table)

      assert inspect(table) =~ "#Tptp.Lint.Table<"
      assert inspect(table) =~ "symbol"
      assert inspect(table) =~ ":fof"
    end
  end

  describe "the escape hatch" do
    test "structs: false still shows everything" do
      [statement | _rest] = file().statements
      rendered = inspect(statement.formula, structs: false)

      assert rendered =~ "__struct__: Tptp.Node"
      assert rendered =~ "children:"
    end
  end

  describe "cost" do
    test "inspecting a file does not depend on how big the file is" do
      big = String.duplicate("fof(a, axiom, p(x, y, z)).\n", 20_000)
      {:ok, parsed, _diagnostics} = Tptp.from_string(big)

      rendered = inspect(parsed)

      assert String.length(rendered) < 120,
             "inspect/1 must summarise, whatever the input: #{String.slice(rendered, 0, 200)}"

      assert rendered =~ "20000 statements"
    end

    test "inspecting a node is constant in the size of its subtree" do
      deep = String.duplicate("~", 2_000) <> "p"

      {:ok, statement, _diagnostics} =
        Tptp.Parser.statement_from_string("fof(a, axiom, #{deep}).")

      assert String.length(inspect(statement.formula)) < 80
    end
  end

  @tag :corpus
  test "the largest file in the library inspects to one short line" do
    if path = Corpus.root() do
      big = Path.join(path, "Problems/SWW/SWW778_1.p")

      if File.exists?(big) do
        {:ok, parsed, _diagnostics} = Tptp.from_file(big)

        assert String.length(inspect(parsed)) < 120
      end
    end
  end
end
