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

  A sub-role, `<lower_word>-<general_term>` as in `interpretation-domains`, is the
  second alternative of the same rule: a `:formula_role` node with `text: nil` and
  two children. `role_word/1` and `subrole/1` read either form, so a consumer
  asking for the role need not know which was written.
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

  @doc """
  The role's `<lower_word>`: the role itself, or the word before the `-` of a
  sub-role.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, p).")
      iex> Tptp.Statement.Annotated.role_word(statement)
      "axiom"

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, interpretation-domains, p).")
      iex> Tptp.Statement.Annotated.role_word(statement)
      "interpretation"
  """
  @spec role_word(t()) :: binary()
  def role_word(%__MODULE__{role: %Node{text: word}}) when is_binary(word), do: word
  def role_word(%__MODULE__{role: %Node{children: [%Node{text: word} | _rest]}}), do: word

  @doc """
  The `<general_term>` of a sub-role, or `nil` for a plain role.

  The term is uninterpreted, as `source` and `info` are: the BNF names `domains`
  and `mappings` for an `interpretation` and `datatype` for a `type` as examples
  rather than as a closed set.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("tff(d, type-datatype, nat: $tType).")
      iex> Tptp.Statement.Annotated.subrole(statement).text
      "datatype"

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, p).")
      iex> Tptp.Statement.Annotated.subrole(statement)
      nil
  """
  @spec subrole(t()) :: Node.t() | nil
  def subrole(%__MODULE__{role: %Node{children: [_word, term]}}), do: term
  def subrole(%__MODULE__{}), do: nil

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # The formula is a whole tree; see `Tptp.Node`'s implementation for why that is not
    # printed. `Tptp.Statement.text/2` renders the statement itself from its source.
    # A sub-role prints as its word alone: `role_word/1` rather than `role.text`,
    # which is `nil` there.
    @impl true
    def inspect(statement, opts) do
      concat([
        "#Tptp.Statement.Annotated<",
        to_doc(statement.language, opts),
        " ",
        to_doc(statement.name.text, opts),
        ": ",
        @for.role_word(statement),
        ", ",
        "#{statement.off}..#{statement.off + statement.len}",
        ">"
      ])
    end
  end
end
