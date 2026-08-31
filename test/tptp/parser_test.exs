defmodule Tptp.ParserTest do
  use ExUnit.Case, async: true

  doctest Tptp.Node
  doctest Tptp.Parser
  doctest Tptp.Statement.Include

  alias Tptp.Node
  alias Tptp.Parser
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include

  defp parse!(source) do
    {:ok, statement, []} = Parser.statement_from_string(source)
    statement
  end

  defp formula(source), do: parse!(source).formula

  defp kinds(source), do: source |> formula() |> Node.walk() |> Enum.map(& &1.kind)

  defp codes(source) do
    {:error, diagnostics} = Parser.statement_from_string(source)
    Enum.map(diagnostics, & &1.code)
  end

  describe "statements" do
    test "an annotated formula carries its name, role and formula" do
      statement = parse!("fof(a, axiom, p).")

      assert %Annotated{language: :fof} = statement
      assert statement.name.text == "a"
      assert statement.role.text == "axiom"
      assert statement.formula.text == "p"
      assert statement.source == nil
      assert statement.info == nil
    end

    test "every language builds its own statement" do
      for {source, language} <- [
            {"thf(a, type, f: $i).", :thf},
            {"tff(a, axiom, p).", :tff},
            {"tcf(a, axiom, p).", :tcf},
            {"fof(a, axiom, p).", :fof},
            {"cnf(a, axiom, p).", :cnf},
            {"tpi(a, axiom, p).", :tpi}
          ] do
        assert %Annotated{language: ^language} = parse!(source)
      end
    end

    test "the statement span covers the whole statement, keyword and dot included" do
      source = "  fof(a, axiom, p).  "
      {:ok, statement, []} = Parser.statement_from_string(source)

      assert Tptp.Statement.text(statement, source) == "fof(a, axiom, p)."
    end

    test "source and info are retained, because that is what TSTP is" do
      statement = parse!("fof(a, axiom, p, inference(resolution, [status(thm)], [b, c])).")

      assert statement.source.kind == :inference_record
      assert statement.info == nil

      assert statement.source |> Node.select(:inference_rule) |> Enum.map(& &1.text) == [
               "resolution"
             ]

      assert statement.source |> Node.select(:name) |> Enum.map(& &1.text) == ["b", "c"]
    end

    test "useful_info arrives as its own subtree" do
      statement = parse!("fof(a, axiom, p, unknown, [description('why')]).")

      assert statement.source.kind == :name
      assert statement.info.kind == :general_list
    end

    test "a formula may be named after a keyword" do
      assert parse!("fof(fof, axiom, p).").name.text == "fof"
      assert parse!("fof(inference, axiom, p).").name.text == "inference"
      assert parse!("fof(include, axiom, p).").name.text == "include"
    end

    test "a role may be a keyword too" do
      assert parse!("fof(a, file, p).").role.text == "file"
    end

    test "a role may carry a general term" do
      statement = parse!("fof(a, assumption-[1], p).")

      assert statement.role.kind == :formula_role
      assert statement.role.children != []
    end
  end

  describe "include statements" do
    test "an include carries its file name" do
      statement = parse!("include('Axioms/SET007+0.ax').")

      assert %Include{} = statement
      assert statement.file_name.text == "'Axioms/SET007+0.ax'"
      assert Include.path(statement) == "Axioms/SET007+0.ax"
      assert Include.selected(statement) == nil
    end

    test "a selection lists the names it takes" do
      statement = parse!("include('a.ax', [b, c, d]).")

      assert Include.selected(statement) == ["b", "c", "d"]
    end

    test "a star selection means the whole file, the same as no selection" do
      assert "include('a.ax', *)." |> parse!() |> Include.selected() == nil
    end

    test "the third argument is kept without meaning attached" do
      statement = parse!("include('a.ax', [b], space).")

      assert statement.space_name.text == "space"
    end

    test "an escaped quote in a file name is unescaped for the resolver" do
      assert "include('it\\'s.ax')." |> parse!() |> Include.path() == "it's.ax"
    end

    test "include?/1 and the parsed struct agree" do
      {[input], _comments, []} = Tptp.Splitter.inputs("include('a.ax').")

      assert Tptp.Input.include?(input)
      assert %Include{} = parse!("include('a.ax').")
    end
  end

  describe "the shape of the tree" do
    test "negation survives as a node" do
      assert :fof_unary_formula in kinds("fof(a, axiom, ~p).")
      assert :cnf_literal in kinds("cnf(a, axiom, ~p).")
    end

    test "parentheses survive as a node, so spans stay contiguous" do
      formula = formula("fof(a, axiom, (p & q) | r).")

      assert formula.kind == :fof_or_formula
      assert [grouped, _r] = formula.children
      assert grouped.kind == :fof_unitary_formula
      assert Node.text(grouped, "fof(a, axiom, (p & q) | r).") == "(p & q)"
    end

    test "a bracketed list is not confusable with its contents" do
      assert :general_list in kinds("fof(a, axiom, p, unknown, [b]).") == false
      assert parse!("fof(a, axiom, p, unknown, [b]).").info.kind == :general_list
    end

    test "an argument keeps its own kind rather than the list's" do
      assert :variable in kinds("tff(a, axiom, p(X)).")
      assert :constant in kinds("tff(a, axiom, p(b)).")
    end

    test "punctuation is dropped but connectives that name nothing are kept" do
      refute :comma in kinds("fof(a, axiom, p(b, c)).")
      refute :lparen in kinds("fof(a, axiom, p(b)).")
      assert :implies in kinds("fof(a, axiom, p => q).")
      assert :iff in kinds("fof(a, axiom, p <=> q).")
    end

    test "the language marker of a formula_data is a child, not an alternative index" do
      statement = parse!("fof(a, axiom, p, unknown, [$fof(q), $cnf(r)]).")
      markers = statement.info |> Node.select(:formula_data) |> Enum.map(&hd(&1.children).kind)

      assert markers == [:dw_fof, :dw_cnf]
    end
  end

  describe "significant chain rules" do
    test "a symbol's role is stamped onto its leaf" do
      assert :constant in kinds("fof(a, axiom, p(b)).")
      assert :functor in kinds("fof(a, axiom, p(b)).")
      assert :variable in kinds("fof(a, axiom, p(X)).")
      assert :defined_type in kinds("tff(a, type, f: $i).")
    end

    test "in THF the same $i is a defined_constant, because the grammar cannot tell" do
      assert :defined_constant in kinds("thf(a, type, f: $i).")
      refute :defined_type in kinds("thf(a, type, f: $i).")
    end

    test "the same word takes a different role in a different position" do
      assert %Node{kind: :functor, text: "f"} = "fof(a, axiom, f(b))." |> formula() |> hd_child()

      assert %Node{kind: :constant, text: "f"} =
               "fof(a, axiom, p(f))." |> formula() |> last_child()
    end

    test "the outermost name of a chain wins" do
      assert "fof(a, axiom, p(f))." |> formula() |> last_child() |> Map.get(:kind) == :constant
    end

    test "a collapsed leaf keeps its text and span" do
      source = "fof(a, axiom, p(f))."
      leaf = source |> formula() |> last_child()

      assert leaf.children == []
      assert leaf.text == binary_part(source, leaf.off, leaf.len)
    end

    defp hd_child(node), do: hd(node.children)
    defp last_child(node), do: List.last(node.children)
  end

  describe "polymorphic constants" do
    test "an explicit type argument is an ordinary argument in source order" do
      formula = formula("thf(a, axiom, f @ $i @ b).")

      assert formula.kind == :thf_apply_formula
      assert [inner, %Node{kind: :constant, text: "b"}] = formula.children

      assert [%Node{kind: :constant, text: "f"}, %Node{kind: :defined_constant, text: "$i"}] =
               inner.children
    end

    test "the TH1 defined terms arrive with a precise kind" do
      for {spelling, kind} <- [
            {"!!", :big_forall},
            {"??", :big_exists},
            {"@@+", :big_choice},
            {"@@-", :big_desc},
            {"@=", :big_equal}
          ] do
        formula = formula("thf(a, axiom, #{spelling} @ p).")

        assert [%Node{kind: ^kind}, _argument] = formula.children,
               "#{spelling} must arrive as #{kind}"
      end
    end

    test "a rank-1 type scheme is kept verbatim" do
      kinds = kinds("thf(a, type, g: !>[A: $tType]: (A > A)).")

      assert :type_forall in kinds
      assert :thf_mapping_type in kinds
      assert :thf_typed_variable in kinds
    end

    test "nothing is uncurried, saturated or instantiated" do
      source = "thf(a, axiom, f @ $i @ b @ c)."
      formula = formula(source)

      assert Node.text(formula, source) == "f @ $i @ b @ c"
      assert formula |> Node.walk() |> Enum.count(&(&1.kind == :thf_apply_formula)) == 3
    end
  end

  describe "spans" do
    test "a node's span covers its own brackets" do
      source = "fof(a, axiom, p(b, c))."
      term = formula(source)

      assert Node.text(term, source) == "p(b, c)"
    end

    test "a leaf's text is exactly the bytes its span names" do
      source = "fof(a, axiom, 'quoted name'(b))."

      for node <- source |> formula() |> Node.walk(), node.text != nil do
        assert node.text == binary_part(source, node.off, node.len)
      end
    end

    test "children never escape their parent" do
      source = "fof(a, axiom, ![X]: (p(X) & q))."

      for parent <- source |> formula() |> Node.walk(), child <- parent.children do
        assert child.off >= parent.off
        assert child.off + child.len <= parent.off + parent.len
      end
    end

    test "at/2 finds the innermost node under an offset" do
      source = "fof(a, axiom, p(bcd))."
      argument = source |> formula() |> Node.at(17)

      assert argument.text == "bcd"
    end

    test "at/2 answers nil outside the tree" do
      assert "fof(a, axiom, p)." |> formula() |> Node.at(0) == nil
    end
  end

  describe "errors" do
    test "a syntax error names the token and where it is" do
      {:error, [diagnostic]} = Parser.statement_from_string("fof(a, axiom, p q).")

      assert diagnostic.code == "TPTP0301"
      assert diagnostic.message == "unexpected `q`"
      assert diagnostic.span.offset == 16
      assert diagnostic.hint =~ "fof"
    end

    test "a truncated statement is reported as ending too early" do
      assert codes("fof(a, axiom, p)") == ["TPTP0302", "TPTP0106"]
    end

    test "an unrecognised language never reaches the grammar" do
      assert codes("wibble(a, axiom, p).") == ["TPTP0201"]
    end

    test "statement_from_string refuses a source holding more than one" do
      assert ["TPTP0303"] = codes("fof(a, axiom, p). fof(b, axiom, q).")
    end

    test "an error carries the splitter's diagnostics too" do
      {:error, diagnostics} = Parser.statement_from_string("fof(a, axiom, p")

      assert Enum.map(diagnostics, & &1.code) == ["TPTP0302", "TPTP0106"]
    end
  end

  describe "detaching and comparing" do
    test "shape/1 ignores position" do
      one = formula("fof(a, axiom, p(b) & q).")
      two = formula("fof(a,axiom,p( b )&q).")

      assert Node.shape(one) == Node.shape(two)
    end

    test "shape/1 still separates different trees" do
      refute Node.shape(formula("fof(a, axiom, p & q).")) ==
               Node.shape(formula("fof(a, axiom, p | q)."))
    end

    test "detach/1 copies every leaf out of the source binary" do
      source = String.duplicate("% padding\n", 1000) <> "fof(a, axiom, p(bcd))."
      {:ok, statement, []} = Parser.statement_from_string(source)
      detached = Node.detach(statement.formula)

      assert Node.shape(detached) == Node.shape(statement.formula)

      for node <- Node.walk(detached), node.text != nil do
        assert :binary.referenced_byte_size(node.text) == byte_size(node.text)
      end
    end
  end
end
