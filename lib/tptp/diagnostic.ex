defmodule Tptp.Diagnostic do
  @moduledoc """
  A single observation about the input.

  Diagnostics do not interrupt processing. Every stage accepts and returns an
  accumulator of them, so a result is available even where it is partial, and
  success carries diagnostics alongside it.

  ## Codes

  Codes are stable and the tier is determined by the number, so an editor can
  filter by code and a consumer can suppress a rule without matching on message
  text.

  | Range | Tier |
  |-------|------|
  | `TPTP00xx` | input and resource limits — `Tptp` |
  | `TPTP01xx` | lexical — `Tptp.Lexer` |
  | `TPTP02xx` | statement structure — `Tptp.Splitter` |
  | `TPTP03xx` | grammar — `Tptp.Parser` |
  | `TPTP04xx` | `:==` well-formedness — `Tptp.Lint` |
  | `TPTP05xx` | cross-statement — `Tptp.Lint` |
  | `TPTP06xx` | include — `Tptp.Include` |
  | `TPTP08xx` | analyzer infrastructure — `Tptp.Analyzer` |

  A code is never reassigned, so the numbering contains gaps: `TPTP0103`,
  `TPTP0108`, `TPTP0403`, `TPTP0502`, `TPTP0505` and `TPTP0604` are unassigned.
  `TPTP0505` was withdrawn when the rule raising it was found to contradict the
  TPTP.

  There is no `TPTP07xx` tier. It was reserved for dialect findings, of which there
  are none: the BNF gives each language its own nonterminals, so a construct used
  in a language that does not provide it fails to parse rather than reaching a
  rule. `Tptp.Lint` sets this out, and `Tptp.Query.dialect/1` derives the dialect
  instead.

  `related` carries the accompanying positions of a finding, such as the first
  declaration alongside a redeclaration.
  """

  alias Tptp.Span

  @enforce_keys [:code, :severity, :span, :message]
  defstruct [:code, :severity, :span, :message, :hint, related: []]

  @typedoc """
  How much a diagnostic matters.

  Only `:error` means no result was produced. A `:warning` accompanies a CST that
  is perfectly usable, which is why every entry point returns diagnostics alongside
  success rather than instead of it.
  """
  @type severity :: :error | :warning | :info | :hint

  @typedoc "One thing the library has to say about a span of input."
  @type t :: %__MODULE__{
          code: binary(),
          severity: severity(),
          span: Span.t(),
          message: binary(),
          hint: binary() | nil,
          related: [{Span.t(), binary()}]
        }

  @doc """
  Build a diagnostic.

  `message` is copied with `:binary.copy/1` when it is a sub-binary of the source,
  because a diagnostic outlives the file it describes far more often than a token
  does.
  """
  @spec new(binary(), severity(), Span.t(), binary(), keyword()) :: t()
  def new(code, severity, %Span{} = span, message, options \\ [])
      when is_binary(code) and severity in [:error, :warning, :info, :hint] and
             is_binary(message) do
    %__MODULE__{
      code: code,
      severity: severity,
      span: span,
      message: :binary.copy(message),
      hint: Keyword.get(options, :hint),
      related: Keyword.get(options, :related, [])
    }
  end

  @doc """
  Sort diagnostics into reading order: by file, then by offset, then by code.
  """
  @spec sort([t()]) :: [t()]
  def sort(diagnostics) when is_list(diagnostics) do
    Enum.sort_by(diagnostics, &{&1.span.file, &1.span.offset, &1.code})
  end

  @doc """
  Whether any diagnostic is severe enough to call the result a failure.
  """
  @spec any_errors?([t()]) :: boolean()
  def any_errors?(diagnostics) when is_list(diagnostics) do
    Enum.any?(diagnostics, &(&1.severity == :error))
  end

  @doc """
  Render one diagnostic as a single line, resolving the span against a line index.

      iex> span = Tptp.Span.new(0, 4, 1)
      iex> diagnostic = Tptp.Diagnostic.new("TPTP0101", :error, span, "illegal character")
      iex> index = Tptp.Span.line_index("fof(\\0)")
      iex> Tptp.Diagnostic.format(diagnostic, index)
      "1:5: error: illegal character [TPTP0101]"
  """
  @spec format(t(), Span.line_index(), Path.t() | nil) :: binary()
  def format(%__MODULE__{} = diagnostic, line_index, path \\ nil) do
    {line, column} = Span.line_column(line_index, diagnostic.span.offset)
    prefix = if path, do: "#{path}:", else: ""

    "#{prefix}#{line}:#{column}: #{diagnostic.severity}: " <>
      "#{diagnostic.message} [#{diagnostic.code}]"
  end
end
