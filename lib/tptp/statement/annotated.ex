defmodule Tptp.Statement.Annotated do
  @moduledoc """
  An annotated formula: `fof(name, role, formula, source, info).`

  ## Retention of `source` and `info`

  These fields constitute the TSTP. A derivation is a set of annotated formulae
  whose `source` records the inference producing each one and the parents it was
  derived from, so a reader discarding them can read problems but not proofs. They
  are already parsed, the grammar covering `<source>` and `<useful_info>` in full,
  so retaining them allows proof reconstruction to be a traversal rather than a
  second parse.

  ## Uninterpreted fields

  `role` is the node as parsed rather than an atom from a closed set:
  `<formula_role>` is a `<lower_word>` in the `::=` grammar and is restricted to
  the named set only by the `:==` conditions, so rejecting an unrecognised role is
  a lint decision rather than a parse decision. Likewise `formula` is the
  unelaborated subtree; in a THF statement it may be a type, a term or a formula,
  and the grammar does not distinguish them.
  """

  alias Tptp.Node

  @enforce_keys [:language, :name, :role, :formula, :off, :len]
  defstruct [:language, :name, :role, :formula, :source, :info, :off, :len]

  @typedoc "One annotated formula, with its four grammatical slots kept apart as separate subtrees."
  @type t :: %__MODULE__{
          language: :thf | :tff | :tcf | :fof | :cnf | :tpi,
          name: Node.t(),
          role: Node.t(),
          formula: Node.t(),
          source: Node.t() | nil,
          info: Node.t() | nil,
          off: non_neg_integer(),
          len: non_neg_integer()
        }

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # The formula is a whole tree; see `Tptp.Node`'s implementation for why that is not
    # printed. `Tptp.Statement.text/2` renders the statement itself from its source.
    @impl true
    def inspect(statement, opts) do
      concat([
        "#Tptp.Statement.Annotated<",
        to_doc(statement.language, opts),
        " ",
        to_doc(statement.name.text, opts),
        ": ",
        statement.role.text,
        ", ",
        "#{statement.off}..#{statement.off + statement.len}",
        ">"
      ])
    end
  end
end
