defmodule Tptp.ParserCorpusTest do
  @moduledoc """
  Gate 3: the CST against the real TPTP library.

  Two questions, both of which only a corpus can answer:

    * **Does every statement parse?** The grammar is generated from the BNF, so a
      failure means either the BNF and the library disagree or our translation of
      it does. Either is worth knowing and neither shows up in a unit test.
    * **Is every node kind reachable?** The grammar can emit a fixed alphabet of
      kinds, read here straight out of the generated `.yrl`. The test reports the
      ones the corpus never reaches rather than asserting a count, because that
      list is a fact about TPTP worth being able to read.

  Two kinds of absence are expected and are not bugs. `Tptp.Parser` folds the
  statement-level nonterminals into `Tptp.Statement` structs, so they can never
  appear inside a tree; those are subtracted here rather than left to puzzle over.
  And the library's `Problems` and `Axioms` directories hold *problems*, not
  derivations, so the whole TSTP annotation machinery — `<inference_record>`,
  `<parents>`, `<general_list>` and the rest — is exercised only by the unit tests.
  Getting those covered by a corpus needs prover output, which is a differential
  test rather than this one.

  On top of those, the span invariants from `Tptp.ParserPropertyTest` are checked
  again here against real input, which is the only place they meet deeply nested
  THF.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Node
  alias Tptp.Parser
  alias Tptp.Splitter
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include
  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: 900_000

  @consumed MapSet.new([
              :thf_annotated,
              :tff_annotated,
              :tcf_annotated,
              :fof_annotated,
              :cnf_annotated,
              :tpi_annotated,
              :annotations,
              :include,
              :include_optionals
            ])

  setup_all do
    files = Corpus.files(every: 3, max_bytes: 3_000_000)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: files, emitted: emitted_kinds()}
  end

  test "every statement in the library parses", %{files: files} do
    failures =
      files
      |> stream(&unparsable/1)
      |> Enum.reject(&(&1 == :ok))

    assert failures == []
  end

  test "every node's span is a real range of its source", %{files: files} do
    violations =
      files
      |> stream(&invariants/1)
      |> Enum.reject(&(&1 == :ok))

    assert violations == []
  end

  test "the kinds the grammar can emit are the kinds the corpus exercises", %{
    files: files,
    emitted: emitted
  } do
    observed =
      files
      |> stream(&kinds/1)
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    unreached = emitted |> MapSet.difference(observed) |> Enum.sort()
    unexpected = observed |> MapSet.difference(emitted) |> Enum.sort()

    IO.puts("\n  #{MapSet.size(observed)} of #{MapSet.size(emitted)} node kinds exercised")

    if unreached != [] do
      IO.puts("  never reached: #{Enum.join(unreached, " ")}")
    end

    assert unexpected == [], "the parser emitted kinds the grammar cannot produce"

    assert MapSet.size(observed) > 80,
           "only #{MapSet.size(observed)} kinds seen; the sample is too thin to mean anything"
  end

  defp stream(files, fun) do
    files
    |> Task.async_stream(fun,
      max_concurrency: System.schedulers_online(),
      timeout: 600_000,
      ordered: false
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp unparsable(path) do
    source = File.read!(path)

    failures =
      for input <- inputs(source),
          {:error, diagnostics} <- [Parser.statement_from_input(input, source)] do
        {Enum.map(diagnostics, & &1.code),
         binary_part(source, input.offset, min(input.length, 120))}
      end

    if failures == [], do: :ok, else: {path, Enum.take(failures, 3)}
  end

  defp invariants(path) do
    source = File.read!(path)

    violations =
      for input <- inputs(source),
          {:ok, statement, _diagnostics} <- [Parser.statement_from_input(input, source)],
          root <- roots(statement),
          violation <- violations(root, source) do
        violation
      end

    if violations == [], do: :ok, else: {path, Enum.take(violations, 3)}
  end

  defp violations(root, source) do
    Node.reduce(root, [], fn node, found ->
      cond do
        node.off + node.len > byte_size(source) ->
          [{:out_of_bounds, node.kind} | found]

        node.text != nil and node.text != binary_part(source, node.off, node.len) ->
          [{:text_disagrees_with_span, node.kind} | found]

        node.text != nil and node.children != [] ->
          [{:text_on_an_interior_node, node.kind} | found]

        escapes?(node) ->
          [{:child_escapes_parent, node.kind} | found]

        true ->
          found
      end
    end)
  end

  defp escapes?(%Node{children: []}), do: false

  defp escapes?(%Node{children: children} = node) do
    first = hd(children)
    last = List.last(children)

    first.off < node.off or last.off + last.len > node.off + node.len
  end

  defp kinds(path) do
    source = File.read!(path)

    for input <- inputs(source),
        {:ok, statement, _diagnostics} <- [Parser.statement_from_input(input, source)],
        root <- roots(statement),
        reduce: MapSet.new() do
      acc -> Node.reduce(root, acc, &MapSet.put(&2, &1.kind))
    end
  end

  defp inputs(source) do
    {inputs, _comments, _diagnostics} = Splitter.inputs(source)
    inputs
  end

  defp roots(%Annotated{} = statement) do
    [statement.name, statement.role, statement.formula] ++
      List.wrap(statement.source) ++ List.wrap(statement.info)
  end

  defp roots(%Include{} = statement) do
    [statement.file_name] ++ List.wrap(statement.selection) ++ List.wrap(statement.space_name)
  end

  defp emitted_kinds do
    grammar = File.read!("src/tptp_parser.yrl")

    categories = MapSet.new(Tptp.Token.categories(), &Atom.to_string/1)

    named =
      ~r/\{'\$(?:node|leaf)', '([\w']+)'/
      |> Regex.scan(grammar, capture: :all_but_first)
      |> Enum.map(&hd/1)

    spliced_terminals =
      ~r/^'[\w']+' -> '(\w+)' : '\$1'\.$/m
      |> Regex.scan(grammar, capture: :all_but_first)
      |> Enum.map(&hd/1)
      |> Enum.filter(&MapSet.member?(categories, &1))

    (named ++ spliced_terminals)
    |> Enum.reject(&String.ends_with?(&1, "_rep"))
    |> MapSet.new(&String.to_existing_atom/1)
    |> MapSet.difference(@consumed)
  end
end
