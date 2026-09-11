defmodule Tptp do
  @moduledoc """
  A span-preserving reader for the TPTP language.

  This library scans, splits, parses, resolves `include` directives, validates and
  prints TPTP. It performs no type checking, no normalisation and no elaboration,
  and it attaches no semantics to the operators it recognises. Its output is a
  transcription of the input with byte-accurate source positions.

  ## Reading a file

      {:ok, file, diagnostics} = Tptp.from_file("Problems/PUZ/PUZ001+1.p")

      file.statements   # [%Tptp.Statement.Annotated{} | %Tptp.Statement.Include{}]
      file.comments     # ordered spans, held outside the tree
      diagnostics       # sorted by source position

  ## Scope

  THF requires a declaration for every symbol and a type on every bound variable,
  and the first-order typed dialects fix a default for whatever they leave out —
  `$i` for an untyped variable, `($i * ... * $i) > $i` or `> $o` for an undeclared
  function or predicate. No type inference is therefore required to read any of
  them, and none is performed. Explicit type arguments are recorded verbatim
  and in source order: in `f @ $i @ a`, the `$i` is retained as an argument of the
  application with its own span.

  A consequence is that the concrete syntax tree does not distinguish a THF type
  from a THF term. The grammar does not either — `<thf_unitary_type> ::=
  <thf_unitary_formula>` identifies the two nonterminals, and the well-formedness
  conditions of the `:==` layer are what restrict a formula to those admissible as
  types. Elaboration against a signature is the consumer's responsibility.

  ## Error handling

  Each stage threads a diagnostic accumulator, so a partial result is available for
  any input and malformed input yields a shorter file rather than an exception.
  `from_string/2` has no failure case; `from_file/2` fails only when the file
  cannot be read. The `!` variants raise `Tptp.Error` carrying the accumulated
  diagnostics.

  ## Includes

  `from_file/2` reads a single file. An `include` directive is recorded as a
  `Tptp.Statement.Include` and not followed, since resolution reads files the
  caller did not name and, under `Tptp.Resolver.Http`, performs network access.
  `Tptp.Unit` is the entry point for include resolution and requires a resolver.

  ## Stages

  | Module | Responsibility |
  |--------|----------------|
  | `Tptp.Lexer` | tokenisation, resumable at statement granularity |
  | `Tptp.Splitter` | statement boundaries and position-dependent keyword resolution |
  | `Tptp.Parser` | tokens to a `%Tptp.Node{}` concrete syntax tree |
  | `Tptp.Include` | include graph construction, with cycle detection |
  | `Tptp.Lint` | the `:==` well-formedness conditions and cross-statement checks |
  | `Tptp.Analysis` | file, diagnostics, symbol table and dialect from one traversal |
  | `Tptp.Printer.Canonical` | tree to bytes |

  ## Versioning

  `bnf_version/0` reports the TPTP BNF release the shipped parser was generated
  from. It is distinct from the package version, which is semantic versioning over
  the Elixir API. Regenerating from a BNF release that introduces nonterminals is a
  minor version increment, since it introduces `kind` atoms that an exhaustive
  pattern match will not cover.
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

    * `:file` — the identifier recorded in every span, for callers tracking more
      than one file. Defaults to `0`.
    * `:path` — recorded on the result and used when rendering diagnostics.
      `from_file/2` sets it.
    * `:max_statements` — an upper bound on the number of statements read, reported
      as a diagnostic when reached. Defaults to no limit.
  """
  @type option :: {:file, Span.file_id()} | {:path, Path.t()} | {:max_statements, pos_integer()}

  @doc """
  Reads TPTP from a binary.

  Always succeeds. Defects in the input are returned as diagnostics alongside
  whatever result could be constructed.

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
  Reads TPTP from a binary, raising `Tptp.Error` on any error-severity diagnostic.

  Warnings do not raise and remain on the returned file.
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
  Reads a single TPTP file from disk.

  `include` directives are recorded rather than followed; see `Tptp.Unit`. Fails
  only when the file cannot be read.
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
  Reads a single TPTP file from disk, raising `Tptp.Error` if the file cannot be
  read or any diagnostic is error-severity.
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
  Reads TPTP from a binary as a stream of statements.

  The lazy counterpart to `from_string/2`, for input too large to materialise as a
  statement list. Peak memory is bounded by the largest single statement rather
  than by the size of the input.

  Each element is a `t:Tptp.Parser.result/0`: `{:ok, statement, diagnostics}` or
  `{:error, diagnostics}`. Comments are not observable through this path; use
  `from_string/2` where they are required.

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
  Reads a TPTP file from disk as a stream of statements.

  Raises if the file cannot be read, following the convention of `File.stream!/3`.
  The source is held as a single binary, into which every leaf's `text` is a
  sub-binary; the statements are what is streamed.
  """
  @spec stream_file!(Path.t(), [option()]) :: Enumerable.t()
  def stream_file!(path, options \\ []) when is_list(options) do
    path |> File.read!() |> stream_string!(options)
  end

  @doc """
  Parses if required, applies the lint traversal once, and returns a
  `Tptp.Analysis`.

  A binary is parsed first; a `Tptp.File` or `Tptp.Unit` is analysed as given.
  Always succeeds: input that does not parse yields an analysis whose diagnostics
  record the failure.

  `options` is the union of `t:option/0` and `t:Tptp.Lint.option/0`. Each stage
  reads the keys it recognises.

      iex> analysis = Tptp.analyze("fof(a, axiom, p). fof(a, axiom, q).")
      iex> Enum.map(analysis.diagnostics, & &1.code)
      ["TPTP0503"]
  """
  @spec analyze(binary() | Tptp.File.t() | Tptp.Unit.t(), keyword()) :: Tptp.Analysis.t()
  def analyze(subject, options \\ [])

  def analyze(source, options) when is_binary(source) do
    {:ok, file, _diagnostics} = from_string(source, options)
    analyze(file, options)
  end

  def analyze(%Tptp.File{} = file, options), do: analysis(file, file.diagnostics, options)
  def analyze(%Tptp.Unit{} = unit, options), do: analysis(unit, unit.diagnostics, options)

  @spec analysis(Tptp.File.t() | Tptp.Unit.t(), [Diagnostic.t()], keyword()) :: Tptp.Analysis.t()
  defp analysis(subject, own, options) do
    {found, table} = Tptp.Lint.scan(subject, options)

    %Tptp.Analysis{
      file: subject,
      diagnostics: Diagnostic.sort(own ++ found),
      table: table,
      line_index: nil
    }
  end

  @doc """
  Returns a copy holding its own binaries, allowing the source to be collected.

  Every leaf's `text` is ordinarily a sub-binary of the file's source, which keeps
  the whole source reachable. Use this when retaining a small number of statements
  from a large file.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> Tptp.detach(statement).formula.text
      "p"
  """
  @spec detach(Tptp.Statement.t()) :: Tptp.Statement.t()
  def detach(statement), do: Tptp.Statement.detach(statement)

  @doc """
  Returns the TPTP BNF release the shipped parser was generated from.

  Read from the vendored grammar at compile time, so it cannot diverge from the
  parser it describes. Record it alongside any cached tree: a BNF release may
  change node kinds, and a cache keyed without it can yield a tree the current
  code cannot interpret.

      iex> Tptp.bnf_version()
      "9.3.1.3"
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
