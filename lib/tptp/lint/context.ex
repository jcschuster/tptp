defmodule Tptp.Lint.Context do
  @moduledoc """
  The position of a node within the statement being traversed.

  A `Tptp.Node` carries no parent pointer and no reference to its statement, since
  storing either on every node would be prohibitive at the scale the traversal
  operates on. The traversal carries this structure alongside instead, rebuilt per
  statement rather than per node.

  `whole` records the subject of the traversal: a complete `Tptp.Unit` with
  includes resolved, or a single `Tptp.File` that may be one part of a problem. A
  rule whose question concerns the problem rather than the statement — whether any
  proof obligation is stated — must decline when this is `false`, since the answer
  may lie in an unread file.

  `slot` records which part of the statement the traversal is within: `:formula`,
  `:name`, `:role`, `:source` or `:info`. It allows a rule concerned with symbols
  to disregard the annotations, where the same words denote something else — `file`
  in a `<source>` is a keyword, and an atom in a `<general_term>` is a label rather
  than a functor.
  """

  alias Tptp.Span
  alias Tptp.Statement

  @enforce_keys [:file, :statement, :slot]
  defstruct [:file, :statement, :slot, :path, depth: 0, whole: false]

  @typedoc "Which part of the statement the walk is currently inside."
  @type slot :: :name | :role | :formula | :source | :info | :file_name | :selection

  @typedoc "Where the fused walk currently is: which file, which statement, and which slot of it."
  @type t :: %__MODULE__{
          file: Span.file_id(),
          statement: Statement.t(),
          slot: slot(),
          path: Path.t() | nil,
          depth: non_neg_integer(),
          whole: boolean()
        }

  @doc """
  The language the statement is written in, or `:include`.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("cnf(a,axiom,p).")
      iex> context = %Tptp.Lint.Context{file: 0, statement: statement, slot: :formula}
      iex> Tptp.Lint.Context.language(context)
      :cnf
  """
  @spec language(t()) :: Tptp.Input.language()
  def language(%__MODULE__{statement: %Statement.Annotated{language: language}}), do: language
  def language(%__MODULE__{statement: %Statement.Include{}}), do: :include

  @doc """
  The role of the statement, or `nil` for an `include`.
  """
  @spec role(t()) :: binary() | nil
  def role(%__MODULE__{statement: %Statement.Annotated{role: role}}), do: role.text
  def role(%__MODULE__{statement: %Statement.Include{}}), do: nil

  @doc """
  A span in the file the walk is reading, for a node the rule wants to report.
  """
  @spec span(t(), Tptp.Node.t()) :: Span.t()
  def span(%__MODULE__{file: file}, node), do: Span.new(file, node.off, node.len)
end
