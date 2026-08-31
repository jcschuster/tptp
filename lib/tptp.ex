defmodule Tptp do
  @moduledoc """
  A faithful, span-carrying reader for the TPTP language.

  `tptp` scans, splits, parses, resolves `include` directives, validates and prints
  TPTP. It does not type-check, does not normalise, does not know what `&` means,
  and has no notion of a logic. Everything it produces is a transcription of the
  input with byte-accurate spans attached.

  ## Reading a file

      {:ok, file, diagnostics} = Tptp.from_file("Problems/PUZ/PUZ001+1.p")

      file.statements   # [%Tptp.Statement.Annotated{} | %Tptp.Statement.Include{}]
      file.comments     # ordered spans, never in the tree
      diagnostics       # everything the library has to say, in reading order

  ## What it deliberately does not do

  TPTP's typed dialects declare every symbol and annotate every bound variable, so
  there is no inference problem to solve at this layer and none is attempted. The
  CST records explicit type arguments verbatim, in source order — `f @ $i @ a`
  keeps its `$i` as an ordinary argument with its own span — so a consumer never
  has to reconstruct them. It follows that the CST **cannot distinguish a THF type
  from a THF term**, and does not try: `<thf_unitary_type> ::= <thf_unitary_formula>`
  makes them the same nonterminal, and only the `:==` layer says which formulae are
  legal types. Elaboration belongs to the consumer, with a signature in hand.

  ## Nothing raises on input

  Every stage threads a diagnostic accumulator, so a partial result is always
  available and malformed input produces a shorter file rather than an exception.
  `from_string/2` therefore has no failure case at all: it reports. `from_file/2`
  fails only when the bytes cannot be read. The `!` variants exist for callers who
  would rather be interrupted, and raise `Tptp.Error` carrying the full list.

  ## Includes are not followed

  `from_file/2` reads one file. An `include` directive is recorded as a
  `Tptp.Statement.Include` and left alone, because following it means reading a
  file the caller did not name — or, with the HTTP resolver, reaching the network.
  `Tptp.Unit` is the opt-in entry point for that, and it takes a resolver.

  ## Layers

  | Module | Job |
  |--------|-----|
  | `Tptp.Lexer` | bytes to tokens, one statement at a time |
  | `Tptp.Splitter` | statement boundaries and the diagnostics the parser cannot reach |
  | `Tptp.Parser` | tokens to a `%Tptp.Node{}` CST |
  | `Tptp.Include` | the include graph, with cycle detection |
  | `Tptp.Lint` | the `:==` semantic layer and the cross-statement conditions |
  | `Tptp.Printer.Canonical` | back to bytes |

  ## Versions

  Two numbers, and they are not the same. `bnf_version/0` is the TPTP BNF the
  shipped parser was generated from; the package version is semver over the Elixir
  API. A BNF regeneration that adds nonterminals is a minor bump, because new
  `kind` atoms appear and a consumer matching exhaustively will need updating.
  """

  alias Tptp.Diagnostic
  alias Tptp.Parser
  alias Tptp.Span
  alias Tptp.Splitter

  @unreadable "TPTP0001"
  @statement_limit "TPTP0002"

  @bnf_path Path.wildcard(Path.join(__DIR__, "../priv/bnf/SyntaxBNF-v*")) |> List.first()
  @external_resource @bnf_path
  @bnf_version Tptp.Bnf.version!(@bnf_path)

  @typedoc """
  Options accepted by the reading entry points.

    * `:file` — the id stamped into every span, for a caller tracking more than one
      file. Defaults to `0`.
    * `:path` — recorded on the result and used in rendered diagnostics.
      `from_file/2` sets it for you.
    * `:max_statements` — stop after this many and say so, rather than reading a
      hostile file to the end. Defaults to no limit.
  """
  @type option :: {:file, Span.file_id()} | {:path, Path.t()} | {:max_statements, pos_integer()}

  @doc """
  Read TPTP from a binary.

  There is no failure case: everything wrong with the input comes back as a
  diagnostic, alongside as much of a result as could be built.

      iex> {:ok, file, []} = Tptp.from_string("fof(a, axiom, p).")
      iex> [statement] = file.statements
      iex> {statement.language, statement.name.text}
      {:fof, "a"}

      iex> {:ok, file, [diagnostic]} = Tptp.from_string("fof(a, axiom, p). wibble.")
      iex> {length(file.statements), diagnostic.code}
      {1, "TPTP0201"}
  """
  @spec from_string(binary(), [option()]) :: {:ok, Tptp.File.t(), [Diagnostic.t()]}
  def from_string(source, options \\ []) when is_binary(source) and is_list(options) do
    id = Keyword.get(options, :file, 0)
    limit = Keyword.get(options, :max_statements, :infinity)

    {statements, comments, diagnostics} = gather(source, 0, id, limit, 0, [], [], [])

    file = %Tptp.File{
      id: id,
      path: Keyword.get(options, :path),
      source: source,
      bnf_version: @bnf_version,
      statements: statements,
      comments: comments,
      diagnostics: Diagnostic.sort(diagnostics)
    }

    {:ok, file, file.diagnostics}
  end

  @doc """
  Read TPTP from a binary, raising `Tptp.Error` if anything is error-severity.

  Warnings do not raise, because a warning is by definition something you can
  proceed past; they stay on the returned file.
  """
  @spec from_string!(binary(), [option()]) :: Tptp.File.t()
  def from_string!(source, options \\ []) when is_binary(source) do
    {:ok, file, diagnostics} = from_string(source, options)

    if Diagnostic.any_errors?(diagnostics) do
      raise Tptp.Error, diagnostics: diagnostics, path: file.path, source: source
    end

    file
  end

  @doc """
  Read one TPTP file from disk.

  `include` directives are recorded, not followed; see `Tptp.Unit` for that. Fails
  only when the bytes cannot be read.
  """
  @spec from_file(Path.t(), [option()]) ::
          {:ok, Tptp.File.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def from_file(path, options \\ []) when is_list(options) do
    case File.read(path) do
      {:ok, source} ->
        from_string(source, Keyword.put_new(options, :path, path))

      {:error, reason} ->
        {:error, [unreadable(path, reason, Keyword.get(options, :file, 0))]}
    end
  end

  @doc """
  Read one TPTP file from disk, raising `Tptp.Error` on an unreadable file or any
  error-severity diagnostic.
  """
  @spec from_file!(Path.t(), [option()]) :: Tptp.File.t()
  def from_file!(path, options \\ []) when is_list(options) do
    case from_file(path, options) do
      {:ok, file, diagnostics} ->
        if Diagnostic.any_errors?(diagnostics) do
          raise Tptp.Error, diagnostics: diagnostics, path: path, source: file.source
        end

        file

      {:error, diagnostics} ->
        raise Tptp.Error, diagnostics: diagnostics, path: path
    end
  end

  @doc """
  Read TPTP from a binary one statement at a time.

  The lazy counterpart to `from_string/2`, and the only way to read a file too
  large to hold as statements — the 455 MB axiom set in the TPTP library is 3.3
  million of them. Peak memory is one statement, whatever the file size.

  Each element is a `t:Tptp.Parser.result/0`: `{:ok, statement, diagnostics}` or
  `{:error, diagnostics}`. Comments are not observable through this path; a caller
  that needs them wants `from_string/2` and a file small enough to afford it.

      iex> "fof(a,axiom,p). fof(b,axiom,q)."
      ...> |> Tptp.stream_string!()
      ...> |> Enum.map(fn {:ok, statement, []} -> statement.name.text end)
      ["a", "b"]
  """
  @spec stream_string!(binary(), [option()]) :: Enumerable.t()
  def stream_string!(source, options \\ []) when is_binary(source) and is_list(options) do
    id = Keyword.get(options, :file, 0)

    source
    |> Splitter.stream_inputs(id)
    |> Stream.map(&Parser.statement_from_input(&1, source, id))
  end

  @doc """
  Read a TPTP file from disk one statement at a time.

  Raises if the file cannot be read, in the manner of `File.stream!/3`. The whole
  file is held as one binary — that part is cheap, and it is what every leaf's
  `text` points into; it is the *statements* that are streamed.
  """
  @spec stream_file!(Path.t(), [option()]) :: Enumerable.t()
  def stream_file!(path, options \\ []) when is_list(options) do
    path |> File.read!() |> stream_string!(options)
  end

  @doc """
  A copy that owns its bytes, so the file it was read from can be collected.

  Every leaf's `text` is a sub-binary of the source, which is the right trade while
  the file is in hand and the wrong one for a consumer keeping three statements out
  of a 455 MB axiom set.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> Tptp.detach(statement).formula.text
      "p"
  """
  @spec detach(Tptp.Statement.t()) :: Tptp.Statement.t()
  def detach(statement), do: Tptp.Statement.detach(statement)

  @doc """
  The TPTP BNF version the shipped parser was generated from.

  Read at compile time from the vendored grammar, so it cannot drift from the
  parser it describes. Store it alongside anything you cache: a BNF bump can change
  node kinds, and a cache keyed without it will hand you a CST the current code
  cannot read.

      iex> Tptp.bnf_version()
      "9.3.1.2"
  """
  @spec bnf_version() :: binary()
  def bnf_version, do: @bnf_version

  @spec gather(
          binary(),
          non_neg_integer(),
          Span.file_id(),
          pos_integer() | :infinity,
          non_neg_integer(),
          [Tptp.Statement.t()],
          [[Tptp.Lexer.comment()]],
          [[Diagnostic.t()]]
        ) :: {[Tptp.Statement.t()], [Tptp.Lexer.comment()], [Diagnostic.t()]}
  defp gather(source, offset, id, limit, count, statements, comments, diagnostics) do
    if reached?(count, limit) do
      finish(statements, comments, [[too_many(source, offset, id, limit)] | diagnostics])
    else
      case Splitter.next_input(source, offset, id) do
        {:input, input, next, new_comments} ->
          {statements, diagnostics} = add(input, source, id, statements, diagnostics)

          gather(
            source,
            next,
            id,
            limit,
            count + 1,
            statements,
            [new_comments | comments],
            diagnostics
          )

        {:eof, _next, new_comments, new_diagnostics} ->
          finish(statements, [new_comments | comments], [new_diagnostics | diagnostics])
      end
    end
  end

  defp add(input, source, id, statements, diagnostics) do
    case Parser.statement_from_input(input, source, id) do
      {:ok, statement, new} -> {[statement | statements], [new | diagnostics]}
      {:error, new} -> {statements, [new | diagnostics]}
    end
  end

  defp finish(statements, comments, diagnostics) do
    {Enum.reverse(statements), flatten(comments), flatten(diagnostics)}
  end

  defp flatten(chunks), do: chunks |> Enum.reverse() |> Enum.concat()

  defp reached?(_count, :infinity), do: false
  defp reached?(count, limit), do: count >= limit

  defp too_many(source, offset, id, limit) do
    Diagnostic.new(
      @statement_limit,
      :warning,
      Span.new(id, min(offset, byte_size(source)), 0),
      "stopped after #{limit} statements",
      hint: "raise or remove `:max_statements` to read the rest"
    )
  end

  defp unreadable(path, reason, id) do
    Diagnostic.new(
      @unreadable,
      :error,
      Span.new(id, 0, 0),
      "cannot read #{path}: #{:file.format_error(reason)}"
    )
  end
end
