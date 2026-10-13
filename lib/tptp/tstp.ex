defmodule Tptp.Tstp do
  @moduledoc """
  Reads a TSTP solution file, or a SystemOnTPTP `X2TPTP` reply, which has the same
  shape.

      iex> {:ok, solution, []} = Tptp.Tstp.from_file("test/fixtures/tstp/E---3.5.1.THM-CRf.s")
      iex> {solution.result, solution.output, length(solution.solution.statements)}
      {:theorem, :cnf_refutation, 54}

  ## The shape

  A solution file is ruled into regions by lines of dashes:

      %------------------------------------------------------------------   rule
      % File     : E---3.5.1                                               header
      % Problem  : PUZ001+1 : TPTP v9.3.1. Released v2.0.0.
      % Result   : Theorem 0.12s 0.45s
      % SZS Type : Refutation
      %            Derivation depth      :    8                            continuation
      %------------------------------------------------------------------   rule
      fof(pel55_4, axiom, …).                                              solution
      cnf(c_0_53, plain, ($false), …).
      %------------------------------------------------------------------   rule
      %----ORIGINAL SYSTEM OUTPUT                                          marker
      % 0.12/0.45  % SZS status Theorem                                    original
      %------------------------------------------------------------------   rule

  A header line is `%`, one space, a key, ` : ` and a value; a line whose `%` is
  followed by two or more spaces continues the previous value. Only the first colon
  after the key divides the line, so `Problem` keeps `PUZ001+1 : TPTP v9.3.1` whole.

  ## What this does not do

  The derivation is handed to `Tptp.from_string/2` and nothing else is done with
  it; `Tptp.Derivation` is what reads it as a graph. The archived system output is
  handed back as text with its `% ` removed, for `Tptp.Szs.status/1` and
  `Tptp.Szs.blocks/2` to read — which is also why the two are kept apart. In an
  archived file the proof block under ORIGINAL SYSTEM OUTPUT reads

      % SZS output start CNFRefutation
      % See solution above

  with the derivation lifted out into the solution region and never closed, so the
  block is not a block any more and `Tptp.Szs.blocks/2` drops it. The derivation is
  `solution`; `original` is everything the system said around it.

  Writing TSTP files is not in scope: a solution file is an archive of what a
  system printed, and this library has nothing of its own to put in one.

  ## Anything else

  `{:error, :not_tstp}` is the answer for input that is not a solution file — a
  raw prover log, a problem file, an empty string, an HTML error page. The test is
  a rule at the top of the input and a `File` key in the header; both are written
  by the TSTP's own tooling, and neither occurs by accident.
  """

  alias Tptp.Diagnostic
  alias Tptp.Span
  alias Tptp.Szs
  alias Tptp.Szs.Ontology
  alias Tptp.Tstp.Solution

  @unreadable "TPTP0001"

  # Horizontal white space is `[ \t]`, never `\s`, which crosses line ends.
  @rule ~r/^%-{4,}[ \t]*\r?$/m
  @key ~r/^%[ \t](\S(?:[^:\r\n]*?\S)?)[ \t]*:[ \t]?([^\r\n]*?)[ \t]*\r?$/
  @continuation ~r/^%[ \t]{2,}([^\r\n]*?)[ \t]*\r?$/
  @marker ~r/^%----ORIGINAL SYSTEM OUTPUT[ \t]*\r?$/

  @doc """
  Reads a solution from a binary.

  The options are `Tptp.from_string/2`'s and are passed to it for the solution
  region. The diagnostics returned are that parse's, with their spans shifted so
  that they index the input rather than the region — the diagnostics on
  `solution.solution` are unshifted, since that file is the region.

      iex> source = "%----\\n% File     : Otter\\n% Result   : Unsatisfiable 0.1s\\n%----\\ncnf(c,plain,$false).\\n"
      iex> {:ok, solution, []} = Tptp.Tstp.from_string(source)
      iex> {solution.result, solution.keys, length(solution.solution.statements)}
      {:unsatisfiable, ["File", "Result"], 1}

      iex> Tptp.Tstp.from_string("% SZS status Theorem for X\\n")
      {:error, :not_tstp}
  """
  @spec from_string(binary(), [Tptp.option()]) ::
          {:ok, Solution.t(), [Diagnostic.t()]} | {:error, :not_tstp}
  def from_string(input, options \\ []) when is_binary(input) and is_list(options) do
    with [first | rest] <- rules(input),
         true <- nothing_before?(input, first),
         {header, keys} = read_header(input, region(input, first, rest)),
         {:ok, _system} <- Map.fetch(header, "File") do
      build(input, header, keys, rest, options)
    else
      _otherwise -> {:error, :not_tstp}
    end
  end

  @doc """
  Reads a solution from a file on disk.

  Fails with a diagnostic list when the file cannot be read, as
  `Tptp.from_file/2` does, and with `{:error, :not_tstp}` when it can be read and
  is not a solution file.

      iex> {:ok, solution, []} = Tptp.Tstp.from_file("test/fixtures/tstp/e_cnfrefutation_x2tptp.txt")
      iex> {solution.result, solution.output}
      {:theorem, :cnf_refutation}

      iex> Tptp.Tstp.from_file("test/fixtures/tstp/e_saturation_raw.txt")
      {:error, :not_tstp}
  """
  @spec from_file(Path.t(), [Tptp.option()]) ::
          {:ok, Solution.t(), [Diagnostic.t()]} | {:error, :not_tstp} | {:error, [Diagnostic.t()]}
  def from_file(path, options \\ []) when is_list(options) do
    case File.read(path) do
      {:ok, input} ->
        from_string(input, Keyword.put_new(options, :path, path))

      {:error, reason} ->
        {:error, [unreadable(path, reason, Keyword.get(options, :file, 0))]}
    end
  end

  @spec rules(binary()) :: [Solution.region()]
  defp rules(input) do
    @rule |> Regex.scan(input, return: :index) |> Enum.map(&hd/1)
  end

  # The first rule has to be the first thing in the input. A prover log that happens
  # to print a line of dashes halfway down is not a solution file, and reading one as
  # if it were would hand back a header made of its banner.
  @spec nothing_before?(binary(), Solution.region()) :: boolean()
  defp nothing_before?(input, {offset, _length}) do
    input |> binary_part(0, offset) |> String.trim() == ""
  end

  # The region between the end of one rule and the start of the next, or the end of
  # the input when that was the last rule.
  @spec region(binary(), Solution.region(), [Solution.region()]) :: Solution.region()
  defp region(input, {offset, length}, rest) do
    from = offset + length

    to =
      case rest do
        [{next, _length} | _tail] -> next
        [] -> byte_size(input)
      end

    {from, max(to - from, 0)}
  end

  @spec build(binary(), %{binary() => binary()}, [binary()], [Solution.region()], keyword()) ::
          {:ok, Solution.t(), [Diagnostic.t()]}
  defp build(input, header, keys, rules, options) do
    {solution_span, solution, diagnostics} = solution(input, rules, options)

    {:ok,
     %Solution{
       header: header,
       keys: keys,
       result: ontology_value(header, "Result"),
       output: ontology_value(header, "Output"),
       solution: solution,
       original: original(input, rules),
       span: %{solution: solution_span, original: original_span(input, rules)}
     }, diagnostics}
  end

  @spec solution(binary(), [Solution.region()], keyword()) ::
          {Solution.region() | nil, Tptp.File.t() | nil, [Diagnostic.t()]}
  defp solution(_input, [], _options), do: {nil, nil, []}

  defp solution(input, [second | rest], options) do
    {offset, length} = span = trimmed(input, region(input, second, rest))
    {:ok, file, diagnostics} = Tptp.from_string(binary_part(input, offset, length), options)

    case file.statements do
      [] -> {span, nil, shift(diagnostics, offset)}
      _statements -> {span, file, shift(diagnostics, offset)}
    end
  end

  # The third region is the archived output only if its first line says so. Without
  # the marker it is whatever else the file chose to put there, and not for `Tptp.Szs`.
  @spec original_span(binary(), [Solution.region()]) :: Solution.region() | nil
  defp original_span(input, [_second, third | rest]) do
    {offset, length} = trimmed(input, region(input, third, rest))

    with {at, _size} <- :binary.match(binary_part(input, offset, length), "\n"),
         true <- Regex.match?(@marker, binary_part(input, offset, at)) do
      trimmed(input, {offset + at + 1, length - at - 1})
    else
      _otherwise -> nil
    end
  end

  defp original_span(_input, _rules), do: nil

  @spec original(binary(), [Solution.region()]) :: binary() | nil
  defp original(input, rules) do
    case original_span(input, rules) do
      nil ->
        nil

      {offset, length} ->
        Regex.replace(Szs.prefix(:line_comment), binary_part(input, offset, length), "")
    end
  end

  # A region without the blank lines around it: the rules are a line apart from what
  # they delimit, and a span over the gap is a span over nothing.
  @spec trimmed(binary(), Solution.region()) :: Solution.region()
  defp trimmed(input, {offset, length}) do
    slice = binary_part(input, offset, length)
    leading = byte_size(slice) - byte_size(String.trim_leading(slice))

    {offset + leading, byte_size(String.trim(slice))}
  end

  @spec read_header(binary(), Solution.region()) :: {%{binary() => binary()}, [binary()]}
  defp read_header(input, {offset, length}) do
    {header, keys} =
      input
      |> binary_part(offset, length)
      |> String.split("\n")
      |> Enum.reduce({%{}, []}, &header_line/2)

    {header, Enum.reverse(keys)}
  end

  @spec header_line(binary(), {%{binary() => binary()}, [binary()]}) ::
          {%{binary() => binary()}, [binary()]}
  defp header_line(line, {header, keys} = so_far) do
    cond do
      match = Regex.run(@key, line) ->
        [_whole, key, value] = match
        {Map.put(header, key, value), if(key in keys, do: keys, else: [key | keys])}

      match = Regex.run(@continuation, line) ->
        [_whole, text] = match
        continue(so_far, keys, text)

      true ->
        so_far
    end
  end

  # A continuation before any key has nothing to continue, and a bare `%` line is the
  # header's own blank line.
  @spec continue({%{binary() => binary()}, [binary()]}, [binary()], binary()) ::
          {%{binary() => binary()}, [binary()]}
  defp continue(so_far, [], _text), do: so_far

  defp continue({header, keys}, [key | _rest], text) do
    {Map.update!(header, key, &join(&1, text)), keys}
  end

  @spec join(binary(), binary()) :: binary()
  defp join("", text), do: text
  defp join(value, text), do: value <> "\n" <> text

  @spec ontology_value(%{binary() => binary()}, binary()) :: Ontology.t() | nil
  defp ontology_value(header, key) do
    with {:ok, value} <- Map.fetch(header, key),
         [word | _rest] <- String.split(value),
         {:ok, found} <- Ontology.from_string(word) do
      found
    else
      _otherwise -> nil
    end
  end

  # The solution is parsed from a sub-binary, so its diagnostics index the region.
  # A caller holding the whole file wants them to index that instead.
  @spec shift([Diagnostic.t()], non_neg_integer()) :: [Diagnostic.t()]
  defp shift(diagnostics, 0), do: diagnostics

  defp shift(diagnostics, offset) do
    Enum.map(diagnostics, fn %Diagnostic{} = diagnostic ->
      %{
        diagnostic
        | span: move(diagnostic.span, offset),
          related:
            Enum.map(diagnostic.related, fn {span, label} -> {move(span, offset), label} end)
      }
    end)
  end

  @spec move(Span.t(), non_neg_integer()) :: Span.t()
  defp move(%Span{} = span, offset), do: %{span | offset: span.offset + offset}

  @spec unreadable(Path.t(), File.posix(), Span.file_id()) :: Diagnostic.t()
  defp unreadable(path, reason, id) do
    Diagnostic.new(
      @unreadable,
      :error,
      Span.new(id, 0, 0),
      "cannot read #{path}: #{:file.format_error(reason)}"
    )
  end
end
