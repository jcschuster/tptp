defmodule Tptp.Lexer do
  @moduledoc """
  Scans TPTP bytes into tokens, one statement at a time.

  ## Why one statement at a time

  The largest file in the TPTP library is a 455 MB axiom file, roughly 75 million
  tokens. Materialised as three-tuples that is about 2.4 GB — the token stream, not
  the file, is what makes a large corpus run fall over. So the file binary is held
  whole (one refc binary, cheap) and the scanner is resumable over `(source,
  offset)`, handing back exactly one statement's tokens per call. Peak memory is
  one statement, whatever the file size.

  ## Bytes, not graphemes

  Every character class in the BNF lies in `\\40`-`\\176`, so byte matching is
  correct here and every `String` function — UTF-8 aware and grapheme-based — is
  both wrong-shaped and several times slower. This module uses byte patterns and
  `:binary` exclusively. The one place non-ASCII can appear is inside a quoted atom
  or a comment in a non-conforming file; those bytes are carried through opaquely
  rather than checked, because checking them would put a branch on every byte of
  every string for something a lint rule can do later from the token text.

  ## No binaries in the scan loop

  A token is `{category, offset, length}`. Text is recovered later with
  `binary_part/3`, so scanning allocates nothing per token beyond the tuple itself.

  ## Maximal munch

  The scan clauses for operators are generated from `Tptp.Token.operators/0`, which
  is sorted longest-spelling-first, so `<=>` is tried before `<=` before `<` as a
  property of the table rather than something a maintainer has to remember.

  Three cases the table cannot settle on its own, and each is a real bug in a
  hand-written TPTP lexer:

    * **`.` is the statement terminator, but `1.5` is one `<real>`.** Numbers are
      scanned from their leading digit and consume their own `.`, and the
      terminator clause only fires on a `.` that is not followed by a digit. `p(3).`
      works because `<decimal_fraction>` requires digits *after* the dot.
    * **A word is always scanned to its end**, never cut short at a prefix that
      happens to be a keyword. `$letter` is one `dollar_word`, not `$let` followed
      by `ter`, and `filename` is one `lower_word`, not `file` followed by `name`.
      This is what makes it safe for `Tptp.Splitter` to recognise keywords by
      whole-word lookup afterwards.
    * **`[.]`, `<.>`, `{.}` and `(.)` are single tokens.** `<.>` in particular would
      otherwise put a bare `.` at bracket depth zero and split a statement in half.

  ## It accepts what the BNF rejects, and says so

  Two shapes lex cleanly and are still not what the BNF describes, so they produce
  a token *and* a warning rather than either a silent acceptance or a refusal:

    * **An empty quoted atom.** `<single_quoted>` requires at least one `<sq_char>`
      where `<distinct_object>` allows none, so `""` is legal TPTP and `''` is not
      (`TPTP0107`).
    * **A redundant leading zero.** `<unsigned_integer>` is `0` or a digit sequence
      starting `1`-`9`, so `00`, `-007` and `01.5` are not numbers the grammar
      admits (`TPTP0110`); and `<positive_integer>`, which is what a rational's
      denominator must be, may not begin with `0` at all, so neither `1/02` nor
      `1/0` is a `<rational>` (`TPTP0111`).

  Producing the token anyway is what lets the statement go on to parse, which is
  the whole reason these are warnings. That the list is exactly two is not a claim
  anyone has to take on trust: `Tptp.Bnf.OracleTable` transcribes the `::-` and
  `:::` rules mechanically, and `Tptp.LexerOracleTest` asserts that every token this
  module emits *without complaint* satisfies its own BNF pattern.

  ## What this module does not decide

  It emits `lower_word` for `fof`, `inference` and `file`, and `dollar_word` for
  `$let` and `$thf`. Those are ordinary words until something about their position
  says otherwise, and position is `Tptp.Splitter`'s business: a statement's first
  token, and a word directly before `(`, are the only places a keyword reading is
  possible. Deciding it here would break `fof(fof, axiom, p).`, which is legal
  TPTP, and would leave keyword resolution split across two modules for no gain —
  the whole-word guarantee above is all the splitter needs.

  ## Comments are a side channel

  The BNF says comments may occur between any two tokens but do not act as white
  space. They are collected into a separate ordered list rather than the token
  stream, so the parser never sees them and the format-preserving printer can
  re-attach them by position. `%$` and `/*$` mark a defined comment and `%$$` and
  `/*$$` a system comment; both are reserved in the BNF and some tools use them, so
  the class is retained.
  """

  alias Tptp.Diagnostic
  alias Tptp.Span
  alias Tptp.Token

  @typedoc "Where a comment came from, and whether it is a pragma."
  @type comment ::
          {offset :: non_neg_integer(), length :: non_neg_integer(), :line | :block,
           :plain | :defined | :system}

  @typedoc """
  One call's worth of scanning.

  `:statement` carries the tokens up to and including a bracket-depth-zero `.`;
  `:eof` means the input was exhausted. Both carry the comments and diagnostics
  seen along the way and the offset to resume from.
  """
  @type result ::
          {:statement, [Token.t()], non_neg_integer(), [comment()], [Diagnostic.t()]}
          | {:eof, non_neg_integer(), [comment()], [Diagnostic.t()]}

  @illegal_character "TPTP0101"
  @unterminated_quote "TPTP0102"
  @unterminated_comment "TPTP0104"
  @unbalanced_bracket "TPTP0105"
  @missing_terminator "TPTP0106"
  @empty_quoted_atom "TPTP0107"
  @incomplete_back_quote "TPTP0109"
  @leading_zero "TPTP0110"
  @zero_denominator "TPTP0111"

  defguardp is_lower(c) when c >= ?a and c <= ?z
  defguardp is_upper(c) when c >= ?A and c <= ?Z
  defguardp is_digit(c) when c >= ?0 and c <= ?9
  defguardp is_alnum(c) when is_lower(c) or is_upper(c) or is_digit(c) or c == ?_
  defguardp is_space(c) when c == ?\s or c == ?\t or c == ?\n or c == ?\r or c == ?\f or c == ?\v
  defguardp is_sign(c) when c == ?- or c == ?+
  defguardp is_exponent(c) when c == ?e or c == ?E

  @doc """
  Scan the next statement starting at `offset`.

  `file` is stamped into any diagnostic's span; it is the id under which the caller
  registered this source, and defaults to zero for a single-file scan.

      iex> {:statement, tokens, next, [], []} = Tptp.Lexer.next_statement("fof(a,axiom,p).", 0)
      iex> Enum.map(tokens, &elem(&1, 0))
      [:lower_word, :lparen, :lower_word, :comma, :lower_word, :comma, :lower_word, :rparen, :dot]
      iex> next
      15
  """
  @spec next_statement(binary(), non_neg_integer(), Span.file_id()) :: result()
  def next_statement(source, offset, file \\ 0)
      when is_binary(source) and is_integer(offset) and offset >= 0 do
    source
    |> drop(offset)
    |> scan(offset, file, 0, [], [], [])
    |> without_tail()
  end

  defp without_tail({:statement, tokens, _tail, next, comments, diagnostics}) do
    {:statement, tokens, next, comments, diagnostics}
  end

  defp without_tail({:eof, _tail, next, comments, diagnostics}) do
    {:eof, next, comments, diagnostics}
  end

  @doc """
  Scan an entire source into statements, eagerly.

  A convenience over `next_statement/3` for small inputs and for tests. Anything
  large should go through the streaming path instead, for the reason in the
  moduledoc.
  """
  @spec statements(binary(), Span.file_id()) :: {[[Token.t()]], [comment()], [Diagnostic.t()]}
  def statements(source, file \\ 0) when is_binary(source) do
    collect(source, 0, file, [], [], [])
  end

  @doc """
  The bytes a token covers.

  A sub-binary, not a copy. See `Tptp.Span.text/2` for when that matters.
  """
  @spec text(Token.t(), binary()) :: binary()
  def text({_category, offset, length}, source), do: binary_part(source, offset, length)

  @doc """
  The bytes a comment covers, including its `%` or `/* */` delimiters.
  """
  @spec comment_text(comment(), binary()) :: binary()
  def comment_text({offset, length, _form, _class}, source) do
    binary_part(source, offset, length)
  end

  @spec collect(
          binary(),
          non_neg_integer(),
          Span.file_id(),
          [[Token.t()]],
          [[comment()]],
          [[Diagnostic.t()]]
        ) :: {[[Token.t()]], [comment()], [Diagnostic.t()]}
  defp collect(source, offset, file, statements, comments, diagnostics) do
    case scan(source, offset, file, 0, [], [], []) do
      {:statement, tokens, tail, next, new_comments, new_diagnostics} ->
        collect(
          tail,
          next,
          file,
          [tokens | statements],
          [new_comments | comments],
          [new_diagnostics | diagnostics]
        )

      {:eof, _tail, _next, new_comments, new_diagnostics} ->
        {Enum.reverse(statements), flatten([new_comments | comments]),
         flatten([new_diagnostics | diagnostics])}
    end
  end

  defp flatten(chunks), do: chunks |> Enum.reverse() |> Enum.concat()

  defp scan(<<>>, offset, _file, _depth, [], comments, diagnostics) do
    {:eof, "", offset, Enum.reverse(comments), Enum.reverse(diagnostics)}
  end

  defp scan(<<>>, offset, file, depth, tokens, comments, diagnostics) do
    diagnostic =
      diagnose(
        @missing_terminator,
        file,
        offset,
        0,
        "the file ends in the middle of a statement",
        unterminated_hint(depth)
      )

    finish(tokens, "", offset, comments, [diagnostic | diagnostics])
  end

  defp scan(<<c, rest::binary>>, offset, file, depth, tokens, comments, diagnostics)
       when is_space(c) do
    scan(rest, offset + 1, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<"/*", rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    block_comment(rest, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?%, rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    line_comment(rest, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?., c, _::binary>> = all, offset, _file, 0, tokens, comments, diagnostics)
       when not is_digit(c) do
    finish([{:dot, offset, 1} | tokens], drop(all, 1), offset + 1, comments, diagnostics)
  end

  defp scan(<<?.>>, offset, _file, 0, tokens, comments, diagnostics) do
    finish([{:dot, offset, 1} | tokens], "", offset + 1, comments, diagnostics)
  end

  defp scan(<<?., c, _::binary>> = all, offset, file, depth, tokens, comments, diagnostics)
       when not is_digit(c) do
    scan(
      drop(all, 1),
      offset + 1,
      file,
      depth,
      [{:dot, offset, 1} | tokens],
      comments,
      diagnostics
    )
  end

  defp scan(<<?.>>, offset, file, depth, tokens, comments, diagnostics) do
    scan("", offset + 1, file, depth, [{:dot, offset, 1} | tokens], comments, diagnostics)
  end

  defp scan(<<s, c, _::binary>> = all, offset, file, depth, tokens, comments, diagnostics)
       when is_sign(s) and is_digit(c) do
    numeral(all, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<c, _::binary>> = all, offset, file, depth, tokens, comments, diagnostics)
       when is_digit(c) do
    numeral(all, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<"$$", rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    {length, tail} = word(rest, 2)
    emit(:dollar_dollar_word, length, tail, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?$, rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    {length, tail} = word(rest, 1)
    emit(:dollar_word, length, tail, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<c, rest::binary>>, offset, file, depth, tokens, comments, diagnostics)
       when is_lower(c) do
    {length, tail} = word(rest, 1)
    emit(:lower_word, length, tail, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<c, rest::binary>>, offset, file, depth, tokens, comments, diagnostics)
       when is_upper(c) do
    {length, tail} = word(rest, 1)
    emit(:upper_word, length, tail, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?`, c, rest::binary>>, offset, file, depth, tokens, comments, diagnostics)
       when is_upper(c) do
    {length, tail} = word(rest, 2)
    emit(:back_quoted, length, tail, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?`, rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    diagnostic =
      diagnose(
        @incomplete_back_quote,
        file,
        offset,
        1,
        "a back quote must be followed by an upper word",
        "`<back_quoted> ::- <back_quote><upper_word>`"
      )

    scan(rest, offset + 1, file, depth, tokens, comments, [diagnostic | diagnostics])
  end

  defp scan(<<?', rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    quoted(rest, ?', :single_quoted, offset, file, depth, tokens, comments, diagnostics)
  end

  defp scan(<<?", rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    quoted(rest, ?", :distinct_object, offset, file, depth, tokens, comments, diagnostics)
  end

  for {category, spelling} <- Tptp.Token.operators(), category != :dot do
    size = byte_size(spelling)

    delta =
      cond do
        category in [:lparen, :lbracket, :lbrace] -> 1
        category in [:rparen, :rbracket, :rbrace] -> -1
        true -> 0
      end

    if delta == -1 do
      defp scan(
             <<unquote(spelling), rest::binary>>,
             offset,
             file,
             0,
             tokens,
             comments,
             diagnostics
           ) do
        diagnostic =
          diagnose(
            @unbalanced_bracket,
            file,
            offset,
            unquote(size),
            "closing bracket with nothing open",
            "the statement has more closing brackets than opening ones"
          )

        scan(
          rest,
          offset + unquote(size),
          file,
          0,
          [{unquote(category), offset, unquote(size)} | tokens],
          comments,
          [diagnostic | diagnostics]
        )
      end
    end

    defp scan(
           <<unquote(spelling), rest::binary>>,
           offset,
           file,
           depth,
           tokens,
           comments,
           diagnostics
         ) do
      scan(
        rest,
        offset + unquote(size),
        file,
        depth + unquote(delta),
        [{unquote(category), offset, unquote(size)} | tokens],
        comments,
        diagnostics
      )
    end
  end

  defp scan(<<_c, rest::binary>>, offset, file, depth, tokens, comments, diagnostics) do
    diagnostic =
      diagnose(
        @illegal_character,
        file,
        offset,
        1,
        "illegal character",
        "TPTP is ASCII: printable characters from space to tilde, plus white space"
      )

    scan(rest, offset + 1, file, depth, tokens, comments, [diagnostic | diagnostics])
  end

  defp finish(tokens, tail, next, comments, diagnostics) do
    {:statement, Enum.reverse(tokens), tail, next, Enum.reverse(comments),
     Enum.reverse(diagnostics)}
  end

  defp emit(category, length, tail, offset, file, depth, tokens, comments, diagnostics) do
    scan(
      tail,
      offset + length,
      file,
      depth,
      [{category, offset, length} | tokens],
      comments,
      diagnostics
    )
  end

  defp diagnose(code, file, offset, length, message, hint) do
    Diagnostic.new(code, :error, Span.new(file, offset, length), message, hint: hint)
  end

  defp unterminated_hint(0), do: "every TPTP statement ends with `.`"

  defp unterminated_hint(depth) do
    "#{depth} bracket#{if depth == 1, do: "", else: "s"} opened here are never closed, " <>
      "so the terminating `.` is still being read as part of a term"
  end

  defp word(<<c, rest::binary>>, taken) when is_alnum(c), do: word(rest, taken + 1)
  defp word(rest, taken), do: {taken, rest}

  defp numeral(all, offset, file, depth, tokens, comments, diagnostics) do
    {length, category, tail} = number(all)
    text = binary_part(all, 0, length)

    emit(
      category,
      length,
      tail,
      offset,
      file,
      depth,
      tokens,
      comments,
      malformed(text, category, offset, file) ++ diagnostics
    )
  end

  defp malformed(<<s, rest::binary>>, category, offset, file) when is_sign(s) do
    malformed(rest, category, offset + 1, file)
  end

  defp malformed(digits, category, offset, file) do
    List.wrap(padded(digits, offset, file)) ++
      List.wrap(denominator(digits, category, offset, file))
  end

  defp padded(<<?0, c, _::binary>>, offset, file) when is_digit(c) do
    Diagnostic.new(
      @leading_zero,
      :warning,
      Span.new(file, offset, 1),
      "redundant leading zero",
      hint: "`<unsigned_integer>` is `0` or a digit sequence starting `1`-`9`"
    )
  end

  defp padded(_digits, _offset, _file), do: nil

  defp denominator(digits, :rational, offset, file) do
    case :binary.split(digits, "/") do
      [whole, <<?0, _::binary>>] ->
        Diagnostic.new(
          @zero_denominator,
          :warning,
          Span.new(file, offset + byte_size(whole) + 1, 1),
          "rational denominator begins with zero",
          hint: "`<positive_integer>` may not begin with `0`, so neither may a denominator"
        )

      _otherwise ->
        nil
    end
  end

  defp denominator(_digits, _category, _offset, _file), do: nil

  defp number(<<s, rest::binary>>) when is_sign(s) do
    {length, category, tail} = unsigned(rest)
    {length + 1, category, tail}
  end

  defp number(bin), do: unsigned(bin)

  defp unsigned(bin) do
    {whole, after_whole} = digits(bin, 0)

    case after_whole do
      <<?/, c, _::binary>> when is_digit(c) ->
        <<?/, rest::binary>> = after_whole
        {denominator, tail} = digits(rest, 0)
        {whole + 1 + denominator, :rational, tail}

      <<?., c, _::binary>> when is_digit(c) ->
        <<?., rest::binary>> = after_whole
        {fraction, after_fraction} = digits(rest, 0)
        {exponent, tail} = exponent(after_fraction)
        {whole + 1 + fraction + exponent, :real, tail}

      _no_fraction ->
        case exponent(after_whole) do
          {0, tail} -> {whole, :integer, tail}
          {exponent, tail} -> {whole + exponent, :real, tail}
        end
    end
  end

  defp exponent(<<e, s, c, _::binary>> = bin)
       when is_exponent(e) and is_sign(s) and is_digit(c) do
    <<_e, _s, rest::binary>> = bin
    {length, tail} = digits(rest, 0)
    {length + 2, tail}
  end

  defp exponent(<<e, c, _::binary>> = bin) when is_exponent(e) and is_digit(c) do
    <<_e, rest::binary>> = bin
    {length, tail} = digits(rest, 0)
    {length + 1, tail}
  end

  defp exponent(bin), do: {0, bin}

  defp digits(<<c, rest::binary>>, taken) when is_digit(c), do: digits(rest, taken + 1)
  defp digits(rest, taken), do: {taken, rest}

  defp quoted(rest, quote_byte, category, offset, file, depth, tokens, comments, diagnostics) do
    case quoted_body(rest, quote_byte, 0) do
      {:ok, body, tail} ->
        length = body + 2

        diagnostics =
          if body == 0 and category == :single_quoted do
            [empty_quote(file, offset) | diagnostics]
          else
            diagnostics
          end

        emit(category, length, tail, offset, file, depth, tokens, comments, diagnostics)

      {:unterminated, body, tail} ->
        diagnostic =
          diagnose(
            @unterminated_quote,
            file,
            offset,
            body + 1,
            "unterminated #{describe(category)}",
            "a #{describe(category)} cannot span a line break"
          )

        scan(tail, offset + body + 1, file, depth, tokens, comments, [diagnostic | diagnostics])
    end
  end

  defp quoted_body(<<?\\, c, rest::binary>>, quote_byte, taken)
       when c == ?\\ or c == quote_byte do
    quoted_body(rest, quote_byte, taken + 2)
  end

  defp quoted_body(<<c, rest::binary>>, c, taken), do: {:ok, taken, rest}

  defp quoted_body(<<?\n, _::binary>> = tail, _quote_byte, taken),
    do: {:unterminated, taken, tail}

  defp quoted_body(<<>>, _quote_byte, taken), do: {:unterminated, taken, ""}

  defp quoted_body(<<_c, rest::binary>>, quote_byte, taken) do
    quoted_body(rest, quote_byte, taken + 1)
  end

  defp describe(:single_quoted), do: "quoted atom"
  defp describe(:distinct_object), do: "distinct object"

  defp empty_quote(file, offset) do
    Diagnostic.new(
      @empty_quoted_atom,
      :warning,
      Span.new(file, offset, 2),
      "empty quoted atom",
      hint: "`<single_quoted>` requires at least one character between the quotes"
    )
  end

  defp line_comment(rest, offset, file, depth, tokens, comments, diagnostics) do
    class = comment_class(rest)
    length = 1 + line_length(rest, 0)
    tail = drop(rest, length - 1)

    scan(
      tail,
      offset + length,
      file,
      depth,
      tokens,
      [
        {offset, length, :line, class} | comments
      ],
      diagnostics
    )
  end

  defp line_length(<<?\n, _::binary>>, taken), do: taken
  defp line_length(<<>>, taken), do: taken
  defp line_length(<<_c, rest::binary>>, taken), do: line_length(rest, taken + 1)

  defp block_comment(rest, offset, file, depth, tokens, comments, diagnostics) do
    class = comment_class(rest)

    case :binary.match(rest, "*/") do
      {position, 2} ->
        length = position + 4
        tail = drop(rest, position + 2)

        scan(
          tail,
          offset + length,
          file,
          depth,
          tokens,
          [
            {offset, length, :block, class} | comments
          ],
          diagnostics
        )

      :nomatch ->
        length = byte_size(rest) + 2

        diagnostic =
          diagnose(
            @unterminated_comment,
            file,
            offset,
            length,
            "unterminated block comment",
            "a `/*` comment runs to the matching `*/`, and this one reaches end of file"
          )

        scan(
          "",
          offset + length,
          file,
          depth,
          tokens,
          [
            {offset, length, :block, class} | comments
          ],
          [diagnostic | diagnostics]
        )
    end
  end

  defp comment_class(<<"$$", _::binary>>), do: :system
  defp comment_class(<<?$, _::binary>>), do: :defined
  defp comment_class(_rest), do: :plain

  defp drop(binary, count), do: binary_part(binary, count, byte_size(binary) - count)
end
