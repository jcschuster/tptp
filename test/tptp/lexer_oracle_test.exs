defmodule Tptp.LexerOracleTest do
  @moduledoc """
  The hand-written lexer against the BNF's own token rules.

  `Tptp.Bnf.OracleTable` is the `::-` and `:::` layer transcribed mechanically into
  anchored regular expressions by `mix tptp.gen`. It is slow, it cannot scan, and it
  has no idea what maximal munch is — which is exactly why it is a useful second
  opinion. The lexer is the one stage of this library that is not derived from the
  BNF, so it is the one stage that can drift from it silently.

  Three directions, because each catches a different mistake:

    * **Forward.** A string the oracle accepts as a `<lower_word>` lexes to one
      `:lower_word` token. Catches a lexer that stops early or rejects.
    * **Backward.** Every value-carrying token the lexer emits, from generated input
      and from the corpus, satisfies its own BNF pattern. Catches a lexer that
      accepts more than the grammar does.
    * **Exclusive.** A token's text does not also satisfy a *different* value
      category's pattern, except where the BNF itself overlaps. Catches a
      misclassification that both other directions would let through.

  ## Tokens the lexer complained about are exempt, and that is the point

  The library never rejects input; it emits the token and a diagnostic beside it.
  `''` is the case that matters — `<single_quoted>` requires at least one `<sq_char>`
  where `<distinct_object>` allows none, so `""` is legal TPTP and `''` is not — and
  the lexer produces a `:single_quoted` token *and* a `TPTP0107`. `00` is the other
  — `<unsigned_integer>` forbids a redundant leading zero, and the diagnostic points
  at the zero rather than at the whole token, which is why the exemption is by
  overlap rather than by an exact span. Excluding tokens a diagnostic already covers
  is therefore not a hole in the property; it makes the
  property say the useful thing: **the lexer's departures from the BNF are exactly
  the ones it reports.** A silent departure still fails.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tptp.Bnf.OracleTable
  alias Tptp.Lexer
  alias Tptp.Token

  @value_categories Token.value_categories()
  @names Enum.map(@value_categories, &Atom.to_string/1)

  @overlaps %{
    "integer" => ["real", "rational"],
    "real" => ["integer", "rational"],
    "rational" => ["integer", "real"]
  }

  describe "the oracle itself" do
    test "it has a pattern for every category the lexer carries text for" do
      missing = Enum.reject(@names, &(&1 in OracleTable.names()))

      assert missing == []
    end

    test "it is anchored on both sides" do
      refute OracleTable.matches?("lower_word", "abc def")
      refute OracleTable.matches?("lower_word", "Abc")
      refute OracleTable.matches?("integer", "12a")
      assert OracleTable.matches?("integer", "12")
    end

    test "an unknown name raises rather than quietly matching nothing" do
      assert_raise KeyError, fn -> OracleTable.matches?("no_such_rule", "x") end
    end
  end

  describe "forward: what the BNF accepts, the lexer lexes" do
    @examples %{
      "lower_word" => ~w(p abc a_1 aZ9 fof_like),
      "upper_word" => ~w(X Var_1 XY9),
      "single_quoted" => ["'a name'", "'Axioms/SET007+0.ax'", "'it\\'s'"],
      "back_quoted" => ["`X", "`Var1"],
      "distinct_object" => ["\"a thing\"", "\"\"", "\"say \\\"hi\\\"\""],
      "dollar_word" => ~w($i $o $true $tType),
      "dollar_dollar_word" => ~w($$foo $$bar_1),
      "integer" => ~w(0 7 42 -3 +9),
      "rational" => ~w(1/2 -3/4 0/7),
      "real" => ~w(1.5 -0.25 1.0e10 3E-2 +2.5)
    }

    for {name, samples} <- @examples do
      @name name
      @samples samples

      test "#{name}" do
        category = String.to_existing_atom(@name)

        for sample <- @samples do
          assert OracleTable.matches?(@name, sample),
                 "the oracle rejects #{inspect(sample)} as a <#{@name}>"

          assert lexed(sample) == {category, sample},
                 "the lexer read #{inspect(sample)} as #{inspect(lexed(sample))}"
        end
      end
    end
  end

  describe "backward: what the lexer emits, the BNF accepts" do
    property "on generated input" do
      check all(source <- soup()) do
        for {category, text} <- value_tokens(source), category in @value_categories do
          assert OracleTable.matches?(Atom.to_string(category), text),
                 "the lexer produced #{inspect(text)} as #{category}, which the BNF rejects"
        end
      end
    end

    test "on the syntax exercises in the corpus" do
      for path <- Tptp.Test.Corpus.files(every: 97, max_bytes: 200_000) do
        source = File.read!(path)

        for {category, text} <- value_tokens(source) do
          assert OracleTable.matches?(Atom.to_string(category), text),
                 "#{path}: #{inspect(text)} lexed as #{category}, which the BNF rejects"
        end
      end
    end
  end

  describe "exclusive: a token is not also something else" do
    property "no value token satisfies an unrelated category" do
      check all(source <- soup()) do
        for {category, text} <- value_tokens(source) do
          name = Atom.to_string(category)
          allowed = [name | Map.get(@overlaps, name, [])]
          confused = Enum.filter(@names -- allowed, &OracleTable.matches?(&1, text))

          assert confused == [],
                 "#{inspect(text)} lexed as #{name} but also matches #{inspect(confused)}"
        end
      end
    end

    test "the overlaps the BNF really has are the ones we allow" do
      assert OracleTable.matches?("real", "1.5")
      refute OracleTable.matches?("integer", "1.5")
    end

    test "the two dollar words do not overlap, because $ is not alpha-numeric" do
      refute OracleTable.matches?("dollar_word", "$$foo")
      assert OracleTable.matches?("dollar_dollar_word", "$$foo")
      assert OracleTable.matches?("dollar_word", "$foo")
      refute OracleTable.matches?("dollar_dollar_word", "$foo")
    end
  end

  describe "the deviations the lexer reports" do
    test "an empty quoted atom is emitted as a token and reported" do
      source = "fof('', axiom, p)."
      {statements, _comments, diagnostics} = Lexer.statements(source)
      texts = statements |> List.flatten() |> Enum.map(&Lexer.text(&1, source))

      assert "''" in texts
      refute OracleTable.matches?("single_quoted", "''")
      assert [%{code: "TPTP0107", severity: :warning}] = diagnostics
    end

    test "an empty distinct object is legal, and is not reported" do
      source = "fof(a, axiom, p(\"\"))."
      {_statements, _comments, diagnostics} = Lexer.statements(source)

      assert OracleTable.matches?("distinct_object", "\"\"")
      assert diagnostics == []
    end
  end

  describe "the deviations the lexer documents" do
    test "a spaced short connective is not lexed as one, and the BNF agrees it is odd" do
      assert [{:short_bracket, _offset, _length}] = tokens("[.] .") |> Enum.take(1)
      refute match?([{:short_bracket, _, _}], tokens("[ . ] .") |> Enum.take(1))
    end

    test "a number followed by a dot is a number and a dot, not a real" do
      assert Enum.map(tokens("1."), &elem(&1, 0)) == [:integer, :dot]
      assert Enum.map(tokens("1.5 ."), &elem(&1, 0)) == [:real, :dot]
    end
  end

  defp soup do
    gen all(pieces <- list_of(fragment(), max_length: 24)) do
      Enum.join(pieces, " ")
    end
  end

  defp fragment do
    one_of([
      string(Enum.concat([?a..?z, ?A..?Z, ?0..?9, [?_, ?$, ?', ?", ?., ?/, ?+, ?-]]),
        max_length: 8
      ),
      member_of([
        "p",
        "X",
        "$i",
        "$$q",
        "'a b'",
        "\"d\"",
        "1",
        "-2",
        "1/2",
        "1.5",
        "3E-2",
        "&",
        "|",
        "~",
        "=>",
        "<=>",
        "(",
        ")",
        "[",
        "]",
        ",",
        ".",
        ":",
        "@",
        "!",
        "?"
      ])
    ])
  end

  defp value_tokens(source) do
    {statements, _comments, diagnostics} = Lexer.statements(source)
    reported = Enum.map(diagnostics, &{&1.span.offset, &1.span.offset + &1.span.length})

    for tokens <- statements,
        {category, offset, length} = token <- tokens,
        category in @value_categories,
        not complained?(reported, offset, offset + length),
        do: {category, Lexer.text(token, source)}
  end

  defp complained?(reported, from, to) do
    Enum.any?(reported, fn {start, finish} -> start < to and finish > from end)
  end

  defp tokens(source) do
    {statements, _comments, _diagnostics} = Lexer.statements(source)

    List.flatten(statements)
  end

  defp lexed(text) do
    case tokens(text <> " .") do
      [{category, _offset, _length} = token | _rest] ->
        {category, Lexer.text(token, text <> " .")}

      [] ->
        :nothing
    end
  end
end
