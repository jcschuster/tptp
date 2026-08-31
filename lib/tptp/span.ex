defmodule Tptp.Span do
  @moduledoc """
  A byte range in one file.

  Spans are byte offsets, not line/column pairs. Tracking a line and a column in
  the scanner costs a branch and two increments per byte for information that most
  tokens never need; a line index is built once per file instead, and only when a
  diagnostic is actually rendered.

  The `file` field is what makes `include` work. A declaration can arrive from an
  axiom file and be used in the problem file, and a diagnostic about it has to be
  able to point at both, so a span is meaningless without knowing which file it
  indexes.

  Nodes do not store spans. `%Tptp.Node{}` carries a bare offset and length, and a
  span is built on demand — the file id is a per-file fact, and paying a word for
  it on every node of a multi-million-node CST would be paying it in the wrong
  place.
  """

  @enforce_keys [:file, :offset, :length]
  defstruct [:file, :offset, :length]

  @typedoc """
  Which file a span is in.

  An integer rather than a path, because `include` makes spans cross files and
  every statement, diagnostic and symbol has to carry one.
  """
  @type file_id :: non_neg_integer()

  @typedoc "A byte range in one file."
  @type t :: %__MODULE__{
          file: file_id(),
          offset: non_neg_integer(),
          length: non_neg_integer()
        }

  @typedoc """
  Line-start byte offsets, one per line, as a tuple for constant-time indexing.
  """
  @opaque line_index :: tuple()

  @doc """
  A span over `length` bytes starting at `offset` in file `file`.
  """
  @spec new(file_id(), non_neg_integer(), non_neg_integer()) :: t()
  def new(file, offset, length)
      when is_integer(file) and file >= 0 and is_integer(offset) and offset >= 0 and
             is_integer(length) and length >= 0 do
    %__MODULE__{file: file, offset: offset, length: length}
  end

  @doc """
  The byte just past the end of the span.
  """
  @spec ending(t()) :: non_neg_integer()
  def ending(%__MODULE__{offset: offset, length: length}), do: offset + length

  @doc """
  The smallest span covering both, which must be in the same file.
  """
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{file: file} = left, %__MODULE__{file: file} = right) do
    offset = min(left.offset, right.offset)
    %__MODULE__{file: file, offset: offset, length: max(ending(left), ending(right)) - offset}
  end

  @doc """
  The bytes the span covers.

  The result is a sub-binary: four words and no copy, holding a reference into
  `source`. That is what you want while the file is alive anyway, and a leak when
  it is not — a thirty-byte functor name can retain a ten-megabyte file. Use
  `:binary.copy/1` at the boundary where a name outlives its file.
  """
  @spec text(t(), binary()) :: binary()
  def text(%__MODULE__{offset: offset, length: length}, source)
      when offset + length <= byte_size(source) do
    binary_part(source, offset, length)
  end

  @doc """
  Build the line index for a file.

  One pass, using `:binary.matches/2`, which is a NIF. Build it lazily: a corpus
  run that reports no diagnostics should never pay for it.
  """
  @spec line_index(binary()) :: line_index()
  def line_index(source) when is_binary(source) do
    starts = Enum.map(:binary.matches(source, "\n"), fn {offset, _length} -> offset + 1 end)
    List.to_tuple([0 | starts])
  end

  @doc """
  Resolve a byte offset to a one-based line and column, by binary search.

      iex> index = Tptp.Span.line_index("fof(a,axiom,p).\\nfof(b,axiom,q).\\n")
      iex> Tptp.Span.line_column(index, 0)
      {1, 1}
      iex> Tptp.Span.line_column(index, 16)
      {2, 1}
      iex> Tptp.Span.line_column(index, 20)
      {2, 5}
  """
  @spec line_column(line_index(), non_neg_integer()) :: {pos_integer(), pos_integer()}
  def line_column(index, offset) when is_tuple(index) and is_integer(offset) and offset >= 0 do
    line = search(index, offset, 0, tuple_size(index) - 1)
    {line + 1, offset - elem(index, line) + 1}
  end

  @doc """
  The number of lines the index covers.
  """
  @spec line_count(line_index()) :: pos_integer()
  def line_count(index) when is_tuple(index), do: tuple_size(index)

  @spec search(line_index(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  defp search(_index, _offset, low, high) when low >= high, do: low

  defp search(index, offset, low, high) do
    middle = div(low + high + 1, 2)

    if elem(index, middle) > offset do
      search(index, offset, low, middle - 1)
    else
      search(index, offset, middle, high)
    end
  end
end
