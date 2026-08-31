defmodule Tptp.SplitterTest do
  use ExUnit.Case, async: true

  doctest Tptp.Input
  doctest Tptp.Splitter

  alias Tptp.Input
  alias Tptp.Splitter

  defp languages(source) do
    {inputs, _comments, _diagnostics} = Splitter.inputs(source)
    Enum.map(inputs, & &1.language)
  end

  defp categories(source) do
    {[input], _comments, _diagnostics} = Splitter.inputs(source)
    Enum.map(input.tokens, &elem(&1, 0))
  end

  defp codes(source) do
    {_inputs, _comments, diagnostics} = Splitter.inputs(source)
    Enum.map(diagnostics, & &1.code)
  end

  describe "splitting" do
    test "an empty source has no inputs" do
      assert Splitter.inputs("") == {[], [], []}
    end

    test "a source of only white space and comments has no inputs" do
      {inputs, comments, diagnostics} =
        Splitter.inputs("  \n% just a comment\n/* and one more */\n")

      assert inputs == []
      assert length(comments) == 2
      assert diagnostics == []
    end

    test "consecutive statements are separated at the terminating dot" do
      assert languages("fof(a,axiom,p). cnf(b,axiom,q). thf(c,type,f: $i).") == [:fof, :cnf, :thf]
    end

    test "every language keyword is recognised" do
      source = """
      thf(a, type, f: $i).
      tff(b, axiom, p).
      tcf(c, axiom, p).
      fof(d, axiom, p).
      cnf(e, axiom, p).
      tpi(f, axiom, p).
      include('g.ax').
      """

      assert languages(source) == [:thf, :tff, :tcf, :fof, :cnf, :tpi, :include]
    end

    test "a dot inside a quoted atom does not end a statement" do
      assert languages("fof('a.b', axiom, p). fof(c, axiom, q).") == [:fof, :fof]
    end

    test "a dot inside a number does not end a statement" do
      assert languages("tff(a, axiom, $less(1.5, 2.0)). fof(b, axiom, q).") == [:tff, :fof]
    end

    test "a dot inside a comment does not end a statement" do
      assert languages("% ends with a dot.\nfof(a, axiom, p).") == [:fof]
    end

    test "the dot of a short connective does not end a statement" do
      assert languages("tff(a, axiom, [.] p). fof(b, axiom, q).") == [:tff, :fof]
    end
  end

  describe "spans" do
    test "an input covers its first token through its terminating dot" do
      source = "  fof(a,axiom,p).  "
      {[input], _comments, _diagnostics} = Splitter.inputs(source)

      assert input.offset == 2
      assert input.length == 15
      assert Input.text(input, source) == "fof(a,axiom,p)."
    end

    test "leading comments are not part of the input" do
      source = "% a comment\nfof(a,axiom,p)."
      {[input], [comment], _diagnostics} = Splitter.inputs(source)

      assert Input.text(input, source) == "fof(a,axiom,p)."
      assert {0, 11, :line, :plain} = comment
    end

    test "span/2 stamps the file id" do
      {[input], _comments, _diagnostics} = Splitter.inputs("fof(a,axiom,p).", 7)

      assert Input.span(input, 7) == Tptp.Span.new(7, 0, 15)
    end
  end

  describe "language keyword promotion" do
    test "token zero becomes a keyword" do
      assert [:kw_fof | _rest] = categories("fof(a,axiom,p).")
    end

    test "a formula named after its own language keeps the word" do
      assert categories("fof(fof,axiom,p).") ==
               [:kw_fof, :lparen, :lower_word, :comma, :lower_word, :comma, :lower_word, :rparen] ++
                 [:dot]
    end

    test "an unknown prefix is reported and the input is passed on unparsed" do
      assert codes("wibble(a,axiom,p).") == ["TPTP0201"]
      assert languages("wibble(a,axiom,p).") == [:unknown]
    end

    test "a prefix that is not a word at all is reported separately" do
      assert codes("$fof(a,axiom,p).") == ["TPTP0202"]
      assert codes("(a).") == ["TPTP0202"]
    end

    test "a lone dot is an empty statement" do
      assert codes(".") == ["TPTP0203"]
      assert languages(".") == [:unknown]
    end

    test "an unrecognised prefix does not stop the statements around it" do
      assert languages("fof(a,axiom,p). wibble(b). cnf(c,axiom,q).") == [:fof, :unknown, :cnf]
    end
  end

  describe "source keyword promotion" do
    test "inference, introduced and file are promoted before a paren" do
      assert categories("fof(a,axiom,p,inference(r,[],[])).") ==
               [:kw_fof, :lparen, :lower_word, :comma, :lower_word, :comma, :lower_word, :comma] ++
                 [:kw_inference, :lparen, :lower_word, :comma, :lbracket, :rbracket, :comma] ++
                 [:lbracket, :rbracket, :rparen, :rparen, :dot]

      assert :kw_introduced in categories("fof(a,axiom,p,introduced(definition,[],[])).")
      assert :kw_file in categories("fof(a,axiom,p,file('x.p',y)).")
    end

    test "they stay lower words anywhere else" do
      refute :kw_file in categories("fof(a,file,p).")
      refute :kw_inference in categories("fof(inference,axiom,p).")
      refute :kw_introduced in categories("fof(a,axiom,introduced).")
    end

    test "a nested occurrence is promoted too" do
      categories = categories("fof(a,axiom,p,inference(r,[],[inference(s,[],[])])).")

      assert Enum.count(categories, &(&1 == :kw_inference)) == 2
    end

    test "a word that merely starts with a keyword is not promoted" do
      refute :kw_file in categories("fof(a,axiom,filename(x)).")
      refute :kw_inference in categories("fof(a,axiom,inferences(x)).")
    end
  end

  describe "dollar keyword promotion" do
    test "the six dollar keywords are promoted before a paren" do
      assert :dw_let in categories("tff(a,axiom,$let(b: $i, b := c, p(b))).")
      assert :dw_thf in categories("fof(a,axiom,p,unknown,[$thf(q)]).")
      assert :dw_fot in categories("fof(a,axiom,p,unknown,[$fot(q)]).")
    end

    test "an ordinary dollar word is left alone" do
      assert :dollar_word in categories("thf(a,type,f: $i > $o).")
      refute :dw_let in categories("thf(a,type,f: $i > $o).")
    end

    test "a dollar keyword not applied to anything stays a dollar word" do
      refute :dw_fof in categories("fof(a,axiom,p,unknown,[$fof]).")
      assert :dollar_word in categories("fof(a,axiom,p,unknown,[$fof]).")
    end
  end

  describe "resumable splitting" do
    test "next_input/3 reports where to resume" do
      source = "fof(a,axiom,p). fof(b,axiom,q)."

      assert {:input, first, 15, []} = Splitter.next_input(source, 0)
      assert {:input, second, 31, []} = Splitter.next_input(source, 15)
      assert {:eof, 31, [], []} = Splitter.next_input(source, 31)

      assert Input.text(first, source) == "fof(a,axiom,p)."
      assert Input.text(second, source) == "fof(b,axiom,q)."
    end

    test "streaming agrees with the eager path" do
      source = "fof(a,axiom,p). wibble(b). . cnf(c,axiom,q)."
      {eager, _comments, _diagnostics} = Splitter.inputs(source)

      assert source |> Splitter.stream_inputs() |> Enum.to_list() == eager
    end

    test "streaming is lazy" do
      source = String.duplicate("fof(a,axiom,p).\n", 10_000)

      assert source
             |> Splitter.stream_inputs()
             |> Stream.map(& &1.language)
             |> Enum.take(3) == [:fof, :fof, :fof]
    end

    test "an input carries the same diagnostics the eager path reports" do
      source = "wibble(a)."
      {[input], _comments, diagnostics} = Splitter.inputs(source)

      assert input.diagnostics == diagnostics
      assert [%Tptp.Diagnostic{code: "TPTP0201"}] = input.diagnostics
    end
  end

  describe "regression fixtures" do
    @fixtures Path.wildcard("test/fixtures/regression/*.p")

    for path <- @fixtures do
      @path path
      test "#{Path.basename(path)} splits without raising" do
        source = File.read!(@path)

        assert {inputs, _comments, _diagnostics} = Splitter.inputs(source)
        assert Enum.all?(inputs, &match?(%Input{}, &1))
      end
    end

    test "the fixtures were found at all" do
      assert length(@fixtures) >= 9
    end

    test "broken.p reports one diagnostic per malformed statement and recovers between them" do
      source = File.read!("test/fixtures/regression/broken.p")
      {inputs, _comments, diagnostics} = Splitter.inputs(source)

      assert Enum.map(diagnostics, & &1.code) ==
               ~w(TPTP0201 TPTP0202 TPTP0203 TPTP0101 TPTP0105)

      assert List.first(inputs).language == :fof
      assert List.last(inputs).language == :fof
      assert Input.text(List.last(inputs), source) == "fof(fine_again, axiom, r)."
    end

    test "empty.p yields nothing at all" do
      assert Splitter.inputs(File.read!("test/fixtures/regression/empty.p")) == {[], [], []}
    end

    test "cascade.p swallows statements after an unclosed bracket, then recovers" do
      source = File.read!("test/fixtures/regression/cascade.p")
      {inputs, _comments, diagnostics} = Splitter.inputs(source)

      assert Enum.map(diagnostics, & &1.code) == ["TPTP0102"]
      assert length(inputs) == 3

      assert inputs |> Enum.at(1) |> Input.text(source) =~ "swallowed_two"
      assert inputs |> List.last() |> Input.text(source) == "fof(after, axiom, s)."
    end

    test "unclosed_bracket.p blames the bracket, not the missing dot" do
      source = File.read!("test/fixtures/regression/unclosed_bracket.p")
      {_inputs, _comments, [diagnostic]} = Splitter.inputs(source)

      assert diagnostic.code == "TPTP0106"
      assert diagnostic.hint =~ "never closed"
    end
  end

  describe "include statements" do
    test "include?/1 answers without parsing" do
      {inputs, _comments, _diagnostics} =
        Splitter.inputs("fof(a,axiom,p). include('b.ax'). include('c.ax',[d]).")

      assert Enum.map(inputs, &Input.include?/1) == [false, true, true]
    end

    test "a file can be filtered to its includes while streaming" do
      source = String.duplicate("fof(a,axiom,p).\n", 100) <> "include('x.ax').\n"

      assert source
             |> Splitter.stream_inputs()
             |> Stream.filter(&Input.include?/1)
             |> Enum.count() == 1
    end
  end
end
