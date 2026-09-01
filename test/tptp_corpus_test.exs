defmodule TptpCorpusTest do
  @moduledoc """
  Gate 4: the public API against the real TPTP library.

  The one that matters is the last: the largest file in the library is 455 MB and
  about 75 million tokens, which as three-tuples would be some 2.4 GB. Every design
  decision behind the lexer, the splitter and the streaming API exists to make that
  file readable in bounded memory, and this is where the claim is checked rather
  than asserted.

  The measurement deliberately loads the file *before* taking a baseline. Holding
  the whole file as one refc binary is the design — it is what every leaf's `text`
  points into, and it costs one copy — so counting it would measure the trade
  rather than test it. What must stay flat is everything else.

  ## How much of the library this reads

  Each sweep below declares how far it thins the library for a pull request, where
  the run has to finish. `$TPTP_CORPUS_FULL=1` overrides every one of them to read
  the library entire, and the nightly workflow sets it. `mix tptp.corpus` writes
  the same sweep down as a committed report, which is where the number lives.

  Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: false

  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: 900_000

  setup_all do
    if Corpus.root() == nil do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    :ok
  end

  test "every library file reads with no error-severity diagnostic" do
    noisy =
      Corpus.files(every: 5)
      |> Task.async_stream(
        fn path ->
          case Tptp.from_file(path) do
            {:ok, file, _diagnostics} ->
              if Tptp.File.any_errors?(file),
                do: {path, Tptp.File.format_diagnostics(file)},
                else: :ok

            {:error, diagnostics} ->
              {path, Enum.map(diagnostics, & &1.code)}
          end
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 600_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.reject(&(&1 == :ok))

    assert noisy == []
  end

  test "the files this parser refuses still refuse to parse" do
    for {name, why} <- Corpus.known_failures() do
      [path] = Path.wildcard(Path.join([Corpus.root(), "**", name]))
      {:ok, file, _diagnostics} = Tptp.from_file(path)

      assert Tptp.File.any_errors?(file),
             "#{name} parses now. Drop it from known_failures/0 — it was excluded because it #{why}"
    end
  end

  test "streaming and reading eagerly agree, statement for statement" do
    disagreed =
      Corpus.files(every: 37, max_bytes: 1_000_000)
      |> Task.async_stream(
        fn path ->
          source = File.read!(path)
          {:ok, file, _diagnostics} = Tptp.from_string(source)

          streamed =
            source
            |> Tptp.stream_string!()
            |> Enum.flat_map(fn
              {:ok, statement, _diagnostics} -> [statement]
              {:error, _diagnostics} -> []
            end)

          if streamed == file.statements, do: :ok, else: {path, :disagreement}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 600_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.reject(&(&1 == :ok))

    assert disagreed == []
  end

  test "the largest file in the library streams in bounded memory" do
    path = largest()
    source = File.read!(path)
    megabytes = byte_size(source) / 1_048_576

    :erlang.garbage_collect()
    before = :erlang.memory(:total)

    {statements, errors} =
      source
      |> Tptp.stream_string!()
      |> Enum.reduce({0, 0}, fn
        {:ok, statement, _diagnostics}, {ok, bad} ->
          _touched = statement.name.text
          {ok + 1, bad}

        {:error, _diagnostics}, {ok, bad} ->
          {ok, bad + 1}
      end)

    :erlang.garbage_collect()
    grew = (:erlang.memory(:total) - before) / 1_048_576

    IO.puts(
      "\n  #{Path.basename(path)}: #{Float.round(megabytes, 1)} MB, " <>
        "#{statements} statements, #{Float.round(grew, 2)} MB above the loaded file"
    )

    assert errors == 0
    assert statements > 0

    assert grew < max(8, megabytes / 20),
           "streaming grew the heap by #{Float.round(grew, 2)} MB; statements are accumulating"
  end

  defp largest do
    Corpus.files(max_bytes: 1_000_000_000)
    |> Enum.max_by(&File.stat!(&1).size)
  end
end
