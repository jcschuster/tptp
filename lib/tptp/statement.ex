defmodule Tptp.Statement do
  @moduledoc """
  The two shapes a parsed TPTP statement can take.

  `<TPTP_input> ::= <annotated_formula> | <include>`, so there are exactly two, and
  they are separate structs rather than one struct with a tag because they share no
  fields worth sharing and a consumer almost always wants one or the other.

  `Tptp.Statement.Annotated` is the `thf`/`tff`/`tcf`/`fof`/`cnf`/`tpi` form.
  `Tptp.Statement.Include` is the `include` directive, which is what makes a file
  set a graph rather than a list.
  """

  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include

  @typedoc "Either kind of top-level input the grammar admits."
  @type t :: Annotated.t() | Include.t()

  @doc """
  The statement's extent, as a span in the file it was read from.
  """
  @spec span(t(), Tptp.Span.file_id()) :: Tptp.Span.t()
  def span(statement, file \\ 0)

  def span(%Annotated{} = statement, file), do: Tptp.Span.new(file, statement.off, statement.len)
  def span(%Include{} = statement, file), do: Tptp.Span.new(file, statement.off, statement.len)

  @doc """
  The bytes the statement covers, terminating `.` included.
  """
  @spec text(t(), binary()) :: binary()
  def text(%Annotated{} = statement, source),
    do: binary_part(source, statement.off, statement.len)

  def text(%Include{} = statement, source), do: binary_part(source, statement.off, statement.len)

  @doc """
  Every CST subtree the statement holds, in source order.

  A statement is a handful of named slots rather than one tree, because its shape
  is fixed by the grammar and naming the slots is more useful than making a caller
  index into children. This is the escape hatch for the operations that genuinely
  want all of them — walking for symbols, checking span invariants, detaching.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> statement |> Tptp.Statement.roots() |> Enum.map(& &1.kind)
      [:name, :formula_role, :constant]
  """
  @spec roots(t()) :: [Tptp.Node.t()]
  def roots(%Annotated{} = statement) do
    [statement.name, statement.role, statement.formula] ++
      List.wrap(statement.source) ++ List.wrap(statement.info)
  end

  def roots(%Include{} = statement) do
    [statement.file_name] ++ List.wrap(statement.selection) ++ List.wrap(statement.space_name)
  end

  @doc """
  A copy whose every leaf owns its bytes, so the file it came from can be collected.

  See `Tptp.Node.detach/1` for why this is not the default.
  """
  @spec detach(t()) :: t()
  def detach(%Annotated{} = statement) do
    %{
      statement
      | name: Tptp.Node.detach(statement.name),
        role: Tptp.Node.detach(statement.role),
        formula: Tptp.Node.detach(statement.formula),
        source: statement.source && Tptp.Node.detach(statement.source),
        info: statement.info && Tptp.Node.detach(statement.info)
    }
  end

  def detach(%Include{} = statement) do
    %{
      statement
      | file_name: Tptp.Node.detach(statement.file_name),
        selection: statement.selection && Tptp.Node.detach(statement.selection),
        space_name: statement.space_name && Tptp.Node.detach(statement.space_name)
    }
  end
end
