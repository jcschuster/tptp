defmodule Tptp.Printer.Pretty do
  @moduledoc """
  Prints a CST to a chosen width, breaking lines where a formula is too long to fit.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p&q).")
      iex> Tptp.Printer.Pretty.to_string(statement)
      "fof(a, axiom, p & q)."

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p&q).")
      iex> Tptp.Printer.Pretty.to_string(statement, width: 12)
      "fof(\\n  a,\\n  axiom,\\n  p\\n  & q\\n)."

  which is to say, at a width of twelve columns:

      fof(
        a,
        axiom,
        p
        & q
      ).

  ## The contract, and how it is met

  **The tokens are exactly the canonical printer's tokens.** Same sequence, same
  spelling, in the same order; only the white space between them differs. That is
  not a property this module tries to preserve — it is the input it starts from. It
  asks `Tptp.Printer.Canonical` for the token list and then decides only where the
  line breaks go, so the round-trip guarantee is inherited rather than re-earned,
  and a change to the grammar cannot make the two printers disagree.

  Line breaking is `Inspect.Algebra`, the Wadler/Lindig algebra in the standard
  library. No dependency, and the layout is optimal rather than greedy: a group is
  flattened when its *whole* contents fit, so `p(a, b, c)` does not break its first
  argument only to discover the third would have fitted anyway.

  ## The structure is the brackets

  Everything below is derived from one observation: the token stream of a statement
  has balanced `(`, `[` and `{`. `[.]`, `<.>`, `{.}` and `(.)` are single tokens by
  the time the lexer is done, quoted atoms and distinct objects are single tokens
  too, and the grammar guarantees the rest. So bracket matching over the flat token
  list recovers the nesting, and no second traversal of the CST is needed.

  Each bracket region becomes one group with a two-space indent. Whether it breaks
  is decided for it alone, so an argument that does not fit does not force its
  siblings apart. The internal `item` type is that recovery: a bare token, or an
  opener with its contents and its closer. The closer is `nil` only for brackets
  that do not balance, which the grammar makes unreachable and which is handled
  anyway rather than crashing a printer.

  ## Where the breaks are allowed

    * **After a comma.** One element per line when a list has to break.
    * **Before a binary connective**, never after — so a broken chain reads

          p(X)
          & q(X)
          & r(X)

      with the connective starting the line, which is where TPTP output has always
      put it and where it is easiest to scan a long conjunction for the operator
      that differs. `@` is included, so a long THF application spine breaks the
      same way; so is `>`, so a long type signature does.
    * **Just inside a bracket**, which is what lets a region open up at all.

  Nowhere else. In particular there is no break inside a quoted atom or a distinct
  object, because those are one token and this module never looks inside a token.

  ## White space is always safe

  Every junction that may break may also carry a space, and every junction that may
  not break still gets the spacing `Tptp.Printer.Spacing` prescribes. Adding white
  space between two TPTP tokens can never merge or split them — the maximal-munch
  cases that could (`~` beside `|`) are the ones `Spacing` already separates — so
  breaking is never the thing that changes what a file means.
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
