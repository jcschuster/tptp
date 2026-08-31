defmodule Tptp.TokenTest do
  use ExUnit.Case, async: true

  doctest Tptp.Token

  alias Tptp.Token

  test "spellings are ordered longest first, so prefix matching is maximal munch" do
    lengths = Enum.map(Token.spellings(), fn {_category, spelling} -> byte_size(spelling) end)
    assert lengths == Enum.sort(lengths, :desc)
  end

  test "no spelling is reachable only after a shorter prefix of itself" do
    for {category, spelling} <- Token.spellings() do
      first =
        Enum.find(Token.spellings(), fn {_c, candidate} ->
          String.starts_with?(spelling, candidate)
        end)

      assert first == {category, spelling},
             "#{inspect(spelling)} would be shadowed by #{inspect(elem(first, 1))}"
    end
  end

  test "every category is unique" do
    categories = Token.categories()
    assert length(categories) == length(Enum.uniq(categories))
  end

  test "every spelling is unique" do
    spellings = Enum.map(Token.spellings(), &elem(&1, 1))
    assert length(spellings) == length(Enum.uniq(spellings))
  end

  test "value categories carry no fixed spelling and fixed categories do" do
    for category <- Token.value_categories() do
      assert Token.spelling(category) == nil
    end

    for {category, spelling} <- Token.spellings() do
      assert Token.spelling(category) == spelling
    end
  end

  test "the operators that are easiest to mis-order resolve to the longest match" do
    for {text, expected} <- [
          {"<=>", :iff},
          {"<~>", :xor},
          {"<=", :impliedby},
          {"<<", :subtype_sign},
          {"<", :less_sign},
          {"@@+", :big_choice},
          {"@+", :choice},
          {"@", :apply},
          {"!!", :big_forall},
          {"!=", :not_equal},
          {"!>", :type_forall},
          {"!", :forall},
          {"?*", :type_exists},
          {"??", :big_exists},
          {"?", :exists},
          {"-->", :gentzen_arrow},
          {"-", :minus},
          {"~|", :nor},
          {"~&", :nand},
          {"~", :tilde},
          {"[.]", :short_bracket},
          {"<.>", :short_angle}
        ] do
      assert Token.category_for(text) == expected
    end
  end

  test "the four short connectives are single tokens" do
    for category <- [:short_bracket, :short_angle, :short_brace, :short_paren] do
      assert byte_size(Token.spelling(category)) == 3
    end
  end

  test "unknown is not a keyword, so it stays an ordinary lower word" do
    assert Token.category_for("unknown") == nil
    refute :kw_unknown in Token.categories()
  end

  test "punctuation is exactly the set the CST drops" do
    punctuation = Enum.filter(Token.categories(), &Token.punctuation?/1)

    assert Enum.sort(punctuation) == [
             :colon,
             :comma,
             :dot,
             :lbrace,
             :lbracket,
             :lparen,
             :rbrace,
             :rbracket,
             :rparen
           ]
  end
end
