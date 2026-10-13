defmodule Tptp.DerivationTest do
  @moduledoc """
  Reading the `source` annotations of a derivation as a graph.

  The fixtures are captures of what three systems printed — see
  `test/fixtures/tstp/README.md` — because the shapes a `<source>` comes in are
  whatever provers write: E nests inference records and lifts the proof out of its
  own output, Vampire introduces definitions for AVATAR splitting and names a
  parent that is not a statement, and a saturation is a derivation with no root in
  it. Each is asserted against in detail, and the hand-written cases cover the
  shapes the grammar allows that no fixture happens to contain.

  Two of the three findings reported here are `Tptp.Lint`'s own, raised through the
  rule modules' `code/0`, so the tests name the codes rather than the modules: what
  matters to a caller is that the same finding has the same code wherever it was
  made.
  """

  use ExUnit.Case, async: true

  doctest Tptp.Derivation
  doctest Tptp.Derivation.Node
  doctest Tptp.Derivation.Step

  alias Tptp.Derivation
  alias Tptp.Derivation.Step
  alias Tptp.Node
  alias Tptp.Printer.Canonical
  alias Tptp.Szs
  alias Tptp.Tstp

  @archived "test/fixtures/tstp/E---3.5.1.THM-CRf.s"

  defp block(name) do
    [block] =
      "test/fixtures/tstp/#{name}.txt"
      |> File.read!()
      |> Szs.blocks(prefix: Szs.prefix(:line_comment))

    block.body
  end

  defp read(source) do
    {:ok, derivation, diagnostics} = Derivation.from_string(source)

    {derivation, diagnostics}
  end

  defp codes(diagnostics), do: Enum.map(diagnostics, & &1.code)

  describe "E's CNF refutation" do
    setup do
      {derivation, diagnostics} = read(block("e_cnfrefutation_raw"))

      %{derivation: derivation, diagnostics: diagnostics}
    end

    test "every statement is a node and nothing is unaccounted for", %{
      derivation: derivation,
      diagnostics: diagnostics
    } do
      assert length(derivation.order) == 54
      assert map_size(derivation.nodes) == 54
      assert diagnostics == []
    end

    test "a nested inference record flattens inside out", %{derivation: derivation} do
      [steps] = derivation.nodes["c_0_53"].steps

      assert Enum.map(steps, &{&1.rule, &1.status, &1.parents}) == [
               {"rw", :theorem, ["c_0_19", "c_0_51"]},
               {"sr", :theorem, [{:step, 0}, "c_0_52"]}
             ]

      # The inner record's own formula is not a statement of the file and gets no
      # node; the names it was derived from are parents of the statement all the same.
      assert derivation.nodes["c_0_53"].parents == ["c_0_19", "c_0_51", "c_0_52"]
      assert Step.named_parents(List.last(steps)) == ["c_0_52"]
    end

    test "every status in the proof resolves to an ontology value", %{derivation: derivation} do
      statuses =
        for {_name, node} <- derivation.nodes,
            steps <- node.steps,
            step <- steps,
            do: step.status

      assert length(statuses) == 61
      assert Enum.uniq(Enum.sort(statuses)) == [:counter_theorem, :equi_satisfiable, :theorem]
      refute Enum.any?(statuses, &is_nil/1)
    end

    test "the refutation has one root, the statement of $false", %{derivation: derivation} do
      assert derivation.roots == ["c_0_53"]
      assert Canonical.to_string(derivation.nodes["c_0_53"].statement) =~ "$false"
    end

    test "the leaves are the statements read from the problem file", %{derivation: derivation} do
      assert length(derivation.leaves) == 11

      for name <- derivation.leaves do
        assert {:file, path, ^name} = derivation.nodes[name].origin
        assert String.ends_with?(path, "PUZ001+1.p")
      end
    end

    test "is a DAG, and topological/1 puts every parent before its child", %{
      derivation: derivation
    } do
      assert Derivation.acyclic?(derivation)
      assert {:ok, sorted} = Derivation.topological(derivation)
      assert length(sorted) == 54

      positions = sorted |> Enum.with_index() |> Map.new()

      for {name, node} <- derivation.nodes, parent <- node.parents do
        assert positions[parent] < positions[name],
               "#{parent} must come before #{name}"
      end
    end

    test "ancestors reach back to the axioms, descendants forward to $false", %{
      derivation: derivation
    } do
      assert length(Derivation.ancestors(derivation, "c_0_53")) == 53
      assert Derivation.descendants(derivation, "c_0_53") == []
      assert "c_0_53" in Derivation.descendants(derivation, "pel55")
    end
  end

  describe "Vampire's proof" do
    setup do
      {derivation, diagnostics} = read(block("vampire_proof_raw"))

      %{derivation: derivation, diagnostics: diagnostics}
    end

    test "an introduced definition records its type and keeps its info", %{
      derivation: derivation
    } do
      node = derivation.nodes["f54"]

      assert {:introduced, "definition", info} = node.origin
      assert Canonical.to_string(info) == "[new_symbols(definition, [spl2_1])]"
      assert node.steps == []
    end

    # `introduced(definition, [...], [avatar_definition])` writes a name in parent
    # position, and no statement of the proof has it: by C5 the node has a parent and
    # is therefore not a leaf, and the name is reported like any other.
    test "a parent named by an introduction is a parent like any other", %{
      derivation: derivation,
      diagnostics: diagnostics
    } do
      assert derivation.nodes["f54"].parents == ["avatar_definition"]
      refute "f54" in derivation.leaves

      assert codes(diagnostics) == ["TPTP0504", "TPTP0504", "TPTP0504"]
      assert Enum.all?(diagnostics, &(&1.message =~ "avatar_definition"))
    end

    test "a file source carries the formula's name in the problem file", %{
      derivation: derivation
    } do
      assert {:file, path, "pel55_1"} = derivation.nodes["f1"].origin
      assert String.ends_with?(path, "PUZ001+1.p")

      # The name in a `file(...)` source names a formula of that file, not a parent
      # in this one, so it is no edge and raises nothing.
      assert derivation.nodes["f1"].parents == []
      assert "f1" in derivation.leaves
    end

    test "the proof is a DAG ending in one statement", %{derivation: derivation} do
      assert derivation.roots == ["f92"]
      assert Derivation.acyclic?(derivation)
      assert {:ok, _sorted} = Derivation.topological(derivation)
    end

    test "statuses other than thm resolve too", %{derivation: derivation} do
      statuses =
        for {_name, node} <- derivation.nodes,
            steps <- node.steps,
            step <- steps,
            status = step.status,
            do: status

      assert Enum.sort(statuses) == [:counter_theorem, :equi_satisfiable, :equi_satisfiable]
    end
  end

  describe "E's saturation" do
    setup do
      {derivation, diagnostics} = read(block("e_saturation_raw"))

      %{derivation: derivation, diagnostics: diagnostics}
    end

    test "nothing derives $false, so every clause is a root", %{derivation: derivation} do
      assert length(derivation.order) == 4
      assert derivation.roots == derivation.order
      assert derivation.leaves == []
    end

    test "the clauses it was saturated from are not in the block", %{diagnostics: diagnostics} do
      # Five occurrences of four names: `c_0_8` justifies two of the four clauses.
      assert codes(diagnostics) == List.duplicate("TPTP0504", 5)
    end

    test "the statement's own info is not the step's", %{derivation: derivation} do
      node = derivation.nodes["c_0_12"]
      [[step]] = node.steps

      assert Canonical.to_string(node.statement.info) == "['final']"
      assert step.status == :theorem
      assert Canonical.to_string(step.info) == "[status(thm)]"
    end
  end

  describe "a derivation lifted out of a solution file" do
    test "has the nodes and leaves its header states" do
      {:ok, solution, []} = Tstp.from_file(@archived)
      {:ok, derivation, []} = Derivation.from_file(solution.solution)

      assert solution.header["Syntax"] =~ "Number of formulae    :   54"
      assert solution.header["SZS Type"] =~ "Number of leaves      :   11"

      assert length(derivation.order) == 54
      assert length(derivation.leaves) == 11
      assert derivation.roots == ["c_0_53"]
    end
  end

  describe "names" do
    test "the later statement of a duplicated name wins, and the duplicate is reported" do
      first = "fof(a, axiom, p).\n"
      source = first <> "fof(a, axiom, q).\nfof(b, plain, r, a)."
      {derivation, [diagnostic]} = read(source)

      assert derivation.order == ["a", "b"]

      assert Canonical.to_string(derivation.nodes["a"].statement) ==
               "fof(a, axiom, q)."

      assert diagnostic.code == "TPTP0503"
      assert diagnostic.message == ~s("a" names 2 statements)

      # Reported at the later occurrence, with the earlier one related, as
      # `Tptp.Lint.Rules.DuplicateName` does it.
      assert diagnostic.span.offset > byte_size(first)
      assert binary_part(source, diagnostic.span.offset, diagnostic.span.length) == "a"
      assert [{related, "first named here"}] = diagnostic.related
      assert related.offset == 4
    end

    test "a quoted name and an unquoted one are one node" do
      {derivation, []} = read("fof('c_0_7', axiom, p).\nfof(b, plain, q, c_0_7).")

      assert derivation.order == ["c_0_7", "b"]
      assert derivation.nodes["b"].parents == ["c_0_7"]
      assert derivation.leaves == ["c_0_7"]
    end
  end

  describe "a parent that names no statement" do
    test "is reported once per occurrence, with the name's own span" do
      source = "fof(b, plain, q, inference(r, [], [a, a])).\nfof(c, plain, s, a)."
      {derivation, diagnostics} = read(source)

      assert codes(diagnostics) == List.duplicate("TPTP0504", 3)

      for diagnostic <- diagnostics do
        assert binary_part(source, diagnostic.span.offset, diagnostic.span.length) == "a"
      end

      assert Enum.map(diagnostics, & &1.span.offset) |> Enum.sort() |> Enum.uniq() |> length() ==
               3

      # The edge is dropped from every query, the node being one this graph does not
      # have, but `parents` keeps what the file wrote.
      assert derivation.nodes["b"].parents == ["a"]
      assert Derivation.ancestors(derivation, "b") == []
      assert derivation.leaves == []
    end

    test "unknown is not reported" do
      {derivation, []} = read("fof(a, plain, p, unknown).")

      assert derivation.nodes["a"].origin == {:name, "unknown"}
      assert derivation.nodes["a"].parents == ["unknown"]
    end
  end

  describe "a cycle" do
    test "is reported once for the two nodes on it" do
      {derivation, [diagnostic]} = read("fof(a, plain, p, b).\nfof(b, plain, q, a).")

      assert diagnostic.code == "TPTP0507"
      assert diagnostic.severity == :warning
      assert diagnostic.message == ~s("a" is derived from itself through "b")
      assert diagnostic.hint =~ "acyclic?/1"
      assert [{related, "on the same cycle"}] = diagnostic.related
      assert related.offset == 25

      refute Derivation.acyclic?(derivation)
      assert Derivation.topological(derivation) == :error
    end

    test "says only that a self-loop derives itself" do
      {_derivation, [diagnostic]} = read("fof(a, plain, p, a).")

      assert diagnostic.message == ~s("a" is derived from itself)
      assert diagnostic.related == []
    end

    test "leaves order, roots and leaves as the file wrote them" do
      {derivation, [_cycle]} =
        read("fof(a, plain, p, b).\nfof(b, plain, q, a).\nfof(c, axiom, r).")

      assert derivation.order == ["a", "b", "c"]
      assert derivation.roots == ["c"]
      assert derivation.leaves == ["c"]
      assert Derivation.ancestors(derivation, "a") == ["b"]
    end

    test "is one diagnostic per component" do
      {_derivation, diagnostics} =
        read("""
        fof(a, plain, p, b).
        fof(b, plain, q, a).
        fof(c, plain, r, d).
        fof(d, plain, s, c).
        """)

      assert codes(diagnostics) == ["TPTP0507", "TPTP0507"]

      assert Enum.map(diagnostics, & &1.message) == [
               ~s("a" is derived from itself through "b"),
               ~s("c" is derived from itself through "d")
             ]
    end
  end

  describe "sources that are not inference records" do
    test "a bare name is a parent, and the node is not a leaf" do
      {derivation, []} = read("fof(a, axiom, p).\nfof(b, plain, q, a).")

      assert derivation.nodes["b"].origin == {:name, "a"}
      assert derivation.nodes["b"].steps == []
      assert derivation.nodes["b"].parents == ["a"]
      assert derivation.leaves == ["a"]
    end

    test "a statement without annotations is both a leaf and a root" do
      {derivation, []} = read("fof(a, axiom, p).")

      assert derivation.nodes["a"].origin == :none
      assert derivation.leaves == ["a"]
      assert derivation.roots == ["a"]
    end

    test "a bracketed source of two records has one step list each" do
      {derivation, []} =
        read(
          "fof(a, axiom, p).\nfof(c, axiom, r).\nfof(b, plain, q, [inference(x, [], [a]), inference(y, [], [c])])."
        )

      node = derivation.nodes["b"]

      assert node.origin == :inference

      assert Enum.map(node.steps, fn [step] -> {step.rule, step.parents} end) == [
               {"x", ["a"]},
               {"y", ["c"]}
             ]

      assert node.parents == ["a", "c"]
    end

    test "a bracketed source with an alternative that is not a record is kept whole" do
      {derivation, []} =
        read("fof(a, axiom, p).\nfof(b, plain, q, [a, inference(y, [], [a])]).")

      node = derivation.nodes["b"]

      assert {:unknown, %Node{kind: :source}} = node.origin
      assert Enum.map(node.steps, fn [step] -> step.rule end) == ["y"]
      assert node.parents == ["a"]
    end

    test "a source the classifier does not know keeps its node" do
      {derivation, []} = read("fof(a, axiom, p, file('x.p')).")

      assert derivation.nodes["a"].origin == {:file, "x.p", nil}
      assert derivation.nodes["a"].parents == []
    end
  end

  describe "cone/2" do
    @cone """
    % before a
    fof(a, axiom, p, file('p.p', ax)).
    fof(b, axiom, q).
    fof(c, plain, r, % why
        inference(x, [], [a])).
    """

    test "keeps the node and its ancestors, and prints as TPTP again" do
      {derivation, []} = read(@cone)
      cone = Derivation.cone(derivation, "c")

      assert cone.order == ["a", "c"]
      assert cone.roots == ["c"]
      assert cone.leaves == ["a"]
      assert inspect(cone) == "#Tptp.Derivation<2 nodes, 1 leaf, 1 root>"

      printed = Canonical.to_string(cone.file)
      {:ok, again, []} = Tptp.from_string(printed)

      assert Enum.map(again.statements, &Node.value(&1.name)) == ["a", "c"]
    end

    test "keeps the comments inside the statements it keeps, and no others" do
      {derivation, []} = read(@cone)
      cone = Derivation.cone(derivation, "c")

      assert Enum.map(cone.file.comments, fn {off, len, _where, _kind} ->
               binary_part(@cone, off, len)
             end) == ["% why"]

      assert cone.file.diagnostics == []
      assert cone.file.source == @cone
    end

    test "drops a parent that named no statement" do
      {derivation, [_missing]} =
        read("fof(c_0, axiom, p).\nfof(c, plain, r, inference(x, [], [a, c_0])).")

      cone = Derivation.cone(derivation, "c")

      assert cone.order == ["c_0", "c"]
      assert cone.nodes["c"].parents == ["c_0"]
      assert cone.nodes["c"].steps == derivation.nodes["c"].steps
    end

    test "an unknown name is an empty derivation" do
      {derivation, []} = read("fof(a, axiom, p).")
      cone = Derivation.cone(derivation, "z")

      assert cone.order == []
      assert cone.nodes == %{}
      assert cone.roots == []
      assert cone.leaves == []
      assert cone.file.statements == []
    end
  end

  describe "queries over a diamond" do
    @diamond """
    fof(top, axiom, p).
    fof(left, plain, q, inference(x, [], [top])).
    fof(right, plain, r, inference(x, [], [top])).
    fof(bottom, plain, s, inference(x, [], [left, right])).
    """

    test "ancestors and descendants are transitive and in order" do
      {derivation, []} = read(@diamond)

      assert Derivation.ancestors(derivation, "bottom") == ["top", "left", "right"]
      assert Derivation.descendants(derivation, "top") == ["left", "right", "bottom"]
      assert Derivation.ancestors(derivation, "top") == []
      assert Derivation.descendants(derivation, "bottom") == []
    end

    test "topological/1 breaks ties by the file's order" do
      {derivation, []} = read(@diamond)

      assert Derivation.topological(derivation) == {:ok, ["top", "left", "right", "bottom"]}

      {reversed, []} =
        read("""
        fof(bottom, plain, s, inference(x, [], [left])).
        fof(unrelated, axiom, u).
        fof(left, axiom, q).
        """)

      assert Derivation.topological(reversed) == {:ok, ["unrelated", "left", "bottom"]}
    end
  end

  test "no atom is created for a rule or a status the ontology does not know" do
    fresh = "zzz#{System.unique_integer([:positive])}"

    {derivation, []} =
      read("fof(a, axiom, p).\nfof(b, plain, q, inference(#{fresh}, [status(#{fresh})], [a])).")

    [[step]] = derivation.nodes["b"].steps

    assert step.rule == fresh
    assert step.status == nil
    assert_raise ArgumentError, fn -> String.to_existing_atom(fresh) end
  end
end
