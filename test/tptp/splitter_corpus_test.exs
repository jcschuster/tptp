defmodule Tptp.SplitterCorpusTest do
  @moduledoc """
  Gate 2: the splitter against the real TPTP library.

  Four properties, over every file the corpus offers:

    * **Silence.** No conforming library file produces a tier-2 diagnostic. A
      statement whose first token is not a language keyword is either a corpus file
      we cannot read or a bug here, and either way we want to know.
    * **Every statement has a language.** `:unknown` never appears.
    * **The grammar accepts what the splitter produces.** This is the only real test
      of the keyword promotions: `inference`, `introduced`, `file` and the six
      `$`-keywords are promoted on a one-token lookahead, and if that lookahead is
      wrong the generated parser is what says so. It is Gate 3's job properly, but
      running it here is what makes Gate 3's rule a decision rather than a guess.
    * **Streaming agrees with the eager path**, so the 455 MB file loses nothing by
      taking the only route it can take.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Input
  alias Tptp.Splitter
  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: 900_000

  setup_all do
    files = Corpus.files(every: 3)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: files}
  end

  test "no library file produces a statement-structure diagnostic", %{files: files} do
    noisy =
      files
      |> stream(&tier_two/1)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "every statement in the library has a known language", %{files: files} do
    unknown =
      files
      |> stream(&unknown_languages/1)
      |> Enum.reject(&(&1 == :ok))

    assert unknown == []
  end

  test "every statement in the library is accepted by the generated grammar", %{files: files} do
    rejected =
      files
      |> stream(&unparsable/1)
      |> Enum.reject(&(&1 == :ok))

    assert rejected == []
  end

  test "the library exercises every language", %{files: files} do
    counts =
      files
      |> stream(fn path ->
        {inputs, _comments, _diagnostics} = Splitter.inputs(File.read!(path))
        Enum.frequencies_by(inputs, & &1.language)
      end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _key, a, b -> a + b end))

    assert counts |> Map.values() |> Enum.sum() > 100_000
    assert Map.has_key?(counts, :include)

    for language <- [:thf, :tff, :fof, :cnf] do
      assert Map.get(counts, language, 0) > 0, "the corpus sample contains no #{language}"
    end
  end

  test "streaming a file agrees with splitting it eagerly", %{files: files} do
    disagreed =
      files
      |> Enum.take_every(7)
      |> stream(fn path ->
        source = File.read!(path)
        {eager, _comments, _diagnostics} = Splitter.inputs(source)

        if source |> Splitter.stream_inputs() |> Enum.to_list() == eager do
          :ok
        else
          {path, :disagreement}
        end
      end)
      |> Enum.reject(&(&1 == :ok))

    assert disagreed == []
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

  defp tier_two(path) do
    source = File.read!(path)
    {_inputs, _comments, diagnostics} = Splitter.inputs(source)

    case Enum.filter(diagnostics, &String.starts_with?(&1.code, "TPTP02")) do
      [] ->
        :ok

      found ->
        index = Tptp.Span.line_index(source)
        {path, Enum.map(found, &Tptp.Diagnostic.format(&1, index))}
    end
  end

  defp unknown_languages(path) do
    source = File.read!(path)
    {inputs, _comments, _diagnostics} = Splitter.inputs(source)

    case Enum.filter(inputs, &(&1.language == :unknown)) do
      [] -> :ok
      found -> {path, Enum.map(found, &excerpt(&1, source))}
    end
  end

  defp unparsable(path) do
    source = File.read!(path)
    {inputs, _comments, _diagnostics} = Splitter.inputs(source)

    failures =
      for input <- inputs,
          {:error, {offset, _module, message}} <- [:tptp_parser.parse(input.tokens)] do
        {offset, IO.iodata_to_binary(:tptp_parser.format_error(message)), excerpt(input, source)}
      end

    if failures == [], do: :ok, else: {path, Enum.take(failures, 3)}
  end

  defp excerpt(%Input{} = input, source) do
    binary_part(source, input.offset, min(input.length, 120))
  end
end
