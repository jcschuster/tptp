defmodule Tptp.Printer.Pretty do
  @moduledoc """
  Prints a CST to a chosen width, breaking lines where a formula is too long to fit.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p&q).")
      iex> Tptp.Printer.Pretty.to_string(statement)
      "fof(a, axiom, p & q)."

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p&q).")
      iex> Tptp.Printer.Pretty.to_string(statement, width: 12)
      "fof(\\n  a,\\n  axiom,\\n  p\\n  & q\\n)."

  At a width of twelve columns:

      fof(
        a,
        axiom,
        p
        & q
      ).

  ## Contract

  The token sequence is that of `Tptp.Printer.Canonical`: the same tokens, in the
  same order, with the same spellings, differing only in the white space between
  them. This is not preserved by construction but inherited: this module obtains
  the token list from the canonical printer and determines only where line breaks
  occur, so a change to the grammar cannot cause the two printers to diverge.

  Line breaking uses `Inspect.Algebra`, the Wadler–Lindig algebra in the standard
  library, which introduces no dependency and produces an optimal rather than
  greedy layout: a group is flattened when its entire contents fit, so
  `p(a, b, c)` does not break its first argument before establishing that the
  third would not have fitted.

  ## Structure

  The token stream of a statement has balanced `(`, `[` and `{`. `[.]`, `<.>`,
  `{.}` and `(.)` are single tokens after lexing, as are quoted atoms and distinct
  objects, and the grammar guarantees the remainder. Bracket matching over the flat
  token list therefore recovers the nesting without a second traversal of the tree.

  Each bracket region becomes one group with a two-space indent, and whether it
  breaks is determined independently, so an argument that does not fit does not
  separate its siblings. The internal `item` type represents this recovery: either
  a token, or an opener with its contents and its closer. The closer is `nil` only
  for unbalanced brackets, which the grammar makes unreachable and which are
  handled rather than raising.

  ## Permitted break positions

    * **After a comma**, giving one element per line where a list breaks.
    * **Before a binary connective**, never after, so that a broken chain reads

          p(X)
          & q(X)
          & r(X)

      with the connective at the start of the line, which is the convention in
      TPTP output and which allows a long conjunction to be scanned for the
      operator that differs. `@` is included, so a long THF application spine
      breaks in the same way, as is `>`, for a long type signature.
    * **Immediately inside a bracket**, which permits a region to open.

  No other position. In particular no break occurs inside a quoted atom or a
  distinct object, each being a single token, and this module does not examine the
  interior of a token.

  ## Safety of white space

  Every position at which a break may occur may also carry a space, and every
  position at which it may not still receives the spacing prescribed by
  `Tptp.Printer.Spacing`. White space between two TPTP tokens can neither merge nor
  divide them: the longest-match cases that could, such as `~` adjacent to `|`, are
  those `Spacing` already separates.
  """

  alias Inspect.Algebra
  alias Tptp.Printer.Canonical
  alias Tptp.Printer.Spacing
  alias Tptp.Token

  @indent 2
  @default_width 80

  @infix [
    :gentzen_arrow,
    :iff,
    :xor,
    :implies,
    :impliedby,
    :nor,
    :nand,
    :ampersand,
    :vline,
    :apply,
    :arrow,
    :equal,
    :not_equal,
    :identical
  ]

  @breaks_before Enum.map(@infix, &Token.spelling/1)
  @openers ["(", "[", "{"]
  @closers [")", "]", "}"]

  @typedoc "Anything this printer knows how to write, which is anything the canonical printer does."
  @type printable :: Canonical.printable()

  @typedoc """
  How wide a line may be.

  `:width` is the column the algebra tries to keep within; it is a target and not a
  guarantee, because a single token longer than the width cannot be broken.
  """
  @type option :: {:width, pos_integer()}

  @typep item :: binary() | {binary(), [item()], binary() | nil}

  @doc """
  Print to a width, as iodata.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("cnf(c,axiom,p|~q).")
      iex> statement |> Tptp.Printer.Pretty.to_iodata() |> IO.iodata_to_binary()
      "cnf(c, axiom, p | ~q)."
  """
  @spec to_iodata(printable(), [option()]) :: iodata()
  def to_iodata(printable, options \\ [])

  def to_iodata(%Tptp.File{} = file, options) do
    Enum.map(file.statements, &[to_iodata(&1, options), ?\n])
  end

  def to_iodata(%Tptp.Unit{} = unit, options) do
    unit
    |> Tptp.Unit.statements()
    |> Enum.map(fn {_id, statement} -> [to_iodata(statement, options), ?\n] end)
  end

  def to_iodata(printable, options) do
    width = Keyword.get(options, :width, @default_width)

    printable
    |> Canonical.tokens()
    |> document()
    |> Algebra.format(width)
  end

  @doc """
  Print to a width, as a binary.

      iex> {:ok, file, []} = Tptp.from_string("fof(a,axiom,p(X)&q).")
      iex> Tptp.Printer.Pretty.to_string(file)
      "fof(a, axiom, p(X) & q).\\n"
  """
  @spec to_string(printable(), [option()]) :: binary()
  def to_string(printable, options \\ []) do
    printable |> to_iodata(options) |> IO.iodata_to_binary()
  end

  @doc """
  Write the pretty form to disk.
  """
  @spec to_file(printable(), Path.t(), [option()]) :: :ok | {:error, File.posix()}
  def to_file(printable, path, options \\ []) do
    File.write(path, to_iodata(printable, options))
  end

  @spec document([binary()]) :: Algebra.t()
  defp document(tokens) do
    {items, _leftover} = regions(tokens)

    Algebra.group(sequence(items, nil))
  end

  @spec regions([binary()]) :: {[item()], [binary()]}
  defp regions([]), do: {[], []}

  defp regions([token | _rest] = tokens) when token in @closers, do: {[], tokens}

  defp regions([open | rest]) when open in @openers do
    {inner, remainder} = regions(rest)
    {close, tail} = closer(remainder)
    {siblings, leftover} = regions(tail)

    {[{open, inner, close} | siblings], leftover}
  end

  defp regions([token | rest]) do
    {siblings, leftover} = regions(rest)

    {[token | siblings], leftover}
  end

  @spec closer([binary()]) :: {binary() | nil, [binary()]}
  defp closer([close | tail]) when close in @closers, do: {close, tail}
  defp closer(tokens), do: {nil, tokens}

  @spec sequence([item()], binary() | nil) :: Algebra.t()
  defp sequence([], _previous), do: Algebra.empty()

  defp sequence([item | rest], previous) do
    Algebra.concat([
      glue(previous, opening(item)),
      render(item),
      sequence(rest, closing(item))
    ])
  end

  @spec render(item()) :: Algebra.t()
  defp render(token) when is_binary(token), do: Algebra.string(token)

  defp render({open, inner, close}) do
    body = Algebra.concat(Algebra.break(""), sequence(inner, nil))

    Algebra.group(
      Algebra.concat([
        Algebra.string(open),
        Algebra.nest(body, @indent),
        Algebra.break(""),
        tail(close)
      ])
    )
  end

  @spec tail(binary() | nil) :: Algebra.t()
  defp tail(nil), do: Algebra.empty()
  defp tail(close), do: Algebra.string(close)

  @spec glue(binary() | nil, binary()) :: Algebra.t()
  defp glue(nil, _next), do: Algebra.empty()
  defp glue(",", _next), do: Algebra.break(" ")
  defp glue(_previous, next) when next in @breaks_before, do: Algebra.break(" ")

  defp glue(previous, next) do
    if Spacing.space?(previous, next), do: Algebra.string(" "), else: Algebra.empty()
  end

  @spec opening(item()) :: binary()
  defp opening(token) when is_binary(token), do: token
  defp opening({open, _inner, _close}), do: open

  @spec closing(item()) :: binary()
  defp closing(token) when is_binary(token), do: token
  defp closing({_open, _inner, close}) when is_binary(close), do: close
  defp closing({open, inner, nil}), do: List.last(Enum.map(inner, &closing/1), open)
end
