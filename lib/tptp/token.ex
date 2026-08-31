defmodule Tptp.Token do
  @moduledoc """
  The terminal vocabulary of the TPTP grammar.

  This module is the single source of truth shared by three consumers:

    * `Tptp.Bnf.Generator`, which resolves the literal text appearing in `::=` rules
      to terminal atoms when it emits `src/tptp_parser.yrl`;
    * `Tptp.Lexer`, which emits these atoms as token categories;
    * `Tptp.Printer.Canonical`, which turns them back into bytes.

  A token is a plain three-tuple `{category, offset, length}` — never a struct and
  never carrying a binary. `yecc` reads `elem(token, 0)` as the category and
  `elem(token, 1)` as the position, so a parse error reports a byte offset
  directly. Token text is recovered with `binary_part/3` during the CST post-pass,
  which keeps the scan loop free of binary allocation.

  Every atom named here is created at compile time. Nothing in this library ever
  calls `String.to_atom/1` on input; see the `Credo.Check.Warning.NoDynamicAtoms`
  check for the mechanical enforcement.
  """

  @typedoc "A terminal category. Always a compile-time atom."
  @type category :: atom()

  @typedoc "A lexed token: category, byte offset, byte length."
  @type t :: {category(), non_neg_integer(), non_neg_integer()}

  @operators [
    {:gentzen_arrow, "-->"},
    {:big_choice, "@@+"},
    {:big_desc, "@@-"},
    {:iff, "<=>"},
    {:xor, "<~>"},
    {:short_angle, "<.>"},
    {:short_bracket, "[.]"},
    {:short_brace, "{.}"},
    {:short_paren, "(.)"},
    {:big_forall, "!!"},
    {:big_exists, "??"},
    {:big_equal, "@="},
    {:not_equal, "!="},
    {:type_forall, "!>"},
    {:type_exists, "?*"},
    {:choice, "@+"},
    {:desc, "@-"},
    {:implies, "=>"},
    {:impliedby, "<="},
    {:subtype_sign, "<<"},
    {:nor, "~|"},
    {:nand, "~&"},
    {:identical, "=="},
    {:assign, ":="},
    {:forall, "!"},
    {:exists, "?"},
    {:lambda, "^"},
    {:apply, "@"},
    {:tilde, "~"},
    {:equal, "="},
    {:vline, "|"},
    {:ampersand, "&"},
    {:arrow, ">"},
    {:less_sign, "<"},
    {:star, "*"},
    {:plus, "+"},
    {:minus, "-"},
    {:hash, "#"},
    {:slash, "/"},
    {:slosh, "\\"},
    {:lparen, "("},
    {:rparen, ")"},
    {:lbracket, "["},
    {:rbracket, "]"},
    {:lbrace, "{"},
    {:rbrace, "}"},
    {:comma, ","},
    {:dot, "."},
    {:colon, ":"}
  ]

  @statement_keywords [
    {:kw_thf, "thf"},
    {:kw_tff, "tff"},
    {:kw_tcf, "tcf"},
    {:kw_fof, "fof"},
    {:kw_cnf, "cnf"},
    {:kw_tpi, "tpi"},
    {:kw_include, "include"}
  ]

  @source_keywords [
    {:kw_inference, "inference"},
    {:kw_introduced, "introduced"},
    {:kw_file, "file"}
  ]

  @dollar_keywords [
    {:dw_thf, "$thf"},
    {:dw_tff, "$tff"},
    {:dw_fof, "$fof"},
    {:dw_cnf, "$cnf"},
    {:dw_fot, "$fot"},
    {:dw_let, "$let"}
  ]

  @value_categories [
    :lower_word,
    :upper_word,
    :single_quoted,
    :back_quoted,
    :distinct_object,
    :dollar_word,
    :dollar_dollar_word,
    :integer,
    :rational,
    :real
  ]

  @sorted_operators Enum.sort_by(@operators, fn {_a, s} -> -byte_size(s) end)
  @keywords @statement_keywords ++ @source_keywords ++ @dollar_keywords
  @spellings Enum.sort_by(@operators ++ @keywords, fn {_a, s} -> -byte_size(s) end)
  @spelling_map Map.new(@operators ++ @keywords)
  @all_categories Enum.map(@operators ++ @keywords, &elem(&1, 0)) ++ @value_categories

  @punctuation [:lparen, :rparen, :lbracket, :rbracket, :lbrace, :rbrace, :comma, :dot, :colon]

  @doc """
  Every terminal category, operators and keywords and value categories alike.
  """
  @spec categories() :: [category()]
  def categories, do: @all_categories

  @doc """
  Categories whose text must be carried because the category does not determine it.
  """
  @spec value_categories() :: [category()]
  def value_categories, do: @value_categories

  @doc """
  `{category, spelling}` pairs for every fixed-text terminal, longest spelling first.

  Sorted so that a caller matching prefixes in list order gets maximal munch for
  free.
  """
  @spec spellings() :: [{category(), binary()}]
  def spellings, do: @spellings

  @doc """
  Operators and punctuation only, longest spelling first.

  This is what `Tptp.Lexer` generates its scan clauses from. Keywords are excluded
  deliberately: a keyword must be recognised by scanning the whole word and then
  looking it up, never by matching a prefix, or `filename` lexes as `file` followed
  by `name`.
  """
  @spec operators() :: [{category(), binary()}]
  def operators, do: @sorted_operators

  @doc """
  The seven language keywords that open a statement.
  """
  @spec statement_keywords() :: [{category(), binary()}]
  def statement_keywords, do: @statement_keywords

  @doc """
  The four `<source>` keywords, which are also legal `<atomic_word>`s.
  """
  @spec source_keywords() :: [{category(), binary()}]
  def source_keywords, do: @source_keywords

  @doc """
  The six `$`-word keywords, which are also legal `<dollar_word>`s.
  """
  @spec dollar_keywords() :: [{category(), binary()}]
  def dollar_keywords, do: @dollar_keywords

  @doc """
  The fixed text of a category, or `nil` for a value-carrying category.

      iex> Tptp.Token.spelling(:iff)
      "<=>"
      iex> Tptp.Token.spelling(:lower_word)
      nil
  """
  @spec spelling(category()) :: binary() | nil
  def spelling(category) when is_atom(category), do: Map.get(@spelling_map, category)

  @doc """
  Whether a category is pure punctuation, and so dropped from the CST.

      iex> Tptp.Token.punctuation?(:comma)
      true
      iex> Tptp.Token.punctuation?(:ampersand)
      false
  """
  @spec punctuation?(category()) :: boolean()
  def punctuation?(category) when is_atom(category), do: category in @punctuation

  @doc """
  The category for a literal spelling as it appears in the BNF, or `nil`.

      iex> Tptp.Token.category_for("~|")
      :nor
      iex> Tptp.Token.category_for("wibble")
      nil
  """
  @spec category_for(binary()) :: category() | nil
  def category_for(spelling) when is_binary(spelling) do
    Enum.find_value(@spellings, fn
      {category, ^spelling} -> category
      _other -> nil
    end)
  end
end
