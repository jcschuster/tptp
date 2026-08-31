defmodule Tptp.Printer.Canonical do
  @moduledoc """
  Prints a CST back to TPTP, deterministically and without comments.

      iex> {:ok, file, []} = Tptp.from_string("fof( a , axiom , p(X)&q ).")
      iex> Tptp.Printer.Canonical.to_string(file)
      "fof(a, axiom, p(X) & q).\\n"

  ## The contract

  `from_string(print(tree))` has the same shape as `tree`. Shape means
  `Tptp.Node.shape/1` — kinds, texts and structure, with every offset erased,
  because printing moves everything. That property is checked over the whole TPTP
  library, and it is the one that has to hold before any consumer can rely on this.

  ## It does not re-parenthesise, and does not need to

  The obvious way to print a formula language with no precedence table is to
  parenthesise everything. That is not necessary here, because the tree already
  says where the parentheses were: `<fof_unitary_formula> ::= (<fof_logic_formula>)`
  is kept as a node rather than spliced away, precisely so that `a | (b | c)` and
  `(a | b) | c` are different trees. So the printer neither adds parentheses nor
  drops them — it writes down what the tree says — and round-tripping follows from
  faithfulness rather than from over-bracketing.

  ## The spellings are generated

  `Tptp.Printer.Shapes` says how each node kind is written, and it comes from the
  same BNF as the parser in the same `mix tptp.gen` run. A hand-written printer
  would agree with the grammar right up until someone regenerated the grammar.

  ## An empty collection is not a leaf

  `[]` is a `general_list` with no children, and a `~` connective is a leaf with no
  children and no text. Both are childless, so the shape is consulted before the
  leaf case rather than after — the other order prints every empty list as nothing,
  which is how `inference(r, [], [a])` came out as `inference(r,, [a])`.

  ## Spacing

  Enough to be legible, never enough to change the tokens. Nothing before `)`, `]`,
  `}`, `,`, `.` or `:`; nothing after `(`, `[` or `{`; nothing before an opening
  bracket that follows a word or a prefix operator, so `p(a)` and `![X]:` come out
  as they went in. Everywhere else a single space, which is what keeps two adjacent
  operators from munching into a third.
  """

  alias Tptp.Node
  alias Tptp.Printer.Shapes
  alias Tptp.Printer.Spacing
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include
  alias Tptp.Token

  @typedoc "Anything this printer knows how to write."
  @type printable :: Node.t() | Tptp.Statement.t() | Tptp.File.t() | Tptp.Unit.t()

  @doc """
  Print as iodata, which is what to hand `IO.write/2` or `:file.write/2`.

  Building iodata rather than a binary is the difference between one allocation per
  fragment and one copy of the whole file per concatenation, and a 455 MB axiom set
  makes that difference visible.
  """
  @spec to_iodata(printable()) :: iodata()
  def to_iodata(%Node{} = node), do: node |> tokens() |> Spacing.join()

  def to_iodata(%Annotated{} = statement), do: statement |> tokens() |> Spacing.join()
  def to_iodata(%Include{} = statement), do: statement |> tokens() |> Spacing.join()

  def to_iodata(%Tptp.File{} = file), do: Enum.map(file.statements, &[to_iodata(&1), ?\n])

  def to_iodata(%Tptp.Unit{} = unit) do
    unit
    |> Tptp.Unit.statements()
    |> Enum.map(fn {_id, statement} -> [to_iodata(statement), ?\n] end)
  end

  @doc """
  Print as a binary.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("cnf(c,axiom,p|~q).")
      iex> Tptp.Printer.Canonical.to_string(statement)
      "cnf(c, axiom, p | ~q)."
  """
  @spec to_string(printable()) :: binary()
  def to_string(printable), do: printable |> to_iodata() |> IO.iodata_to_binary()

  @doc """
  Write a file's canonical form to disk.
  """
  @spec to_file(printable(), Path.t()) :: :ok | {:error, File.posix()}
  def to_file(printable, path), do: File.write(path, to_iodata(printable))

  @doc """
  The token sequence a printable spells out, before any white space is chosen.

  Public because `Tptp.Printer.Pretty` starts here: it decides only where the line
  breaks go, so it must be spelling the same tokens as this module rather than a
  parallel set that could drift from them.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p&q).")
      iex> Tptp.Printer.Canonical.tokens(statement)
      ["fof", "(", "a", ",", "axiom", ",", "p", "&", "q", ")", "."]
  """
  @spec tokens(printable()) :: [binary()]
  def tokens(%Annotated{} = statement) do
    [Atom.to_string(statement.language), "("] ++
      tokens(statement.name) ++
      [","] ++
      tokens(statement.role) ++
      [","] ++ tokens(statement.formula) ++ annotations(statement) ++ [")", "."]
  end

  def tokens(%Include{} = statement) do
    ["include", "("] ++ tokens(statement.file_name) ++ selection(statement) ++ [")", "."]
  end

  def tokens(%Node{children: [], text: text}) when is_binary(text), do: [text]

  def tokens(%Node{kind: kind, children: children}) do
    case Shapes.shape(kind, length(children)) do
      {:separated, separator} ->
        children |> Enum.map(&tokens/1) |> Enum.intersperse([separator]) |> Enum.concat()

      nil ->
        unshaped(kind, children)

      items ->
        fill(items, children)
    end
  end

  defp unshaped(kind, []), do: List.wrap(Token.spelling(kind))
  defp unshaped(_kind, children), do: Enum.flat_map(children, &tokens/1)

  defp fill([], _children), do: []
  defp fill([:slot | items], [child | children]), do: tokens(child) ++ fill(items, children)
  defp fill([:slot | items], []), do: fill(items, [])
  defp fill([literal | items], children), do: [literal | fill(items, children)]

  defp annotations(%Annotated{source: nil}), do: []

  defp annotations(%Annotated{source: source, info: nil}), do: [","] ++ tokens(source)

  defp annotations(%Annotated{source: source, info: info}) do
    [","] ++ tokens(source) ++ [","] ++ tokens(info)
  end

  defp selection(%Include{selection: nil}), do: []

  defp selection(%Include{selection: selection, space_name: nil}), do: [","] ++ tokens(selection)

  defp selection(%Include{selection: selection, space_name: space}) do
    [","] ++ tokens(selection) ++ [","] ++ tokens(space)
  end
end
