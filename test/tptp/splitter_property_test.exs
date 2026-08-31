defmodule Tptp.SplitterPropertyTest do
  @moduledoc """
  The splitter's invariants, over generated input rather than chosen input.

  The defining one is the partition: splitting must not invent, drop, reorder or
  re-categorise a token, and the only categories it may change are the keyword
  promotions it exists to make. A corpus test cannot show this, because a corpus
  file is well-formed and the interesting inputs are not.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tptp.Input
  alias Tptp.Lexer
  alias Tptp.Splitter

  @printable Enum.concat([?\s..?~, [?\n, ?\t, ?\r]])

  @promotions Enum.map(
                Tptp.Token.statement_keywords() ++
                  Tptp.Token.source_keywords() ++ Tptp.Token.dollar_keywords(),
                &elem(&1, 0)
              )

  property "never raises, whatever the bytes" do
    check all(source <- binary()) do
      assert {_inputs, _comments, _diagnostics} = Splitter.inputs(source)
    end
  end

  property "the inputs partition the lexer's token stream, in order" do
    check all(source <- ascii_soup()) do
      {statements, _comments, _diagnostics} = Lexer.statements(source)
      {inputs, _comments, _diagnostics} = Splitter.inputs(source)

      assert length(inputs) == length(statements)

      for {tokens, input} <- Enum.zip(statements, inputs) do
        assert Enum.map(tokens, &{elem(&1, 1), elem(&1, 2)}) ==
                 Enum.map(input.tokens, &{elem(&1, 1), elem(&1, 2)}),
               "splitting moved or dropped a token"
      end
    end
  end

  property "only keyword categories ever change, and only towards a promotion" do
    check all(source <- ascii_soup()) do
      {statements, _comments, _diagnostics} = Lexer.statements(source)
      {inputs, _comments, _diagnostics} = Splitter.inputs(source)

      for {tokens, input} <- Enum.zip(statements, inputs),
          {{before, _offset, _length}, {now, _o, _l}} <- Enum.zip(tokens, input.tokens),
          before != now do
        assert before in [:lower_word, :dollar_word],
               "#{before} was rewritten, and only words may be"

        assert now in @promotions, "#{before} became #{now}, which is not a keyword"
      end
    end
  end

  property "an input's span covers exactly its own tokens" do
    check all(source <- ascii_soup()) do
      {inputs, _comments, _diagnostics} = Splitter.inputs(source)

      for %Input{tokens: [{_c, first, _l} | _rest] = tokens} = input <- inputs do
        {_category, last, length} = List.last(tokens)

        assert input.offset == first
        assert input.offset + input.length == last + length
        assert input.offset + input.length <= byte_size(source)
      end
    end
  end

  property "inputs are disjoint and in reading order" do
    check all(source <- ascii_soup()) do
      {inputs, _comments, _diagnostics} = Splitter.inputs(source)

      Enum.reduce(inputs, 0, fn input, position ->
        assert input.offset >= position, "inputs overlap at #{input.offset}"
        input.offset + input.length
      end)
    end
  end

  property "a language is assigned exactly when no tier-2 diagnostic is raised" do
    check all(source <- ascii_soup()) do
      {inputs, _comments, _diagnostics} = Splitter.inputs(source)

      for input <- inputs do
        tier_two = Enum.filter(input.diagnostics, &String.starts_with?(&1.code, "TPTP02"))
        recognised? = input.language != :unknown

        assert recognised? == (tier_two == []),
               "language #{input.language} with #{length(tier_two)} tier-2 diagnostics"
      end
    end
  end

  property "streaming agrees with the eager path" do
    check all(source <- ascii_soup()) do
      {eager, _comments, _diagnostics} = Splitter.inputs(source)

      assert source |> Splitter.stream_inputs() |> Enum.to_list() == eager
    end
  end

  defp ascii_soup do
    gen all(parts <- list_of(fragment(), max_length: 30)) do
      IO.iodata_to_binary(parts)
    end
  end

  defp fragment do
    one_of([
      constant("fof(a,axiom,p)."),
      constant("fof(fof,axiom,p)."),
      constant("fof(a,file,p)."),
      constant("fof(a,axiom,p,inference(r,[],[b]))."),
      constant("fof(a,axiom,p,file('x.p',y))."),
      constant("thf(t,type,f: $i > $o)."),
      constant("thf(t,axiom,!! @ p)."),
      constant("tff(a,axiom,$let(b: $i, b := c, p(b)))."),
      constant("include('Axioms/SET007+0.ax')."),
      constant("wibble(a,axiom,p)."),
      constant("$fof(a,axiom,p)."),
      constant("% a comment\n"),
      constant("/* block */"),
      constant("'quoted'"),
      constant("[.]"),
      constant("<.>"),
      constant("."),
      constant("("),
      constant(")"),
      constant("'"),
      constant("/*"),
      string(@printable, max_length: 12)
    ])
  end
end
