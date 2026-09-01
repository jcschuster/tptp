defmodule Tptp.Lint.Context do
  @moduledoc """
  Where a node is, when a rule is looking at it.

  A `Tptp.Node` knows nothing about its surroundings — it has no parent pointer and
  no idea which statement it is in — because paying for that on 27 million nodes to
  serve nine rules would be the wrong trade. The traversal carries this alongside
  instead, and it is rebuilt per statement rather than per node.

  `whole` says what the walk is over: a whole `Tptp.Unit`, includes resolved, or a
  single `Tptp.File` that may be one fragment of a problem. A rule whose question
  is about the problem rather than about a statement — *is anything being asked
  here?* — has to decline when this is `false`, because the answer may be sitting
  in a file that was never read.

  `slot` is which part of the statement the walk is in: `:formula`, `:name`,
  `:role`, `:source` or `:info`. It is what lets a rule about symbols ignore the
  annotations, where the same words mean something else entirely — `file` in a
  `<source>` is a keyword, and an atom in a `<general_term>` is a label, not a
  functor.
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
