defmodule Tptp.ParserPropertyTest do
  @moduledoc """
  The CST's invariants, over generated input rather than chosen input.

  The one that matters most is that a node's span is a real range of the source:
  in bounds, containing its children, and equal to `text` on a leaf. A tree that
  gets this wrong still looks right in a unit test and breaks every consumer that
  reports a position — which is all of them.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tptp.Node
  alias Tptp.Parser
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include

  @higher_order [
    "thf(a, type, f: $i > $o).",
    "thf(a, type, g: !>[A: $tType]: (A > A)).",
    "thf(a, axiom, f @ $i @ b).",
    "thf(a, axiom, !! @ (^[X: $i]: p @ X)).",
    "thf(a, axiom, ![X: $i]: (p @ X)).",
    "thf(a, axiom, @@+ @ p).",
    "cnf(a, axiom, p | ~q).",
    "cnf(a, negated_conjecture, ~p(X) | q(f(X))).",
    "tcf(a, axiom, ![X: $i]: (p(X) | q)).",
    "tpi(a, axiom, p).",
    "include('Axioms/SET007+0.ax').",
    "include('a.ax', [b, c]).",
    "include('a.ax', *, space).",
    "tff(a, type, f: $i > $o).",
    "tff(a, axiom, ![X: $i]: (p(X) => q(X))).",
    "tff(a, axiom, a != b).",
    "tff(a, axiom, $let(b: $i, b := c, p(b))).",
    "tff(a, axiom, $ite(p, a, b) = c).",
    "fof(a, assumption-[1], p).",
    "fof(a, axiom, p, unknown, [$fof(q), description('why')])."
  ]

  property "never raises, whatever the bytes" do
    check all(source <- binary()) do
      assert is_tuple(Parser.statement_from_string(source))
    end
  end

  property "never raises on plausible-looking statements" do
    check all(source <- statement()) do
      assert is_tuple(Parser.statement_from_string(source))
    end
  end

  property "every node's span is in bounds and its leaf text matches it" do
    check all({source, statement} <- parsed()) do
      for root <- roots(statement), node <- Node.walk(root) do
        assert node.off + node.len <= byte_size(source), "#{node.kind} runs past the source"

        if node.text do
          assert node.text == binary_part(source, node.off, node.len),
                 "#{node.kind} carries text its span does not name"
        end
      end
    end
  end

  property "children are inside their parent and in reading order" do
    check all({_source, statement} <- parsed()) do
      for root <- roots(statement), parent <- Node.walk(root) do
        Enum.reduce(parent.children, parent.off, fn child, position ->
          assert child.off >= position, "#{child.kind} overlaps its previous sibling"

          assert child.off + child.len <= parent.off + parent.len,
                 "#{child.kind} escapes its parent #{parent.kind}"

          child.off + child.len
        end)
      end
    end
  end

  @categories MapSet.new(Tptp.Token.categories())

  property "only leaves carry text, and a token leaf carries it exactly when its kind does not" do
    check all({_source, statement} <- parsed()) do
      for root <- roots(statement), node <- Node.walk(root) do
        if node.text do
          assert node.children == [], "#{node.kind} carries text and has children"
        end

        if MapSet.member?(@categories, node.kind) do
          assert is_nil(node.text) == (Tptp.Token.spelling(node.kind) != nil),
                 "leaf #{node.kind} disagrees with its category about carrying text"
        end
      end
    end
  end

  property "an empty collection is a childless node, not a leaf with text" do
    for source <- [
          "fof(a, axiom, p, introduced(definition, [], [])).",
          "thf(a, axiom, [] = []).",
          "fof(a, axiom, p, unknown, [])."
        ] do
      {:ok, statement, []} = Parser.statement_from_string(source)

      for root <- roots(statement),
          node <- Node.walk(root),
          node.kind in [:general_list, :parents, :thf_tuple] do
        assert node.children == []
        assert node.text == nil
        assert node.len >= 2, "an empty collection must still span its brackets"
      end
    end
  end

  property "at/2 finds a node for every offset the statement covers" do
    check all({_source, statement} <- parsed()) do
      for root <- roots(statement), offset <- [root.off, root.off + div(root.len, 2)] do
        assert %Node{} = Node.at(root, offset)
      end
    end
  end

  property "shape/1 ignores white space but not structure" do
    check all(source <- statement()) do
      spaced = String.replace(source, ",", " , ")

      case {Parser.statement_from_string(source), Parser.statement_from_string(spaced)} do
        {{:ok, %Annotated{} = one, _}, {:ok, %Annotated{} = two, _}} ->
          assert Node.shape(one.formula) == Node.shape(two.formula)

        _otherwise ->
          :ok
      end
    end
  end

  property "detach/1 preserves shape and releases the source" do
    check all({_source, statement} <- parsed()) do
      for root <- roots(statement) do
        detached = Node.detach(root)
        assert Node.shape(detached) == Node.shape(root)

        for leaf <- Node.walk(detached), leaf.text != nil do
          assert :binary.referenced_byte_size(leaf.text) == byte_size(leaf.text)
        end
      end
    end
  end

  defp roots(%Annotated{} = statement) do
    [statement.name, statement.role, statement.formula] ++
      List.wrap(statement.source) ++ List.wrap(statement.info)
  end

  defp roots(%Include{} = statement) do
    [statement.file_name] ++ List.wrap(statement.selection) ++ List.wrap(statement.space_name)
  end

  defp parsed do
    gen all(source <- statement()) do
      {:ok, statement, _diagnostics} = Parser.statement_from_string(source)
      {source, statement}
    end
  end

  defp statement do
    one_of([fof_statement(), member_of(@higher_order)])
  end

  defp fof_statement do
    gen all(
          name <- name(),
          role <- member_of(~w(axiom conjecture definition lemma hypothesis)),
          body <- formula(),
          annotation <- annotation()
        ) do
      "fof(#{name}, #{role}, #{body}#{annotation})."
    end
  end

  defp name do
    member_of(["a", "b", "c", "fof", "inference", "file", "include", "unknown", "42", "'a name'"])
  end

  defp annotation do
    one_of([
      constant(""),
      constant(", unknown"),
      constant(", inference(rule, [status(thm)], [a])"),
      constant(", file('x.p', y)"),
      constant(", introduced(definition, [], [])"),
      constant(", unknown, [$fof(p), description('why')]")
    ])
  end

  defp formula do
    tree(
      one_of([
        constant("p"),
        constant("q(a)"),
        constant("r(X, f(Y))"),
        constant("$true"),
        constant("a = b"),
        constant("a != b"),
        constant("![X]: p(X)"),
        constant("?[X]: q(X)")
      ]),
      fn child ->
        one_of([
          map(child, &"~ (#{&1})"),
          map(child, &"(#{&1})"),
          map({child, child}, fn {a, b} -> "(#{a} & #{b})" end),
          map({child, child}, fn {a, b} -> "(#{a} | #{b})" end),
          map({child, child}, fn {a, b} -> "(#{a} => #{b})" end),
          map({child, child}, fn {a, b} -> "(#{a} <=> #{b})" end)
        ])
      end
    )
  end
end
