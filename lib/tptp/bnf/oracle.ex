defmodule Tptp.Bnf.Oracle do
  @moduledoc """
  Renders `Tptp.Bnf.OracleTable`, the regex transcription of the BNF's token layer.

  `mix tptp.gen` runs this; nothing at runtime does. The output goes to
  `test/support/`, because its only purpose is to be a second opinion the lexer can
  be checked against.

  ## Why a second opinion is worth generating

  `Tptp.Lexer` is the one hand-written stage in this library. Everything else is
  derived from the BNF, so a mistake shows up as a compile failure or a coverage
  gap; a lexer that quietly accepts `1.` as a real, or stops a `<sq_char>` one byte
  early, produces a plausible token stream and a wrong parse. The BNF's `::-` and
  `:::` rules are already regular expressions with `<name>` references in place of
  sub-patterns, so transcribing them mechanically costs almost nothing and gives a
  property test something independent to disagree with.

  It is an oracle, not an implementation. It anchors and matches one token at a
  time; it does not scan, has no notion of maximal munch, and is far too slow for
  the hot path. Where the two disagree the BNF is right and the lexer is wrong —
  unless the disagreement is one of the deliberate deviations `Tptp.Lexer`
  documents, in which case the test names it.

  ## The transcription

  Each rule's right-hand side is regex syntax already. Every `<name>` is replaced
  by that rule's pattern wrapped in a non-capturing group, recursively; the
  references form a DAG with no cycles, so the substitution terminates. Octal
  escapes such as `\\40` mean the same thing to PCRE as they do to the BNF, and are
  passed through untouched rather than reinterpreted.
  """

  alias Tptp.Bnf

  @token_separators ["::-", ":::"]

  @doc """
  Render the oracle module, and say how many patterns it holds.
  """
  @spec table(Path.t()) :: {binary(), non_neg_integer()}
  def table(bnf_path) do
    patterns = patterns(bnf_path)

    {render(patterns, bnf_path), map_size(patterns)}
  end

  @doc """
  The resolved pattern for every `::-` and `:::` rule, keyed by nonterminal name.

      iex> patterns = Tptp.Bnf.Oracle.patterns(Tptp.Bnf.vendored_path!())
      iex> patterns["lower_alpha"]
      "[a-z]"
      iex> patterns["lower_word"]
      "(?:[a-z])(?:((?:[a-z])|(?:[A-Z])|(?:[0-9])|(?:[_])))*"
  """
  @spec patterns(Path.t()) :: %{binary() => binary()}
  def patterns(bnf_path) do
    raw =
      bnf_path
      |> Bnf.read!()
      |> Enum.filter(&(&1.separator in @token_separators))
      |> Map.new(&{&1.lhs, &1.raw})

    Map.new(raw, fn {name, _body} -> {name, resolve(name, raw, [])} end)
  end

  @spec resolve(binary(), %{binary() => binary()}, [binary()]) :: binary()
  defp resolve(name, raw, seen) do
    if name in seen do
      raise "the BNF token rules are cyclic through <#{name}>: #{inspect(seen)}"
    end

    case Map.fetch(raw, name) do
      {:ok, body} -> substitute(body, raw, [name | seen])
      :error -> raise "<#{name}> is referenced by a token rule but has none of its own"
    end
  end

  @spec substitute(binary(), %{binary() => binary()}, [binary()]) :: binary()
  defp substitute(body, raw, seen) do
    Regex.replace(~r/<([A-Za-z_][A-Za-z_0-9]*)>/, body, fn _whole, name ->
      "(?:#{resolve(name, raw, seen)})"
    end)
  end

  @spec anchor(binary()) :: binary()
  defp anchor(pattern), do: "\\A(?:" <> pattern <> ")\\z"

  @spec render(%{binary() => binary()}, Path.t()) :: binary()
  defp render(patterns, bnf_path) do
    sorted = Enum.sort(patterns)

    """
    defmodule Tptp.Bnf.OracleTable do
      @moduledoc \"\"\"
      The BNF's token layer as anchored regular expressions. Generated; do not edit.

      `mix tptp.gen` writes this from `#{Path.basename(bnf_path)}`, one entry per
      `::-` and `:::` rule, with every `<name>` reference inlined. It exists so that
      the hand-written `Tptp.Lexer` has something independent to be checked against;
      see `Tptp.Bnf.Oracle` for why that is worth generating and what the checking
      does and does not prove.
      \"\"\"

      @typedoc \"\"\"
      A nonterminal defined by a `::-` or `:::` rule.

      One of: #{Enum.map_join(sorted, ", ", fn {name, _} -> "`#{name}`" end)}.
      \"\"\"
      @type name :: binary()

      @patterns %{
    #{Enum.map_join(sorted, ",\n", fn {name, pattern} -> "    #{inspect(name)} => Regex.compile!(#{inspect(anchor(pattern))})" end)}
      }

      @doc "Every nonterminal the token layer defines, sorted."
      @spec names() :: [name()]
      def names, do: #{sorted |> Enum.map_join(", ", fn {name, _} -> inspect(name) end) |> then(&"[#{&1}]")}

      @doc \"\"\"
      The anchored pattern for one nonterminal.

      Raises for a name the BNF does not define, because a typo in a test should
      fail rather than silently check nothing.
      \"\"\"
      @spec pattern(name()) :: Regex.t()
      def pattern(name), do: Map.fetch!(@patterns, name)

      @doc \"\"\"
      Whether `text` is exactly one `name`, start to end.

      Anchored on both sides: a token that only starts with a `<lower_word>` is not
      a `<lower_word>`, and the whole point of the oracle is to catch a lexer that
      stopped a byte early.
      \"\"\"
      @spec matches?(name(), binary()) :: boolean()
      def matches?(name, text) when is_binary(text), do: Regex.match?(pattern(name), text)

      @doc "Which of the token nonterminals `text` is, if any."
      @spec classify(binary()) :: [name()]
      def classify(text) when is_binary(text) do
        for name <- names(), matches?(name, text), do: name
      end
    end
    """
  end
end
