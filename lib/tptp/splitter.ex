defmodule Tptp.Splitter do
  @moduledoc """
  Turns a byte stream into `Tptp.Input` records: one statement, one language, one
  token list whose keywords have been resolved.

  ## What this stage is for

  `Tptp.Lexer` already ends a statement at a bracket-depth-zero `.`, because it has
  to track depth anyway to know which dots those are. What is left, and what this
  module owns, is everything about a statement that only its *position* can settle:

    * **Keyword resolution.** The lexer emits `lower_word` for `fof`, `inference`
      and `file`, because `fof(fof, axiom, p).` and `fof(a, file, p).` are both
      legal TPTP and both would break if a keyword reading were forced by spelling
      alone. Only position disambiguates, and only this module sees position.
    * **The language.** Token zero names it, so it is knowable without parsing.
    * **Tier-2 diagnostics.** An input whose first token is not a language keyword
      is reported here, with a message naming what was found and what was expected,
      and is passed on unparsed rather than dragged through the grammar for a worse
      error.

  Splitting on tokens rather than bytes is the whole point: `'foo.bar'`, `1.5`,
  `% a comment.` and `<.>` all contain a `.` that does not end a statement, and a
  byte-level split gets every one of them wrong.

  ## The three promotions

  A `lower_word` at position zero becomes `kw_thf`, `kw_tff`, `kw_tcf`, `kw_fof`,
  `kw_cnf`, `kw_tpi` or `kw_include` on spelling alone. There is no ambiguity to
  guard against: position zero of a `<TPTP_input>` is always one of those seven.

  `inference`, `introduced` and `file` become `kw_inference`, `kw_introduced` and
  `kw_file` **only when the next token is `(`**, because those are the only shapes
  the grammar admits — `inference_record`, `internal_source` and `file_source` all
  apply the keyword immediately. Anywhere else the word stays a `lower_word`, and
  `atomic_word` in the grammar accepts the promoted categories anyway, so a formula
  genuinely named `inference` still parses.

  `$thf`, `$tff`, `$fof`, `$cnf`, `$fot` and `$let` become `dw_*` under the same
  `(`-follows rule, for the same reason: `<formula_data>` and `<thf_let>` always
  apply them, and everywhere else they are ordinary `<dollar_word>`s.

  ## Where recovery stops, and why it is not patched over

  A statement ends at a `.` the lexer sees at bracket depth zero, so an input that
  leaves a bracket open — an unterminated quoted atom swallowing its own `)`, say —
  keeps the depth above zero, and the dots that follow are read as parts of a term
  rather than terminators. The next statements are absorbed into the broken one
  until the depth returns to zero. `test/fixtures/regression/cascade.p` pins this.

  It would be easy to resynchronise on a `.` at end of line before a line starting
  with a language keyword, and that would be wrong: it is a guess about layout, and
  a formula may legally be laid out that way. Splitting stays exact. What the
  library owes the caller instead is a diagnostic pointing at the *cause* rather
  than at the wreckage, and the first diagnostic on such an input is the
  unterminated quote, at the column where it opened.

  ## Streaming

  `stream_inputs/2` is the primitive and holds one statement at a time; `inputs/2`
  is the eager convenience over it. Each `Tptp.Input` carries its own diagnostics,
  so nothing is lost by taking the streaming path — which matters, because a 455 MB
  axiom file has no eager path.
  """

  alias Tptp.Diagnostic
  alias Tptp.Input
  alias Tptp.Lexer
  alias Tptp.Span
  alias Tptp.Token

  @unknown_language "TPTP0201"
  @not_a_language "TPTP0202"
  @empty_statement "TPTP0203"

  @statement_promotions Map.new(Token.statement_keywords(), fn {c, s} -> {s, c} end)
  @source_promotions Map.new(Token.source_keywords(), fn {c, s} -> {s, c} end)
  @dollar_promotions Map.new(Token.dollar_keywords(), fn {c, s} -> {s, c} end)

  @source_lengths @source_promotions |> Map.keys() |> Enum.map(&byte_size/1) |> Enum.uniq()
  @dollar_lengths @dollar_promotions |> Map.keys() |> Enum.map(&byte_size/1) |> Enum.uniq()

  @spellings Enum.map_join(Token.statement_keywords(), ", ", fn {_c, s} -> s end)

  @typedoc """
  One call's worth of splitting.

  `:input` carries the statement and the offset to resume from; `:eof` carries the
  diagnostics raised after the last statement, which have no input to belong to.
  Both carry the comments seen along the way, which are a side channel in both
  stages and never enter the token stream.
  """
  @type result ::
          {:input, Input.t(), non_neg_integer(), [Lexer.comment()]}
          | {:eof, non_neg_integer(), [Lexer.comment()], [Diagnostic.t()]}

  @doc """
  Split the next input starting at `offset`.

  `file` is stamped into any diagnostic's span; it is the id under which the caller
  registered this source, and defaults to zero for a single-file split.

      iex> {:input, input, next, []} = Tptp.Splitter.next_input("fof(a,axiom,p). fof(b,axiom,q).", 0)
      iex> {input.language, input.offset, input.length}
      {:fof, 0, 15}
      iex> next
      15
  """
  @spec next_input(binary(), non_neg_integer(), Span.file_id()) :: result()
  def next_input(source, offset, file \\ 0)
      when is_binary(source) and is_integer(offset) and offset >= 0 do
    case Lexer.next_statement(source, offset, file) do
      {:statement, tokens, next, comments, diagnostics} ->
        {:input, build(tokens, source, file, diagnostics), next, comments}

      {:eof, next, comments, diagnostics} ->
        {:eof, next, comments, diagnostics}
    end
  end

  @doc """
  Every input in a source, eagerly, with its comments and diagnostics.

  The diagnostic list is the union of every input's own diagnostics and those
  raised after the last one, flattened into reading order — convenient for a
  caller holding the whole file, and redundant with `Tptp.Input.diagnostics` by
  design so that `stream_inputs/2` loses nothing.

  This holds the entire token stream in memory. Use `stream_inputs/2` for anything
  large; see `Tptp.Lexer` for why that distinction is not academic.

      iex> {inputs, _comments, []} = Tptp.Splitter.inputs("fof(a,axiom,p). include('b.ax').")
      iex> Enum.map(inputs, & &1.language)
      [:fof, :include]
  """
  @spec inputs(binary(), Span.file_id()) ::
          {[Input.t()], [Lexer.comment()], [Diagnostic.t()]}
  def inputs(source, file \\ 0) when is_binary(source) do
    collect(source, 0, file, [], [], [])
  end

  @doc """
  Every input in a source, lazily, one statement at a time.

  The stream yields `Tptp.Input` structs, each carrying its own diagnostics.
  Comments and any diagnostics raised after the last statement are not observable
  through this path; a caller that needs them wants `inputs/2` and has a file small
  enough to afford it.

      iex> "fof(a,axiom,p). cnf(b,axiom,q). thf(c,type,f: $i)."
      ...> |> Tptp.Splitter.stream_inputs()
      ...> |> Stream.map(& &1.language)
      ...> |> Enum.take(2)
      [:fof, :cnf]
  """
  @spec stream_inputs(binary(), Span.file_id()) :: Enumerable.t()
  def stream_inputs(source, file \\ 0) when is_binary(source) do
    Stream.resource(
      fn -> 0 end,
      fn offset ->
        case next_input(source, offset, file) do
          {:input, input, next, _comments} -> {[input], next}
          {:eof, _next, _comments, _diagnostics} -> {:halt, offset}
        end
      end,
      fn _offset -> :ok end
    )
  end

  @spec collect(
          binary(),
          non_neg_integer(),
          Span.file_id(),
          [Input.t()],
          [[Lexer.comment()]],
          [[Diagnostic.t()]]
        ) :: {[Input.t()], [Lexer.comment()], [Diagnostic.t()]}
  defp collect(source, offset, file, inputs, comments, diagnostics) do
    case next_input(source, offset, file) do
      {:input, input, next, new_comments} ->
        collect(source, next, file, [input | inputs], [new_comments | comments], [
          input.diagnostics | diagnostics
        ])

      {:eof, _next, new_comments, new_diagnostics} ->
        {Enum.reverse(inputs), flatten([new_comments | comments]),
         flatten([new_diagnostics | diagnostics])}
    end
  end

  defp flatten(chunks), do: chunks |> Enum.reverse() |> Enum.concat()

  @spec build([Token.t()], binary(), Span.file_id(), [Diagnostic.t()]) :: Input.t()
  defp build([{_category, offset, _length} | _rest] = tokens, source, file, diagnostics) do
    {language, promoted, extra} = resolve(tokens, source, file)

    %Input{
      language: language,
      tokens: promoted,
      offset: offset,
      length: extent(tokens) - offset,
      diagnostics: Diagnostic.sort(diagnostics ++ extra)
    }
  end

  defp extent(tokens) do
    {_category, offset, length} = List.last(tokens)
    offset + length
  end

  @spec resolve([Token.t()], binary(), Span.file_id()) ::
          {Input.language(), [Token.t()], [Diagnostic.t()]}
  defp resolve([{:dot, offset, length}], _source, file) do
    diagnostic =
      diagnose(
        @empty_statement,
        file,
        offset,
        length,
        "a statement with nothing in it",
        "a stray `.` terminates a statement that was never started"
      )

    {:unknown, [{:dot, offset, length}], [diagnostic]}
  end

  defp resolve([{:lower_word, offset, length} = first | rest], source, file) do
    word = binary_part(source, offset, length)

    case Map.get(@statement_promotions, word) do
      nil ->
        {:unknown, [first | promote(rest, source)],
         [
           diagnose(
             @unknown_language,
             file,
             offset,
             length,
             "`#{word}` does not start a TPTP statement",
             "expected one of #{@spellings}"
           )
         ]}

      category ->
        {Input.language_for(category), [{category, offset, length} | promote(rest, source)], []}
    end
  end

  defp resolve([{category, offset, length} = first | rest], source, file) do
    {:unknown, [first | promote(rest, source)],
     [
       diagnose(
         @not_a_language,
         file,
         offset,
         length,
         "a statement cannot start with #{describe(category, source, offset, length)}",
         "expected one of #{@spellings}"
       )
     ]}
  end

  defp describe(category, source, offset, length) do
    case Token.spelling(category) do
      nil -> "`#{binary_part(source, offset, length)}`"
      spelling -> "`#{spelling}`"
    end
  end

  @spec promote([Token.t()], binary()) :: [Token.t()]
  defp promote(tokens, source), do: promote(tokens, source, [])

  defp promote([], _source, acc), do: Enum.reverse(acc)

  defp promote([token | tail], source, acc) do
    promote(tail, source, [promoted(token, tail, source) | acc])
  end

  defp promoted({:lower_word, offset, length}, [{:lparen, _, _} | _rest], source)
       when length in @source_lengths do
    lookup(@source_promotions, :lower_word, offset, length, source)
  end

  defp promoted({:dollar_word, offset, length}, [{:lparen, _, _} | _rest], source)
       when length in @dollar_lengths do
    lookup(@dollar_promotions, :dollar_word, offset, length, source)
  end

  defp promoted(token, _tail, _source), do: token

  defp lookup(table, category, offset, length, source) do
    case Map.get(table, binary_part(source, offset, length)) do
      nil -> {category, offset, length}
      promoted -> {promoted, offset, length}
    end
  end

  defp diagnose(code, file, offset, length, message, hint) do
    Diagnostic.new(code, :error, Span.new(file, offset, length), message, hint: hint)
  end
end
