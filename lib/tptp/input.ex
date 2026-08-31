defmodule Tptp.Input do
  @moduledoc """
  One unparsed TPTP statement: its language, its tokens and where it came from.

  The name is the BNF's own. `<TPTP_input> ::= <annotated_formula> | <include>` is
  the unit a `<TPTP_file>` is a sequence of, and it is what `Tptp.Splitter` hands
  to `Tptp.Parser` — hence `Tptp.Input` rather than a second `Statement`, which is
  the *parsed* thing.

  ## Why the language is decided before parsing

  Every input begins with one of seven keywords, so the dialect is knowable from
  token zero without looking at anything else. Deciding it here buys three things:
  an input whose prefix is not a keyword can be reported precisely and skipped
  rather than dragged through the grammar for a worse error; a consumer can filter
  a 455 MB axiom file down to its `include` statements without parsing a single
  formula; and `Tptp.Query.dialect/1` gets its cheapest input for free.

  `:unknown` means exactly that the first token was not one of the seven, and it
  always comes with a `TPTP0201` or `TPTP0202` diagnostic on the input.

  ## Offsets, not spans

  Like `Tptp.Node`, an input stores a bare offset and length. The file id belongs
  to the file, not to each of its thousands of statements, so `span/2` builds a
  `Tptp.Span` on demand when a diagnostic needs one.
  """

  alias Tptp.Span
  alias Tptp.Token

  @enforce_keys [:language, :tokens, :offset, :length]
  defstruct [:language, :tokens, :offset, :length, diagnostics: []]

  @typedoc """
  The TPTP language this input is written in, or `:unknown` when token zero was
  not a language keyword.
  """
  @type language :: :thf | :tff | :tcf | :fof | :cnf | :tpi | :include | :unknown

  @typedoc "One statement's worth of tokens, with the span they cover and the language they open with."
  @type t :: %__MODULE__{
          language: language(),
          tokens: [Token.t()],
          offset: non_neg_integer(),
          length: non_neg_integer(),
          diagnostics: [Tptp.Diagnostic.t()]
        }

  @languages [
    kw_thf: :thf,
    kw_tff: :tff,
    kw_tcf: :tcf,
    kw_fof: :fof,
    kw_cnf: :cnf,
    kw_tpi: :tpi,
    kw_include: :include
  ]

  @language_map Map.new(@languages)

  @doc """
  The language an opening keyword category names.

      iex> Tptp.Input.language_for(:kw_cnf)
      :cnf
      iex> Tptp.Input.language_for(:lower_word)
      :unknown
  """
  @spec language_for(Token.category()) :: language()
  def language_for(category) when is_atom(category) do
    Map.get(@language_map, category, :unknown)
  end

  @doc """
  The keyword categories that open an input, paired with the language they name.
  """
  @spec languages() :: [{Token.category(), language()}]
  def languages, do: @languages

  @doc """
  The input's extent, as a span in the file it was read from.
  """
  @spec span(t(), Span.file_id()) :: Span.t()
  def span(%__MODULE__{} = input, file \\ 0) do
    Span.new(file, input.offset, input.length)
  end

  @doc """
  The bytes the input covers, terminating `.` included.

  A sub-binary, not a copy.
  """
  @spec text(t(), binary()) :: binary()
  def text(%__MODULE__{} = input, source) when is_binary(source) do
    binary_part(source, input.offset, input.length)
  end

  @doc """
  Whether this input is an `include` directive.

  Cheaper and clearer at a call site than matching on the language atom, and it is
  the question `Tptp.Include` asks of every input in a file.

      iex> {[input], _comments, _diagnostics} = Tptp.Splitter.inputs("include('a.ax').")
      iex> Tptp.Input.include?(input)
      true
  """
  @spec include?(t()) :: boolean()
  def include?(%__MODULE__{language: :include}), do: true
  def include?(%__MODULE__{}), do: false
end
