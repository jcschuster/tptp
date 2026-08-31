defmodule Tptp.BnfTest do
  use ExUnit.Case, async: true

  alias Tptp.Bnf
  alias Tptp.Bnf.Rule

  setup_all do
    path = Bnf.vendored_path!()
    %{path: path, rules: Bnf.read!(path)}
  end

  describe "version!/1" do
    test "reads the version out of the filename" do
      assert Bnf.version!("priv/bnf/SyntaxBNF-v9.3.1.2") == "9.3.1.2"
    end

    test "refuses a filename it cannot read a version from" do
      assert_raise ArgumentError, ~r/expected a name like/, fn ->
        Bnf.version!("priv/bnf/SyntaxBNF")
      end
    end
  end

  describe "read!/1 over the vendored BNF" do
    test "finds the expected number of rules per separator", %{rules: rules} do
      assert Enum.frequencies_by(rules, & &1.separator) == %{
               "::=" => 229,
               ":==" => 67,
               "::-" => 18,
               ":::" => 38
             }
    end

    test "finds the expected number of alternatives", %{rules: rules} do
      alternatives = fn separator ->
        rules |> Bnf.with_separator(separator) |> Enum.map(&length(&1.alternatives)) |> Enum.sum()
      end

      assert alternatives.("::=") == 439
      assert alternatives.(":==") == 237
    end

    test "leaves token and character-class rules unparsed", %{rules: rules} do
      for rule <- Bnf.with_separator(rules, "::-") ++ Bnf.with_separator(rules, ":::") do
        assert rule.alternatives == nil
        assert rule.raw != ""
      end
    end

    test "records the source line of every rule", %{rules: rules} do
      assert Enum.all?(rules, &(&1.line > 0))
      assert %Rule{line: 37} = Enum.find(rules, &(&1.lhs == "TPTP_file"))
    end
  end

  describe "read!/1 on the alternatives that are easy to get wrong" do
    test "treats a bare pipe as alternation and <vline> as a literal", %{rules: rules} do
      rule = syntactic(rules, "nonassoc_connective")

      assert rule.alternatives == [
               [literal: "<=>"],
               [literal: "=>"],
               [literal: "<="],
               [literal: "<~>"],
               [literal: "~", ref: "vline"],
               [literal: "~&"]
             ]
    end

    test "keeps the short connectives' spelling", %{rules: rules} do
      assert syntactic(rules, "ntf_short_connective").alternatives == [
               [literal: "[.]"],
               [ref: "less_sign", literal: ".", ref: "arrow"],
               [literal: "{.}"],
               [literal: "(.)"]
             ]
    end

    test "keeps a trailing `).` together with the rest of the statement", %{rules: rules} do
      assert [[{:literal, "tpi("} | _rest] = alternative] =
               syntactic(rules, "tpi_annotated").alternatives

      assert List.last(alternative) == {:literal, ")."}
    end

    test "reads an empty right-hand side as one empty alternative", %{rules: rules} do
      assert syntactic(rules, "nothing").alternatives == [[]]
    end

    test "marks repetition with a trailing literal star", %{rules: rules} do
      assert syntactic(rules, "thf_formula_list").alternatives == [
               [ref: "thf_logic_formula", ref: "comma_thf_logic_formula", literal: "*"]
             ]
    end

    test "finds repetition in exactly six syntactic rules", %{rules: rules} do
      repeating =
        rules
        |> Bnf.with_separator("::=")
        |> Enum.filter(fn rule ->
          Enum.any?(rule.alternatives, &Enum.member?(&1, {:literal, "*"}))
        end)
        |> Enum.map(& &1.lhs)

      assert repeating == ~w(
               TPTP_file thf_formula_list tff_arguments
               fof_formula_tuple_list parent_list general_terms
             )
    end
  end

  describe "definitions/1" do
    test "prefers the syntactic rule when a name carries both", %{rules: rules} do
      definitions = Bnf.definitions(rules)

      assert definitions["formula_role"] == "::="
      assert definitions["thf_unitary_type"] == "::="
      assert definitions["status_value"] == ":=="
      assert definitions["lower_word"] == "::-"
      assert definitions["alpha_numeric"] == ":::"
    end

    test "fourteen names carry both a syntactic and a semantic rule", %{rules: rules} do
      both =
        MapSet.intersection(
          names(rules, "::="),
          names(rules, ":==")
        )

      assert MapSet.size(both) == 14
      assert "formula_role" in both
      assert "thf_unitary_type" in both
    end
  end

  describe "merge_alternatives/1" do
    test "merges the two rules that share a left-hand side and separator", %{rules: rules} do
      duplicated =
        rules
        |> Enum.group_by(&{&1.lhs, &1.separator})
        |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
        |> Enum.map(&elem(&1, 0))

      assert Enum.sort(duplicated) == [
               {"defined_predicate", ":=="},
               {"defined_proposition", ":=="}
             ]

      merged = Bnf.merge_alternatives(rules)
      assert length(merged) == length(rules) - 2

      predicate = Enum.find(merged, &(&1.lhs == "defined_predicate" and &1.separator == ":=="))
      assert length(predicate.alternatives) == 8
    end

    test "preserves source order", %{rules: rules} do
      merged = Bnf.merge_alternatives(rules)
      assert hd(merged).lhs == "TPTP_file"
    end
  end

  defp syntactic(rules, name) do
    Enum.find(rules, &(&1.lhs == name and &1.separator == "::="))
  end

  defp names(rules, separator) do
    rules |> Bnf.with_separator(separator) |> MapSet.new(& &1.lhs)
  end
end
