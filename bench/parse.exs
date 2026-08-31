defmodule Tptp.Bench do
  @moduledoc """
  The benchmark ladder: throughput *and* allocation, at five sizes.

      mix run bench/parse.exs
      mix run bench/parse.exs --only lexer
      mix run bench/parse.exs --skip-huge

  ## Why memory is measured beside time

  This library's design is mostly a set of allocation decisions — tokens as 3-tuples
  carrying no binary, leaf text as sub-binaries of one retained source, a statement
  stream that is never materialised. A throughput number alone would report all of
  those as fine right up until one of them regressed and the machine still had
  enough RAM to hide it. So each rung reports bytes allocated per run alongside the
  time, measured as a `:erlang.memory(:total)` delta around a forced collection.

  ## The rungs

  | Rung | File | Size |
  |---|---|---|
  | `1k` | `Problems/SYN/SYN989^2.p` | 1.3 KB |
  | `100k` | `Problems/ALG/ALG015^7.p` | 98 KB |
  | `1m` | `Problems/NUM/NUM924^4.p` | ~1 MB |
  | `4m` | `Problems/ITP/ITP286^3.p` | 4.5 MB |
  | `455m` | `Axioms/CSR002+5.ax` | 455 MB, streaming only |

  The last rung is the gate, not a speed contest. It is run only through
  `Tptp.stream_string!/1`, and what it asserts is that the heap stays a small
  multiple of one statement rather than growing with the file — the whole reason the
  lexer is resumable. `from_string/2` on that rung would need several gigabytes and
  is deliberately not attempted.

  Its baseline is taken *after* the source binary is read, so the 455 MB is excluded
  on purpose: the question is not whether a 455 MB file costs 455 MB — it must — but
  whether the token stream is materialised alongside it. As 3-tuples those 75 million
  tokens would be roughly 2.4 GB, so a number in the low megabytes is the whole
  design being confirmed and anything near a gigabyte is it being lost.

  Sizes are found by pattern, not hard-coded, so a corpus at a different version
  still produces a ladder; a rung whose file is missing is skipped and named.
  """

  @rungs [
    {"1k", "Problems/SYN/SYN989^2.p"},
    {"100k", "Problems/ALG/ALG015^7.p"},
    {"1m", "Problems/NUM/NUM924^4.p"},
    {"4m", "Problems/ITP/ITP286^3.p"}
  ]

  @huge "Axioms/CSR002+5.ax"

  def run(argv) do
    {options, _rest} =
      OptionParser.parse!(argv, strict: [only: :string, skip_huge: :boolean, quick: :boolean])

    root = root!()
    rungs = present(root, @rungs)

    if rungs == [] do
      abort("no ladder files found under #{root}; set $TPTP_ROOT to a TPTP library")
    end

    report_sizes(rungs)
    ladder(rungs, options)

    if options[:skip_huge] != true, do: huge(root, options)
  end

  defp root! do
    root = System.get_env("TPTP_ROOT") || System.get_env("TPTP") || "/opt/TPTP"

    if File.dir?(root), do: root, else: abort("no TPTP library at #{root}; set $TPTP_ROOT")
  end

  defp present(root, rungs) do
    for {name, relative} <- rungs,
        path = Path.join(root, relative),
        File.regular?(path),
        do: {name, path, File.stat!(path).size}
  end

  defp report_sizes(rungs) do
    IO.puts("\nladder:")

    Enum.each(rungs, fn {name, path, size} ->
      IO.puts("  #{String.pad_trailing(name, 6)} #{megabytes(size)}  #{Path.basename(path)}")
    end)

    IO.puts("")
  end

  defp ladder(rungs, options) do
    sources = Map.new(rungs, fn {name, path, _size} -> {name, File.read!(path)} end)
    stages = stages(options[:only])

    for {stage, fun} <- stages do
      IO.puts("\n#{String.duplicate("=", 72)}\n#{stage}\n#{String.duplicate("=", 72)}")

      inputs =
        Map.new(rungs, fn {name, _path, size} -> {"#{name} (#{megabytes(size)})", name} end)

      Benchee.run(
        %{stage => fn name -> fun.(Map.fetch!(sources, name)) end},
        inputs: inputs,
        time: if(options[:quick], do: 1, else: 5),
        warmup: if(options[:quick], do: 0.5, else: 2),
        memory_time: if(options[:quick], do: 0.5, else: 2),
        print: [fast_warning: false]
      )
    end
  end

  defp stages(nil), do: all_stages()

  defp stages(only) do
    wanted = String.split(only, ",", trim: true)
    chosen = Enum.filter(all_stages(), fn {stage, _fun} -> stage in wanted end)

    if chosen == [] do
      abort("no such stage: #{only}. One of: #{Enum.map_join(all_stages(), ", ", &elem(&1, 0))}")
    end

    chosen
  end

  defp all_stages do
    [
      {"lexer", &lex/1},
      {"splitter", &Tptp.Splitter.inputs/1},
      {"parser", &parse/1},
      {"printer", &print/1}
    ]
  end

  defp lex(source) do
    {statements, _comments, _diagnostics} = Tptp.Lexer.statements(source)

    length(statements)
  end

  defp parse(source) do
    {:ok, file, _diagnostics} = Tptp.from_string(source)

    length(file.statements)
  end

  defp print(source) do
    {:ok, file, _diagnostics} = Tptp.from_string(source)

    file |> Tptp.Printer.Canonical.to_iodata() |> IO.iodata_length()
  end

  defp huge(root, options) do
    path = Path.join(root, @huge)

    if File.regular?(path) do
      IO.puts("\n#{String.duplicate("=", 72)}")
      IO.puts("streaming gate: #{Path.basename(path)} (#{megabytes(File.stat!(path).size)})")
      IO.puts(String.duplicate("=", 72))

      stream(path, options[:quick])
    else
      IO.puts("\nstreaming gate skipped: no #{@huge} under #{root}")
    end
  end

  defp stream(path, quick) do
    limit = if quick, do: 200_000, else: 1_000_000_000
    source = File.read!(path)

    :erlang.garbage_collect()
    before = :erlang.memory(:total)
    started = System.monotonic_time(:millisecond)

    {counted, peak} =
      source
      |> Tptp.stream_string!()
      |> Stream.take(limit)
      |> Enum.reduce({0, before}, &tally/2)

    elapsed = System.monotonic_time(:millisecond) - started
    :erlang.garbage_collect()
    settled = :erlang.memory(:total) - before

    IO.puts("  statements  #{counted}")
    IO.puts("  elapsed     #{Float.round(elapsed / 1000, 1)} s")
    IO.puts("  peak heap above the loaded file    #{megabytes(peak - before)}")
    IO.puts("  settled heap above the loaded file #{megabytes(settled)}")
    IO.puts("\n  The gate is those two lines: both must stay a small multiple of one")
    IO.puts("  statement, however long the file is. The baseline is taken after the")
    IO.puts("  source binary is loaded, so the 455 MB itself is excluded on purpose —")
    IO.puts("  what is being measured is whether the token stream is materialised.")
  end

  defp tally(statement, {count, high}) do
    _touched = touch(statement)
    sampled = if rem(count, 100_000) == 0, do: max(high, :erlang.memory(:total)), else: high

    {count + 1, sampled}
  end

  defp touch({:ok, statement, _diagnostics}), do: statement
  defp touch({:error, _diagnostics}), do: nil

  defp megabytes(bytes) when bytes < 0, do: "-" <> megabytes(-bytes)

  defp megabytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp megabytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp megabytes(bytes), do: "#{bytes} B"

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Tptp.Bench.run(System.argv())
