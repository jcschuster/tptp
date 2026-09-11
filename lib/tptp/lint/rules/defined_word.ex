defmodule Tptp.Lint.Rules.DefinedWord do
  @moduledoc """
  A `$`-word outside the vocabularies named by the `:==` conditions.

  The `$` prefix is reserved to the TPTP language, so `$wibble` is not a symbol a
  problem may introduce. `$$wibble` is the system-specific form and is not checked.
  The vocabularies come from `Tptp.Bnf.Vocabulary`, generated from the same BNF as
  the grammar, so the two cannot diverge.

  A warning rather than an error: an unrecognised `$`-word is usually a
  misspelling, but a prover extension not yet incorporated into the BNF is also
  possible.

  ## Coverage over the TPTP library

  This rule reports nothing on TPTP v9.3.1, and reported 76 occurrences across five
  modal system names under the BNF up to v9.3.1.2, whose `<ntf_modal_system>` named
  six systems and `<ntf_modal_axiom>` six axioms where the Non-classical Logics
  section of the TPTP language page stated sixteen and ten. v9.3.1.3 completed both
  lists, and their `$`-words reach this rule through `<reserved_word>`, which is
  what it consults.
  """

  @behaviour Tptp.Lint.Rule

  alias Tptp.Diagnostic
  alias Tptp.Lint.Collect
  alias Tptp.Lint.Context
  alias Tptp.Node

  @kinds [:defined_constant, :defined_functor, :defined_type, :dollar_word]

  @impl true
  def code, do: "TPTP0402"

  @impl true
  def severity, do: :warning

  @impl true
  def describe, do: "a $-word outside the TPTP defined vocabulary"

  @impl true
  def visit(%Node{kind: kind, text: word} = node, %Context{} = context, _table)
      when kind in @kinds and is_binary(word) do
    if Collect.known_dollar_word?(word) do
      []
    else
      [
        Diagnostic.new(
          code(),
          severity(),
          Context.span(context, node),
          "#{inspect(word)} is not a defined TPTP word",
          hint:
            "`$` is reserved for the language; use `$$#{String.trim_leading(word, "$")}` " <>
              "for a system-specific word"
        )
      ]
    end
  end

  def visit(_node, _context, _table), do: []
end
