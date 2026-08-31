defmodule Tptp.Bnf.OracleTable do
  @moduledoc """
  The BNF's token layer as anchored regular expressions. Generated; do not edit.

  `mix tptp.gen` writes this from `SyntaxBNF-v9.3.1.2`, one entry per
  `::-` and `:::` rule, with every `<name>` reference inlined. It exists so that
  the hand-written `Tptp.Lexer` has something independent to be checked against;
  see `Tptp.Bnf.Oracle` for why that is worth generating and what the checking
  does and does not prove.
  """

  @typedoc """
  A nonterminal defined by a `::-` or `:::` rule.

  One of: `alpha`, `alpha_numeric`, `arrow`, `back_quote`, `back_quoted`, `comment`, `comment_block`, `comment_line`, `decimal_exponent`, `decimal_fraction`, `distinct_object`, `do_char`, `dollar`, `dollar_dollar_word`, `dollar_word`, `dot`, `double_quote`, `exp_integer`, `exponent`, `hash`, `integer`, `integer_digits`, `less_sign`, `lower_alpha`, `lower_word`, `non_zero_numeric`, `not_star_slash`, `numeric`, `percentage_sign`, `plus`, `positive_integer`, `printable_char`, `rational`, `real`, `sign`, `signed_exp_integer`, `signed_integer`, `signed_rational`, `signed_real`, `single_quote`, `single_quoted`, `slash`, `slash_char`, `slosh`, `slosh_char`, `sq_char`, `star`, `underscore`, `unsigned_integer`, `unsigned_rational`, `unsigned_real`, `upper_alpha`, `upper_word`, `viewable_char`, `vline`, `zero_numeric`.
  """
  @type name :: binary()

  @patterns %{
    "alpha" => Regex.compile!("\\A(?:((?:[a-z])|(?:[A-Z])))\\z"),
    "alpha_numeric" => Regex.compile!("\\A(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))\\z"),
    "arrow" => Regex.compile!("\\A(?:[>])\\z"),
    "back_quote" => Regex.compile!("\\A(?:[`])\\z"),
    "back_quoted" =>
      Regex.compile!("\\A(?:(?:[`])(?:(?:[A-Z])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*))\\z"),
    "comment" =>
      Regex.compile!(
        "\\A(?:(?:(?:[%])(?:.)*)|(?:(?:[/])(?:[*])(?:([^*]*[*][*]*[^/*])*[^*]*)(?:[*])(?:[*])*(?:[/])))\\z"
      ),
    "comment_block" =>
      Regex.compile!(
        "\\A(?:(?:[/])(?:[*])(?:([^*]*[*][*]*[^/*])*[^*]*)(?:[*])(?:[*])*(?:[/]))\\z"
      ),
    "comment_line" => Regex.compile!("\\A(?:(?:[%])(?:.)*)\\z"),
    "decimal_exponent" =>
      Regex.compile!(
        "\\A(?:((?:(?:[0-9])(?:[0-9])*)|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*)))(?:[Ee])(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*))))\\z"
      ),
    "decimal_fraction" =>
      Regex.compile!(
        "\\A(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*))\\z"
      ),
    "distinct_object" =>
      Regex.compile!(
        "\\A(?:(?:[\"])(?:([\\40-\\41\\43-\\133\\135-\\176]|([\\\\][\"\\\\])))*(?:[\"]))\\z"
      ),
    "do_char" => Regex.compile!("\\A(?:([\\40-\\41\\43-\\133\\135-\\176]|([\\\\][\"\\\\])))\\z"),
    "dollar" => Regex.compile!("\\A(?:[$])\\z"),
    "dollar_dollar_word" =>
      Regex.compile!("\\A(?:(?:[$])(?:[$])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*)\\z"),
    "dollar_word" =>
      Regex.compile!("\\A(?:(?:[$])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*)\\z"),
    "dot" => Regex.compile!("\\A(?:[.])\\z"),
    "double_quote" => Regex.compile!("\\A(?:[\"])\\z"),
    "exp_integer" =>
      Regex.compile!("\\A(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*)))\\z"),
    "exponent" => Regex.compile!("\\A(?:[Ee])\\z"),
    "hash" => Regex.compile!("\\A(?:[#])\\z"),
    "integer" =>
      Regex.compile!(
        "\\A(?:((?:(?:[+-])(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*))))|(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))))\\z"
      ),
    "integer_digits" => Regex.compile!("\\A(?:(?:[0-9])(?:[0-9])*)\\z"),
    "less_sign" => Regex.compile!("\\A(?:[<])\\z"),
    "lower_alpha" => Regex.compile!("\\A(?:[a-z])\\z"),
    "lower_word" =>
      Regex.compile!("\\A(?:(?:[a-z])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*)\\z"),
    "non_zero_numeric" => Regex.compile!("\\A(?:[1-9])\\z"),
    "not_star_slash" => Regex.compile!("\\A(?:([^*]*[*][*]*[^/*])*[^*]*)\\z"),
    "numeric" => Regex.compile!("\\A(?:[0-9])\\z"),
    "percentage_sign" => Regex.compile!("\\A(?:[%])\\z"),
    "plus" => Regex.compile!("\\A(?:[+])\\z"),
    "positive_integer" => Regex.compile!("\\A(?:(?:[1-9])(?:[0-9])*)\\z"),
    "printable_char" => Regex.compile!("\\A(?:.)\\z"),
    "rational" =>
      Regex.compile!(
        "\\A(?:((?:(?:[+-])(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:(?:[/]))(?:(?:[1-9])(?:[0-9])*)))|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:(?:[/]))(?:(?:[1-9])(?:[0-9])*))))\\z"
      ),
    "real" =>
      Regex.compile!(
        "\\A(?:((?:(?:[+-])(?:((?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*))|(?:((?:(?:[0-9])(?:[0-9])*)|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*)))(?:[Ee])(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*)))))))|(?:((?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*))|(?:((?:(?:[0-9])(?:[0-9])*)|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*)))(?:[Ee])(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*))))))))\\z"
      ),
    "sign" => Regex.compile!("\\A(?:[+-])\\z"),
    "signed_exp_integer" => Regex.compile!("\\A(?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))\\z"),
    "signed_integer" => Regex.compile!("\\A(?:(?:[+-])(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*))))\\z"),
    "signed_rational" =>
      Regex.compile!(
        "\\A(?:(?:[+-])(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:(?:[/]))(?:(?:[1-9])(?:[0-9])*)))\\z"
      ),
    "signed_real" =>
      Regex.compile!(
        "\\A(?:(?:[+-])(?:((?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*))|(?:((?:(?:[0-9])(?:[0-9])*)|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*)))(?:[Ee])(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*)))))))\\z"
      ),
    "single_quote" => Regex.compile!("\\A(?:['])\\z"),
    "single_quoted" =>
      Regex.compile!(
        "\\A(?:(?:['])(?:([\\40-\\46\\50-\\133\\135-\\176]|([\\\\]['\\\\])))(?:([\\40-\\46\\50-\\133\\135-\\176]|([\\\\]['\\\\])))*(?:[']))\\z"
      ),
    "slash" => Regex.compile!("\\A(?:(?:[/]))\\z"),
    "slash_char" => Regex.compile!("\\A(?:[/])\\z"),
    "slosh" => Regex.compile!("\\A(?:(?:[\\\\]))\\z"),
    "slosh_char" => Regex.compile!("\\A(?:[\\\\])\\z"),
    "sq_char" => Regex.compile!("\\A(?:([\\40-\\46\\50-\\133\\135-\\176]|([\\\\]['\\\\])))\\z"),
    "star" => Regex.compile!("\\A(?:[*])\\z"),
    "underscore" => Regex.compile!("\\A(?:[_])\\z"),
    "unsigned_integer" => Regex.compile!("\\A(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))\\z"),
    "unsigned_rational" =>
      Regex.compile!(
        "\\A(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:(?:[/]))(?:(?:[1-9])(?:[0-9])*))\\z"
      ),
    "unsigned_real" =>
      Regex.compile!(
        "\\A(?:((?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*))|(?:((?:(?:[0-9])(?:[0-9])*)|(?:(?:((?:[0])|(?:(?:[1-9])(?:[0-9])*)))(?:[.])(?:(?:[0-9])(?:[0-9])*)))(?:[Ee])(?:((?:(?:[+-])(?:(?:[0-9])(?:[0-9])*))|(?:(?:[0-9])(?:[0-9])*))))))\\z"
      ),
    "upper_alpha" => Regex.compile!("\\A(?:[A-Z])\\z"),
    "upper_word" =>
      Regex.compile!("\\A(?:(?:[A-Z])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*)\\z"),
    "viewable_char" => Regex.compile!("\\A(?:[.\\n])\\z"),
    "vline" => Regex.compile!("\\A(?:[|])\\z"),
    "zero_numeric" => Regex.compile!("\\A(?:[0])\\z")
  }

  @doc "Every nonterminal the token layer defines, sorted."
  @spec names() :: [name()]
  def names,
    do: [
      "alpha",
      "alpha_numeric",
      "arrow",
      "back_quote",
      "back_quoted",
      "comment",
      "comment_block",
      "comment_line",
      "decimal_exponent",
      "decimal_fraction",
      "distinct_object",
      "do_char",
      "dollar",
      "dollar_dollar_word",
      "dollar_word",
      "dot",
      "double_quote",
      "exp_integer",
      "exponent",
      "hash",
      "integer",
      "integer_digits",
      "less_sign",
      "lower_alpha",
      "lower_word",
      "non_zero_numeric",
      "not_star_slash",
      "numeric",
      "percentage_sign",
      "plus",
      "positive_integer",
      "printable_char",
      "rational",
      "real",
      "sign",
      "signed_exp_integer",
      "signed_integer",
      "signed_rational",
      "signed_real",
      "single_quote",
      "single_quoted",
      "slash",
      "slash_char",
      "slosh",
      "slosh_char",
      "sq_char",
      "star",
      "underscore",
      "unsigned_integer",
      "unsigned_rational",
      "unsigned_real",
      "upper_alpha",
      "upper_word",
      "viewable_char",
      "vline",
      "zero_numeric"
    ]

  @doc """
  The anchored pattern for one nonterminal.

  Raises for a name the BNF does not define, because a typo in a test should
  fail rather than silently check nothing.
  """
  @spec pattern(name()) :: Regex.t()
  def pattern(name), do: Map.fetch!(@patterns, name)

  @doc """
  Whether `text` is exactly one `name`, start to end.

  Anchored on both sides: a token that only starts with a `<lower_word>` is not
  a `<lower_word>`, and the whole point of the oracle is to catch a lexer that
  stopped a byte early.
  """
  @spec matches?(name(), binary()) :: boolean()
  def matches?(name, text) when is_binary(text), do: Regex.match?(pattern(name), text)

  @doc "Which of the token nonterminals `text` is, if any."
  @spec classify(binary()) :: [name()]
  def classify(text) when is_binary(text) do
    for name <- names(), matches?(name, text), do: name
  end
end
