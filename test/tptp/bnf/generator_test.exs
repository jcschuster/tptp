defmodule Tptp.Bnf.GeneratorTest do
  use ExUnit.Case, async: true

  alias Tptp.Bnf
  alias Tptp.Bnf.Generator
  alias Tptp.Bnf.Szs

  setup_all do
    path = Bnf.vendored_path!()
    {grammar, report} = Generator.generate(path)
    %{grammar: grammar, report: report}
  end

  describe "the committed grammar" do
    test "matches what the generator produces right now", %{grammar: grammar} do
      assert File.read!("src/tptp_parser.yrl") == grammar,
             "src/tptp_parser.yrl is stale; run `mix tptp.gen` and commit the result"
    end

    test "compiles, which is the zero-conflict gate" do
      assert Code.ensure_loaded?(:tptp_parser) and function_exported?(:tptp_parser, :parse, 1),
             "the generated parser did not compile; yecc reports conflicts as warnings " <>
               "and mix.exs sets yecc warnings_as_errors"
    end
  end

  describe "translation shape" do
    test "roots at a single statement, not the whole file", %{grammar: grammar} do
      assert grammar =~ "Rootsymbol 'TPTP_input'."
      refute grammar =~ "'TPTP_file'"
    end

    test "prunes only what is unreachable from the root", %{report: report} do
      assert report.pruned == ["TPTP_file", "nothing"]
    end

    test "turns repetition into a right-recursive helper", %{grammar: grammar} do
      assert grammar =~ "'comma_thf_logic_formula_rep' -> '$empty' : []."

      assert grammar =~
               "'comma_thf_logic_formula_rep' -> 'comma_thf_logic_formula' " <>
                 "'comma_thf_logic_formula_rep' : ['$1' | '$2']."
    end

    test "splices repetition into one flat list rather than nesting", %{grammar: grammar} do
      assert grammar =~
               "'thf_formula_list' -> 'thf_logic_formula' 'comma_thf_logic_formula_rep' : " <>
                 "{'$node', 'thf_formula_list', 0, ['$1'] ++ '$2', nil, nil}."
    end

    test "renders an absent optional as nil, not as an empty node", %{grammar: grammar} do
      assert grammar =~ "'annotations' -> '$empty' : nil."
    end

    test "drops punctuation and fixed spellings from the children", %{grammar: grammar} do
      assert grammar =~
               "'fof_annotated' -> 'kw_fof' 'lparen' 'name' 'comma' 'formula_role' 'comma' " <>
                 "'fof_formula' 'annotations' 'rparen' 'dot' : " <>
                 "{'$node', 'fof_annotated', 0, ['$3', '$5', '$7', '$8'], '$1', '$10'}."
    end

    test "turns a single-terminal alternative into a leaf", %{grammar: grammar} do
      assert grammar =~ "'th1_defined_term' -> 'big_forall' : {'$leaf', 'big_forall', 0, '$1'}."
      assert grammar =~ "'th1_defined_term' -> 'big_equal' : {'$leaf', 'big_equal', 4, '$1'}."
    end

    test "inlines single-terminal rules rather than reducing through them", %{report: report} do
      assert "gentzen_arrow" in report.inlined
      assert "infix_equality" in report.inlined
      assert "unary_connective" in report.inlined
    end

    test "keeps the significant chain rules as nodes for the post-pass to collapse", %{
      report: report
    } do
      for name <- ~w(constant functor variable defined_functor name formula_role) do
        assert name in report.significant
      end
    end
  end

  describe "the departures from a mechanical translation" do
    test "no longer needs to drop <source> ::= unknown, since the BNF did", %{grammar: grammar} do
      refute grammar =~ "'source' -> 'kw_unknown'"
      refute grammar =~ "'source' -> 'lower_word'"
      assert length(Generator.departures()) == 3
    end

    test "admits the three source keywords as ordinary atomic words", %{grammar: grammar} do
      assert grammar =~ "'atomic_word' -> 'kw_inference' :"
      assert grammar =~ "'atomic_word' -> 'kw_introduced' :"
      assert grammar =~ "'atomic_word' -> 'kw_file' :"
    end

    test "reserves the dollar keywords", %{grammar: grammar} do
      refute grammar =~ "'atomic_defined_word' -> 'dw_let'"
    end

    test "does not admit the statement keywords as atomic words", %{grammar: grammar} do
      refute grammar =~ "'atomic_word' -> 'kw_fof'"
    end
  end

  describe "vocabularies/2" do
    setup do
      {source, entries} = Generator.vocabularies(Bnf.vendored_path!(), Bnf.szs_path!())
      %{source: source, entries: Map.new(entries)}
    end

    test "extracts every closed :== word list at the size the BNF states", %{entries: entries} do
      # `status_value` is the one list not read from the SyntaxBNF: it is
      # `<inference_status_value>` of the SZS BNF, under the name the SyntaxBNF
      # references. See `Tptp.Bnf.Generator.vocabularies/2`.
      assert Map.new(entries, fn {name, words} -> {name, length(words)} end) == %{
               "defined_functor" => 19,
               "defined_predicate" => 7,
               "defined_proposition" => 2,
               "defined_type" => 8,
               "formula_role" => 14,
               "intro_type" => 4,
               "ntf_connective_name" => 10,
               "ntf_logic_name" => 6,
               "ntf_modal_axiom" => 10,
               "ntf_modal_system" => 16,
               "status_value" => 47,
               "reserved_word" => 113
             }
    end

    test "the corrected lists carry the values the language page defines", %{entries: entries} do
      assert "logic" in entries["formula_role"]

      # The page's arithmetic table defines `$abs/1`; the `:==` rule omits it.
      assert "$abs" in entries["defined_functor"]

      # The extended arithmetic symbols on that page sit inside HTML comments and are
      # not published, so they are not added.
      for proposed <- ~w($min $max $sqrt $pi $exp $succ $pred $pow) do
        refute proposed in entries["defined_functor"]
        refute proposed in entries["reserved_word"]
      end

      # Sys ∈ {K,KB,K4,K5,K45,KB5,D,DB,D4,D5,D45,M,B,S4,S5,S5U} on the page; the
      # `:==` rule names six of them. The ten below are the difference.
      for sys <- ~w(KB K4 K5 K45 KB5 DB D4 D5 D45 S5U) do
        assert "$modal_system_#{sys}" in entries["ntf_modal_system"]
      end

      # Ax ∈ {K,M,B,D,4,5,CD,BoxM,C4,C}; the rule names six.
      for ax <- ~w(CD BoxM C4 C) do
        assert "$modal_axiom_#{ax}" in entries["ntf_modal_axiom"]
      end
    end

    test "a corrected value also enters the reserved words", %{entries: entries} do
      # `Tptp.Lint.Rules.DefinedWord` consults `<reserved_word>` alone, so a value
      # added to a closed list has no effect on it unless it is added here too.
      assert "$modal_system_KB" in entries["reserved_word"]
      assert "$modal_axiom_BoxM" in entries["reserved_word"]
    end

    test "nothing outside @documented_values is corrected", %{entries: entries} do
      assert entries["intro_type"] == ~w(definition tautology assumption theory)
      assert length(entries["ntf_logic_name"]) == 6
      refute "wibble" in entries["formula_role"]

      # Neither published source names this system, and 17 library files mention it
      # in a header comment the lexer never reaches.
      refute "$modal_system_T" in entries["ntf_modal_system"]
      refute "$modal_system_T" in entries["reserved_word"]
    end

    test "a $-word applied in a rule is still a reserved word", %{entries: entries} do
      reserved = entries["reserved_word"]

      assert "$ite" in reserved
      assert "$let" in reserved
      assert "$domains" in reserved
    end

    test "strips the braces the BNF writes around the modal connectives", %{entries: entries} do
      connectives = entries["ntf_connective_name"]
      assert "$necessary" in connectives
      assert "$box" in connectives
      refute Enum.any?(connectives, &String.contains?(&1, "{"))
    end

    test "keeps the enumeration when a rule also has a generalising alternative", %{
      entries: entries
    } do
      assert Enum.sort(entries["defined_proposition"]) == ["$false", "$true"]
      assert "$distinct" in entries["defined_predicate"]
    end

    test "excludes rules that are structural rather than closed word lists", %{entries: entries} do
      refute Map.has_key?(entries, "tff_plain_atomic")
      refute Map.has_key?(entries, "atomic_type")
      refute Map.has_key?(entries, "th1_quantified_type")
    end

    test "takes <status_value> from the SZS BNF, in its order", %{entries: entries} do
      assert entries["status_value"] ==
               Szs.read!(Bnf.szs_path!()).mnemonics

      assert hd(entries["status_value"]) == "suc"
      assert "thm" in entries["status_value"]
    end

    test "refuses a SyntaxBNF that defines <status_value> itself" do
      path = Path.join(System.tmp_dir!(), "SyntaxBNF-v0.0.0.0")
      File.write!(path, "<inference_status> :== status(<status_value>)\n<status_value> :== thm\n")

      assert_raise ArgumentError, ~r/defines <status_value> itself/, fn ->
        Generator.vocabularies(path, Bnf.szs_path!())
      end
    end

    test "refuses a SyntaxBNF that no longer references <status_value>" do
      path = Path.join(System.tmp_dir!(), "SyntaxBNF-v0.0.0.1")
      File.write!(path, "<inference_status> :== <inference_info>\n")

      assert_raise ArgumentError, ~r/no longer references <status_value>/, fn ->
        Generator.vocabularies(path, Bnf.szs_path!())
      end
    end

    test "matches the committed module", %{source: source} do
      formatted = source |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")

      assert File.read!("lib/tptp/bnf/vocabulary.ex") == formatted,
             "lib/tptp/bnf/vocabulary.ex is stale; run `mix tptp.gen`"
    end
  end
end
