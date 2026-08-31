defmodule Tptp.File do
  @moduledoc """
  One TPTP file, read: its statements, its comments and everything the library has
  to say about it.

  ## The source is retained, and that is deliberate

  Every leaf's `text` is a sub-binary of `source`, so the file binary must outlive
  the tree — which it does, because it is right here. That is the whole point of
  the arrangement: reading a 4 MB problem costs one 4 MB binary plus a tree of
  offsets, rather than a copy of every symbol. `Tptp.detach/1` is the way out for a
  consumer that wants to keep a handful of statements and let the file go.

  ## Comments are beside the statements, not in them

  The BNF allows a comment between any two tokens, and they are not white space, so
  they cannot live in the tree without polluting every node's children. They are
  kept as an ordered list of spans, which is what the format-preserving printer
  needs to re-attach them by position and what everything else needs to ignore
  them.

  ## What is computed on demand

  `line_index/1` and `digest/1` are functions, not fields. Both are O(bytes), both
  are needed rarely — the first only to render a position for a human, the second
  only to key a cache — and a caller that needs either repeatedly should hold the
  result rather than have every file pay for it.
  """

  alias Tptp.Diagnostic
  alias Tptp.Node
  alias Tptp.Span
  alias Tptp.Statement
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include

  @enforce_keys [:id, :source, :bnf_version]
  defstruct [:id, :path, :source, :bnf_version, statements: [], comments: [], diagnostics: []]

  @typedoc "One parsed TPTP file: its source, its statements, its comments and everything said about them."
  @type t :: %__MODULE__{
          id: Span.file_id(),
          path: Path.t() | nil,
          source: binary(),
          bnf_version: binary(),
          statements: [Statement.t()],
          comments: [Tptp.Lexer.comment()],
          diagnostics: [Diagnostic.t()]
        }

  @doc """
  The `include` directives this file names, in source order.

  Derived rather than stored, because a second list of the same structs would be a
  second thing to keep in step.

      iex> {:ok, file, []} = Tptp.from_string("fof(a,axiom,p). include('b.ax').")
      iex> file |> Tptp.File.includes() |> Enum.map(&Tptp.Statement.Include.path/1)
      ["b.ax"]
  """
  @spec includes(t()) :: [Include.t()]
  def includes(%__MODULE__{} = file) do
    Enum.filter(file.statements, &match?(%Include{}, &1))
  end

  @doc """
  The annotated formulae, `include` directives excluded.
  """
  @spec formulae(t()) :: [Annotated.t()]
  def formulae(%__MODULE__{} = file) do
    Enum.filter(file.statements, &match?(%Annotated{}, &1))
  end

  @doc """
  Whether anything error-severity was found.

      iex> {:ok, file, _diagnostics} = Tptp.from_string("fof(a,axiom,p q).")
      iex> Tptp.File.any_errors?(file)
      true
  """
  @spec any_errors?(t()) :: boolean()
  def any_errors?(%__MODULE__{} = file), do: Diagnostic.any_errors?(file.diagnostics)

  @doc """
  A line-start index for turning offsets into line and column numbers.

  O(bytes) to build and independent of the tree, so hold it if you are resolving
  more than a handful of positions. `format_diagnostics/1` builds one and reuses it
  for the whole list, which is the common case.
  """
  @spec line_index(t()) :: Span.line_index()
  def line_index(%__MODULE__{} = file), do: Span.line_index(file.source)

  @doc """
  A SHA-256 of the file's bytes, for keying a cache across runs.

  Pair it with `bnf_version` — the same bytes read against a different BNF can
  produce a different tree, so a cache keyed on content alone will eventually hand
  back a CST the current code cannot read.
  """
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{} = file), do: :crypto.hash(:sha256, file.source)

  @doc """
  Every diagnostic, rendered one per line against a single line index.

      iex> {:ok, file, _diagnostics} = Tptp.from_string("wibble(a).")
      iex> Tptp.File.format_diagnostics(file)
      ["1:1: error: `wibble` does not start a TPTP statement [TPTP0201]"]
  """
  @spec format_diagnostics(t()) :: [binary()]
  def format_diagnostics(%__MODULE__{} = file) do
    index = line_index(file)
    Enum.map(file.diagnostics, &Diagnostic.format(&1, index, file.path))
  end

  @doc """
  The statement containing `offset`, or `nil`.

  The first half of the editor's incremental path: find the statement under the
  cursor, reparse just that one, splice it back. Linear in statements, which is
  what a sorted list costs; a consumer editing a 3 million statement file wants an
  interval tree of its own, built from these spans.
  """
  @spec statement_at(t(), non_neg_integer()) :: Statement.t() | nil
  def statement_at(%__MODULE__{} = file, offset) when is_integer(offset) do
    Enum.find(file.statements, fn statement ->
      offset >= statement.off and offset < statement.off + statement.len
    end)
  end

  @doc """
  The innermost CST node under `offset`, or `nil`.

      iex> {:ok, file, []} = Tptp.from_string("fof(a,axiom,p(bcd)).")
      iex> Tptp.File.node_at(file, 15).text
      "bcd"
  """
  @spec node_at(t(), non_neg_integer()) :: Node.t() | nil
  def node_at(%__MODULE__{} = file, offset) when is_integer(offset) do
    case statement_at(file, offset) do
      nil -> nil
      statement -> statement |> Statement.roots() |> Enum.find_value(&Node.at(&1, offset))
    end
  end
end
