defmodule Tptp.Statement.Annotated do
  @moduledoc """
  An annotated formula: `fof(name, role, formula, source, info).`

  ## Why `source` and `info` are kept

  They are the whole of TSTP. A derivation is a set of annotated formulae whose
  `source` records the inference that produced each one and the parents it came
  from, and a library that dropped them could read problems but not proofs.
  Keeping them costs nothing here, because they are already parsed — the grammar
  covers `<source>` and `<useful_info>` in full — and it is what makes proof
  reconstruction a walk rather than a second parser.

  ## What is not interpreted

  `role` is the raw node, not an atom from a closed set: `<formula_role>` is a
  `<lower_word>` in the `::=` grammar and only *recommended* to be one of thirteen
  by the `:==` rules, so rejecting an unusual one is a lint decision, not a parse
  decision. Likewise `formula` is the unelaborated subtree — for a THF statement it
  may be a type, a term or a formula, and the grammar does not say which.
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
end
