defmodule Tptp.Lint.Rule do
  @moduledoc """
  What a lint rule is.

  A rule declares its code, its severity and the dialects it applies to, and then
  implements one or both of two callbacks:

    * `c:visit/3` sees every node of every statement, during the one traversal
      `Tptp.Lint` makes. This is where anything local lives — a role that is not one
      of the thirteen, a `$`-word that is not in the vocabulary, a construct that
      does not belong in its dialect.
    * `c:review/2` runs afterwards, handed the symbol table the traversal built.
      This is where anything that needs more than one statement lives — an
      undeclared symbol, a duplicate name, a parent that is not there.

  ## Why one traversal

  A rule per walk is the obvious design and the wrong one: ten rules over a 455 MB
  axiom set is ten traversals of 27 million nodes, and the tree does not fit in
  cache. `Tptp.Lint` walks once and offers each node to every enabled rule, so the
  cost of a rule is a function call rather than a pass.

  It follows that `c:visit/3` must be cheap and must not walk. A rule that needs to
  look at a subtree is either asking for something the node itself can answer, or
  it belongs in `c:review/2` where it can look at the table instead.

  ## Severity is a default, not a decree

  `c:severity/0` is what the rule thinks; the caller overrides per code. A rule
  that fires on conforming library files must not report an error, and there is a
  corpus test that says so. `:info` is for a rule whose finding is a fact about the
  file rather than a complaint about it.
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
