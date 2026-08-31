defmodule Tptp.LexerTest do
  use ExUnit.Case, async: true

  doctest Tptp.Lexer

  alias Tptp.Lexer

  describe "the statement terminator against the decimal point" do
    test "a trailing dot after an integer terminates the statement" do
      assert categories("cnf(c,axiom,p(3)).") ==
               [
                 :lower_word,
                 :lparen,
                 :lower_word,
                 :comma,
                 :lower_word,
                 :comma,
                 :lower_word,
                 :lparen,
                 :integer,
                 :rparen,
                 :rparen,
                 :dot
               ]
    end

    test "a dot between digits is part of one real" do
      assert [{:real, 0, 3}] = tokens_of("1.5")
      assert [{:real, 0, 3}, {:dot, 3, 1}] = tokens_of("1.5.")
    end

    test "an integer followed by a dot is two tokens" do
      assert [{:integer, 0, 3}, {:dot, 3, 1}] = tokens_of("123.")
    end

    test "a dot inside a quoted atom does not terminate" do
      assert one_statement("fof('foo.bar',axiom,p).")
    end

    test "a dot inside a comment does not terminate" do
      assert one_statement("% a comment.\nfof(a,axiom,p).")
    end

    test "a dot inside brackets does not terminate" do
      {statements, _comments, _diagnostics} = Lexer.statements("fof(a,axiom,p,[x:y]).")
      assert length(statements) == 1
    end
  end

  describe "numbers" do
    test "integers, signed and not" do
      assert [{:integer, 0, 1}] = tokens_of("0")
      assert [{:integer, 0, 3}] = tokens_of("123")
      assert [{:integer, 0, 2}] = tokens_of("-3")
      assert [{:integer, 0, 2}] = tokens_of("+3")
    end

    test "rationals" do
      assert [{:rational, 0, 3}] = tokens_of("1/2")
      assert [{:rational, 0, 4}] = tokens_of("-1/2")
    end

    test "a slash not followed by a digit is a slash" do
      assert [{:integer, 0, 1}, {:slash, 1, 1}, {:lower_word, 2, 1}] = tokens_of("1/a")
    end

    test "reals, with and without an exponent" do
      assert [{:real, 0, 3}] = tokens_of("1.5")
      assert [{:real, 0, 5}] = tokens_of("1.5e3")
      assert [{:real, 0, 6}] = tokens_of("1.5e-3")
      assert [{:real, 0, 6}] = tokens_of("-1.5e3")
      assert [{:real, 0, 3}] = tokens_of("1e3")
      assert [{:real, 0, 4}] = tokens_of("1E-3")
    end

    test "a malformed exponent falls back rather than swallowing the letter" do
      assert [{:integer, 0, 1}, {:lower_word, 1, 1}] = tokens_of("1e")
      assert [{:integer, 0, 1}, {:lower_word, 1, 2}] = tokens_of("1ex")
    end
  end

  describe "words" do
    test "lower, upper and dollar words" do
      assert [{:lower_word, 0, 5}] = tokens_of("hello")
      assert [{:upper_word, 0, 1}] = tokens_of("X")
      assert [{:upper_word, 0, 4}] = tokens_of("X_12")
      assert [{:dollar_word, 0, 2}] = tokens_of("$i")
      assert [{:dollar_dollar_word, 0, 6}] = tokens_of("$$evil")
    end

    test "a bare dollar is a dollar word" do
      assert [{:dollar_word, 0, 1}] = tokens_of("$")
    end

    test "a dollar word is scanned to its end, never cut at a keyword prefix" do
      assert [{:dollar_word, 0, 4}] = tokens_of("$let")
      assert [{:dollar_word, 0, 7}] = tokens_of("$letter")
      assert [{:dollar_word, 0, 4}, {:lparen, 4, 1}, {:rparen, 5, 1}] = tokens_of("$thf()")
    end

    test "every keyword stays an ordinary word; position decides the rest" do
      for keyword <- ~w(fof thf tff tcf cnf tpi include inference introduced file unknown) do
        assert [{:lower_word, 0, _length}] = tokens_of(keyword),
               "#{keyword} must lex as a lower word; Tptp.Splitter decides the rest"
      end

      for keyword <- ~w($thf $tff $fof $cnf $fot $let) do
        assert [{:dollar_word, 0, 4}] = tokens_of(keyword),
               "#{keyword} must lex as a dollar word; Tptp.Splitter decides the rest"
      end
    end
  end

  describe "quoted atoms and distinct objects" do
    test "a quoted atom keeps its quotes in the span" do
      assert [{:single_quoted, 0, 5}] = tokens_of("'cat'")
    end

    test "escapes do not end the token" do
      assert [{:single_quoted, 0, 8}] = tokens_of(~S('a\'b\\'))
      assert [{:distinct_object, 0, 8}] = tokens_of(~S("a\"b\\"))
    end

    test "a distinct object may be empty but a quoted atom may not" do
      assert [{:distinct_object, 0, 2}] = tokens_of(~S(""))
      assert codes(~S("")) == ["TPTP0106"]

      assert [{:single_quoted, 0, 2}] = tokens_of("''")
      assert [empty] = filter_codes("''", "TPTP0107")
      assert empty.severity == :warning
    end

    test "a back quote takes an upper word and no closing quote" do
      assert [{:back_quoted, 0, 4}] = tokens_of("`Foo")
    end

    test "a back quote without an upper word is a diagnostic" do
      assert [_diagnostic] = filter_codes("`x", "TPTP0109")
    end
  end

  describe "the short connectives" do
    test "each is a single token" do
      assert [{:short_bracket, 0, 3}] = tokens_of("[.]")
      assert [{:short_angle, 0, 3}] = tokens_of("<.>")
      assert [{:short_brace, 0, 3}] = tokens_of("{.}")
      assert [{:short_paren, 0, 3}] = tokens_of("(.)")
    end

    test "an angle short connective does not split the statement" do
      {statements, _comments, diagnostics} = Lexer.statements("tff(a,axiom,<.> p).")

      assert length(statements) == 1,
             "`<.>` holds a bare dot at bracket depth zero; lexing it as three tokens " <>
               "would cut the statement in half"

      assert diagnostics == []
    end
  end

  describe "operators" do
    test "longest match wins" do
      assert [{:iff, 0, 3}] = tokens_of("<=>")
      assert [{:impliedby, 0, 2}] = tokens_of("<=")
      assert [{:subtype_sign, 0, 2}] = tokens_of("<<")
      assert [{:less_sign, 0, 1}] = tokens_of("<")
      assert [{:xor, 0, 3}] = tokens_of("<~>")
      assert [{:big_choice, 0, 3}] = tokens_of("@@+")
      assert [{:choice, 0, 2}] = tokens_of("@+")
      assert [{:apply, 0, 1}] = tokens_of("@")
      assert [{:gentzen_arrow, 0, 3}] = tokens_of("-->")
      assert [{:nor, 0, 2}] = tokens_of("~|")
      assert [{:nand, 0, 2}] = tokens_of("~&")
      assert [{:type_forall, 0, 2}] = tokens_of("!>")
      assert [{:not_equal, 0, 2}] = tokens_of("!=")
      assert [{:big_forall, 0, 2}] = tokens_of("!!")
    end

    test "the TH1 polymorphic constants each get their own category" do
      assert [{:big_forall, 0, 2}] = tokens_of("!!")
      assert [{:big_exists, 0, 2}] = tokens_of("??")
      assert [{:big_choice, 0, 3}] = tokens_of("@@+")
      assert [{:big_desc, 0, 3}] = tokens_of("@@-")
      assert [{:big_equal, 0, 2}] = tokens_of("@=")
    end
  end

  describe "comments" do
    test "a line comment is a side channel, not a token" do
      {statements, comments, []} = Lexer.statements("% hi\nfof(a,axiom,p).")
      assert [{0, 4, :line, :plain}] = comments
      assert Enum.map(hd(statements), &elem(&1, 0)) |> hd() == :lower_word
    end

    test "block comments, and the pragma classes" do
      assert {_statements, [{0, 8, :block, :plain}], []} = Lexer.statements("/* hi */")
      assert {_statements, [{0, 9, :block, :defined}], []} = Lexer.statements("/*$ hi */")
      assert {_statements, [{0, 10, :block, :system}], []} = Lexer.statements("/*$$ hi */")
      assert {_statements, [{0, 5, :line, :defined}], []} = Lexer.statements("%$ hi")
      assert {_statements, [{0, 6, :line, :system}], []} = Lexer.statements("%$$ hi")
    end

    test "a comment between two tokens does not act as white space" do
      {[tokens], comments, []} = Lexer.statements("fof/* c */(a,axiom,p).")
      assert [{_offset, _length, :block, :plain}] = comments
      assert Enum.map(tokens, &elem(&1, 0)) |> Enum.take(2) == [:lower_word, :lparen]
    end
  end

  describe "diagnostics" do
    test "an illegal character is reported and skipped" do
      {_statements, [], [diagnostic]} = Lexer.statements("fof\0(a,axiom,p).")
      assert diagnostic.code == "TPTP0101"
      assert diagnostic.span.offset == 3
    end

    test "an unterminated quote does not swallow the rest of the file" do
      {_statements, [], diagnostics} = Lexer.statements("fof('oops,axiom,p).\nfof(b,axiom,q).")
      assert Enum.any?(diagnostics, &(&1.code == "TPTP0102"))
    end

    test "an unterminated block comment is reported" do
      {_statements, [{0, 8, :block, :plain}], [diagnostic]} = Lexer.statements("/* oops ")
      assert diagnostic.code == "TPTP0104"
    end

    test "a closing bracket with nothing open is reported" do
      assert [diagnostic] = filter_codes("fof).", "TPTP0105")
      assert diagnostic.span.offset == 3
    end

    test "a file ending mid-statement is reported" do
      {_statements, [], [diagnostic]} = Lexer.statements("fof(a,axiom,p)")
      assert diagnostic.code == "TPTP0106"
    end

    test "a diagnostic carries the file id it was scanned under" do
      {_statements, [], [diagnostic]} = Lexer.statements("\0", 7)
      assert diagnostic.span.file == 7
    end
  end

  describe "resumability" do
    test "next_statement/3 hands back the offset to continue from" do
      source = "fof(a,axiom,p).\nfof(b,axiom,q)."

      assert {:statement, first, next, [], []} = Lexer.next_statement(source, 0)
      assert length(first) == 9
      assert {:statement, second, final, [], []} = Lexer.next_statement(source, next)
      assert length(second) == 9
      assert {:eof, _offset, [], []} = Lexer.next_statement(source, final)
    end

    test "an empty file is an immediate end of input" do
      assert {:eof, 0, [], []} = Lexer.next_statement("", 0)
      assert Lexer.statements("") == {[], [], []}
    end

    test "a file of only white space and comments yields no statements" do
      assert {[], [{0, 4, :line, :plain}], []} = Lexer.statements("% hi\n\n  \n")
    end
  end

  describe "spans" do
    test "every token span indexes the bytes it claims to" do
      source = "fof(a,axiom,'q r' & X != 1.5)."
      {[tokens], [], []} = Lexer.statements(source)

      texts = Enum.map(tokens, &Lexer.text(&1, source))

      assert texts == [
               "fof",
               "(",
               "a",
               ",",
               "axiom",
               ",",
               "'q r'",
               "&",
               "X",
               "!=",
               "1.5",
               ")",
               "."
             ]
    end

    test "concatenating tokens, comments and the gaps reproduces the file" do
      source = """
      % header
      fof(a, axiom, p(X) & q).
      /* block */
      cnf(c, axiom, p | ~q).
      """

      assert reassemble(source) == source
    end
  end

  defp codes(source) do
    {_statements, _comments, diagnostics} = Lexer.statements(source)
    Enum.map(diagnostics, & &1.code)
  end

  defp filter_codes(source, code) do
    {_statements, _comments, diagnostics} = Lexer.statements(source)
    Enum.filter(diagnostics, &(&1.code == code))
  end

  defp tokens_of(source) do
    {statements, _comments, _diagnostics} = Lexer.statements(source)
    List.flatten(statements)
  end

  defp categories(source) do
    source |> tokens_of() |> Enum.map(&elem(&1, 0))
  end

  defp one_statement(source) do
    {statements, _comments, diagnostics} = Lexer.statements(source)
    assert diagnostics == []
    assert length(statements) == 1
    true
  end

  defp reassemble(source) do
    {statements, comments, []} = Lexer.statements(source)

    spans =
      Enum.flat_map(statements, fn tokens ->
        Enum.map(tokens, fn {_category, offset, length} -> {offset, length} end)
      end) ++ Enum.map(comments, fn {offset, length, _form, _class} -> {offset, length} end)

    {parts, position} =
      spans
      |> Enum.sort()
      |> Enum.reduce({[], 0}, fn {offset, length}, {parts, position} ->
        gap = binary_part(source, position, offset - position)
        {[binary_part(source, offset, length), gap | parts], offset + length}
      end)

    tail = binary_part(source, position, byte_size(source) - position)
    [tail | parts] |> Enum.reverse() |> IO.iodata_to_binary()
  end
end
