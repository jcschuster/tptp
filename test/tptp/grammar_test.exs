defmodule Tptp.GrammarTest do
  @moduledoc """
  Exercises the generated parser directly, on hand-built token lists.

  `Tptp.Lexer` does not exist yet, so these tests drive `:tptp_parser` with token
  categories written out by hand. That is deliberate for now: it pins the grammar's
  behaviour independently of the scanner, so a later lexer bug cannot quietly look
  like a grammar bug.
  """

  use ExUnit.Case, async: true

  describe "every dialect parses" do
    test "fof" do
      assert {:ok, _tree} =
               parse(~w(kw_fof lparen lower_word comma lower_word comma lower_word
                        lparen upper_word rparen ampersand lower_word rparen dot)a)
    end

    test "cnf" do
      assert {:ok, _tree} =
               parse(~w(kw_cnf lparen lower_word comma lower_word comma lower_word
                        vline tilde lower_word rparen dot)a)
    end

    test "tff with a type declaration" do
      assert {:ok, _tree} =
               parse(~w(kw_tff lparen lower_word comma lower_word comma lower_word
                        colon dollar_word arrow dollar_word rparen dot)a)
    end

    test "tcf" do
      assert {:ok, _tree} =
               parse(~w(kw_tcf lparen lower_word comma lower_word comma forall lbracket
                        upper_word colon lower_word rbracket colon lower_word lparen
                        upper_word rparen rparen dot)a)
    end

    test "thf" do
      assert {:ok, _tree} =
               parse(~w(kw_thf lparen lower_word comma lower_word comma lower_word
                        apply lower_word rparen dot)a)
    end

    test "tpi" do
      assert {:ok, _tree} =
               parse(~w(kw_tpi lparen lower_word comma lower_word comma lower_word rparen dot)a)
    end

    test "include with a formula selection" do
      assert {:ok, _tree} =
               parse(~w(kw_include lparen single_quoted comma lbracket lower_word comma
                        lower_word rbracket rparen dot)a)
    end
  end

  describe "the source keywords stay usable as names" do
    test "a formula may be named inference" do
      assert {:ok, {:"$node", :fof_annotated, 0, [name | _rest], _open, _close}} =
               parse(~w(kw_fof lparen kw_inference comma lower_word comma lower_word rparen dot)a)

      assert {:"$node", :name, 0, [{:"$leaf", :lower_word, 0, {:kw_inference, _off, _len}}], nil,
              nil} =
               name,
             "a formula named `inference` must be indistinguishable from any other " <>
               "lower word once parsed"
    end

    test "an inference record in source position is still an inference record" do
      assert {:ok,
              {:"$node", :fof_annotated, 0, [_name, _role, _formula, annotations], _open, _close}} =
               parse(~w(kw_fof lparen lower_word comma lower_word comma lower_word comma
                        kw_inference lparen lower_word comma lbracket rbracket comma
                        lbracket lower_word rbracket rparen rparen dot)a)

      assert {:"$node", :annotations, 0, [source, nil], _comma, nil} = annotations
      assert {:"$node", :inference_record, 0, _children, _open, _close} = source
    end

    test "unknown parses as a name rather than a reserved word" do
      assert {:ok,
              {:"$node", :fof_annotated, 0, [_name, _role, _formula, annotations], _open, _close}} =
               parse(~w(kw_fof lparen lower_word comma lower_word comma lower_word comma
                        lower_word rparen dot)a)

      assert {:"$node", :annotations, 0, [{:"$node", :name, 0, _, nil, nil}, nil], _comma, nil} =
               annotations
    end
  end

  describe "polymorphic constants survive verbatim" do
    test "an explicit type argument is an ordinary argument in source order" do
      assert {:ok, {:"$node", :thf_annotated, 0, [_name, _role, formula, nil], _open, _close}} =
               parse(~w(kw_thf lparen lower_word comma lower_word comma
                        lower_word apply dollar_word apply lower_word rparen dot)a)

      assert {:"$node", :thf_apply_formula, 1, [inner, argument], nil, nil} = formula
      assert {:"$node", :thf_apply_formula, 0, [head, type_argument], nil, nil} = inner

      assert {:"$node", :constant, 0, _, nil, nil} = head
      assert {:"$node", :defined_constant, 0, _, nil, nil} = type_argument
      assert {:"$node", :constant, 0, _, nil, nil} = argument
    end

    test "the TH1 defined terms arrive with a precise kind" do
      for {category, spelling} <- [
            {:big_forall, "!!"},
            {:big_exists, "??"},
            {:big_choice, "@@+"},
            {:big_desc, "@@-"},
            {:big_equal, "@="}
          ] do
        assert {:ok, {:"$node", :thf_annotated, 0, [_name, _role, formula, nil], _open, _close}} =
                 parse(
                   [:kw_thf, :lparen, :lower_word, :comma, :lower_word, :comma] ++
                     [category, :apply, :lower_word, :rparen, :dot]
                 )

        assert {:"$node", :thf_apply_formula, 0, [{:"$leaf", ^category, _alt, _token}, _arg], nil,
                nil} =
                 formula,
               "expected #{spelling} to arrive as a #{category} leaf"
      end
    end

    test "a rank-1 scheme is kept, and so is the rank-2 one the grammar permits" do
      assert {:ok, _tree} =
               parse(~w(kw_thf lparen lower_word comma lower_word comma lower_word colon
                        type_forall lbracket upper_word colon dollar_word rbracket colon
                        lparen upper_word arrow upper_word rparen rparen dot)a)

      assert {:ok, _tree} =
               parse(~w(kw_thf lparen lower_word comma lower_word comma lower_word colon
                        lparen type_forall lbracket upper_word colon dollar_word rbracket
                        colon lparen upper_word arrow upper_word rparen rparen arrow
                        dollar_word rparen dot)a),
             "THF does not enforce rank-1 syntactically; rejecting this here would " <>
               "make the rank-1 lint impossible to write"
    end
  end

  describe "errors" do
    test "a truncated statement is an error carrying a byte offset" do
      assert {:error, {offset, :tptp_parser, _message}} =
               parse(~w(kw_fof lparen lower_word comma lower_word comma lower_word rparen)a)

      assert is_integer(offset)
    end

    test "the offset is the one the token carried" do
      tokens = [{:kw_fof, 0, 3}, {:lparen, 3, 1}, {:rparen, 4, 1}]
      assert {:error, {4, :tptp_parser, _message}} = :tptp_parser.parse(tokens)
    end
  end

  defp parse(categories) do
    categories
    |> Enum.with_index()
    |> Enum.map(fn {category, index} -> {category, index, 1} end)
    |> :tptp_parser.parse()
  end
end
