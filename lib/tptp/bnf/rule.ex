defmodule Tptp.Bnf.Rule do
  @moduledoc """
  One rule read out of the vendored `SyntaxBNF` file.

  `alternatives` is populated only for `::=` and `:==` rules; token rules (`::-`)
  and character classes (`:::`) keep their `raw` regex text instead, because that
  is what the generated conformance oracle needs.
  """

  @typedoc """
  A single element of an alternative.

  `{:ref, name}` is a `<name>` reference — it may resolve to either a nonterminal
  or, when `name` is defined by a `::-` or `:::` rule, a terminal. `{:literal,
  text}` is a run of literal characters that `Tptp.Bnf.Generator` splits into
  terminals against `Tptp.Token.spellings/0`.
  """
  @type symbol :: {:ref, binary()} | {:literal, binary()}

  @typedoc "One rule: its left-hand side, which of the four separators introduced it, and the alternatives parsed out of it."
  @type t :: %__MODULE__{
          lhs: binary(),
          separator: binary(),
          raw: binary(),
          line: pos_integer(),
          alternatives: [[symbol()]] | nil
        }

  @enforce_keys [:lhs, :separator, :raw, :line]
  defstruct [:lhs, :separator, :raw, :line, alternatives: nil]
end
