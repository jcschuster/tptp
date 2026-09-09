defmodule Tptp.Lint.Rule do
  @moduledoc """
  The behaviour implemented by a lint rule.

  A rule declares its diagnostic code, its default severity and a description, and
  implements one or both callbacks:

    * `c:visit/3` is invoked for every node of every statement during the traversal
      performed by `Tptp.Lint`. Local conditions belong here: a role outside the
      permitted set, a `$`-word outside the vocabulary.
    * `c:review/2` runs after the traversal, against the symbol table it produced.
      Conditions requiring more than one statement belong here: an undeclared
      symbol, a duplicate name, an absent inference parent.

  ## Single traversal

  `Tptp.Lint` traverses once and offers each node to every enabled rule, so the
  cost of an additional rule is a function call rather than a further pass. A rule
  per traversal would require eight traversals of a tree that does not fit in
  cache.

  It follows that `c:visit/3` must be inexpensive and must not itself traverse. A
  rule requiring a subtree is either asking for something the node determines, or
  belongs in `c:review/2` where the table is available.

  ## Severity

  `c:severity/0` is the rule's default, which the caller may override per code. A
  rule that applies to conforming library files must not report an error; a corpus
  test enforces this. `:info` is appropriate where the finding is a property of the
  file rather than a defect in it.
  """

  alias Tptp.Diagnostic
  alias Tptp.Lint.Context
  alias Tptp.Lint.Table
  alias Tptp.Node

  @doc "The diagnostic code this rule raises, `\"TPTP0401\"` and the like."
  @callback code() :: binary()

  @doc "What the rule thinks its findings are worth, before any caller override."
  @callback severity() :: Diagnostic.severity()

  @doc """
  A one-line description, shown when a caller lists the available rules.
  """
  @callback describe() :: binary()

  @doc """
  Look at one node. Called for every node of every statement, so keep it cheap.
  """
  @callback visit(Node.t(), Context.t(), term()) :: [Diagnostic.t()]

  @doc """
  Look at the whole unit once the traversal is done.
  """
  @callback review(Table.t(), Context.t()) :: [Diagnostic.t()]

  @optional_callbacks visit: 3, review: 2
end
