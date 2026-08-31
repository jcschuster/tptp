defmodule Tptp.Bnf do
  @moduledoc """
  Reader for the upstream TPTP `SyntaxBNF` file.

  The BNF uses four separators, and which one a rule carries decides where the
  rule ends up:

  | Separator | Meaning                | Destination                              |
  |-----------|------------------------|------------------------------------------|
  | `::=`     | syntactic rule         | the generated `src/tptp_parser.yrl`      |
  | `:==`     | semantic rule          | `Tptp.Bnf.Vocabulary` and the lint rules |
  | `::-`     | token rule             | `Tptp.Lexer` and the regex oracle        |
  | `:::`     | character class        | `Tptp.Lexer` and the regex oracle        |

  Folding the `:==` layer into the grammar is how a TPTP parser ends up rejecting
  files that `tptp4X` accepts: `<formula_role> ::= <lower_word>` accepts *any*
  lower word, and only the `:==` rule lists the thirteen that mean something. So
  this reader keeps the layers separate and hands the `:==` rules to the linter.

  Only `::=` and `:==` rules get their right-hand sides parsed into symbols; `::-`
  and `:::` rules keep their raw regex-ish text, because that is what
  `Tptp.Bnf.Generator` needs to emit the conformance oracle.
  """

  alias Tptp.Bnf.Rule

  @separators ["::=", ":==", "::-", ":::"]

  @doc """
  Read a `SyntaxBNF` file into rules, in source order.

  Raises `File.Error` if the path does not exist. Malformed rules raise
  `ArgumentError` with the line number — this reader only ever runs on a vendored
  file at generation time, so failing loudly is the right behaviour. (The rule that
  the library never raises on input applies to TPTP input, not to our own BNF.)
  """
  @spec read!(Path.t()) :: [Rule.t()]
  def read!(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> collect_rules([], nil)
    |> Enum.map(&finish_rule/1)
  end

  @doc """
  The BNF version, taken from the filename (`SyntaxBNF-v9.3.1.2` -> `"9.3.1.2"`).
  """
  @spec version!(Path.t()) :: binary()
  def version!(path) do
    case Regex.run(~r/SyntaxBNF-v(\d[\d.]*)$/, Path.basename(path)) do
      [_all, version] ->
        version

      nil ->
        raise ArgumentError,
              "cannot read a BNF version out of #{inspect(Path.basename(path))}; " <>
                "expected a name like SyntaxBNF-v9.3.1.2"
    end
  end

  @doc """
  The single vendored BNF under `priv/bnf`.

  Raises if there is not exactly one, which keeps a half-finished version bump
  from silently shipping the wrong grammar.
  """
  @spec vendored_path!() :: Path.t()
  def vendored_path! do
    pattern = Path.join([Application.app_dir(:tptp, "priv"), "bnf", "SyntaxBNF-v*"])

    case Path.wildcard(pattern) do
      [path] ->
        path

      [] ->
        raise ArgumentError, "no BNF found at #{pattern}"

      many ->
        raise ArgumentError,
              "expected exactly one vendored BNF, found #{length(many)}: " <>
                Enum.map_join(many, ", ", &Path.basename/1)
    end
  end

  @doc """
  Rules carrying the given separator, in source order.
  """
  @spec with_separator([Rule.t()], binary()) :: [Rule.t()]
  def with_separator(rules, separator) when separator in @separators do
    Enum.filter(rules, &(&1.separator == separator))
  end

  @doc """
  Map from nonterminal name to the separator that defines it.

  When a name carries both a `::=` and a `:==` rule — fourteen do, including
  `<formula_role>` and `<thf_unitary_type>` — the `::=` rule wins, because that is
  the layer the parser is built from.
  """
  @spec definitions([Rule.t()]) :: %{binary() => binary()}
  def definitions(rules) do
    Enum.reduce(rules, %{}, fn rule, acc ->
      Map.update(acc, rule.lhs, rule.separator, &prefer_syntactic(&1, rule.separator))
    end)
  end

  @doc """
  Merge rules sharing a left-hand side and separator into one rule.

  `<defined_predicate>` and `<defined_proposition>` each carry two `:==` rules
  whose alternatives belong to a single set; without merging, the second silently
  shadows the first.
  """
  @spec merge_alternatives([Rule.t()]) :: [Rule.t()]
  def merge_alternatives(rules) do
    rules
    |> Enum.reduce({[], %{}}, fn rule, {order, by_key} ->
      key = {rule.lhs, rule.separator}

      case Map.fetch(by_key, key) do
        {:ok, existing} ->
          merged = %{existing | alternatives: existing.alternatives ++ rule.alternatives}
          {order, Map.put(by_key, key, merged)}

        :error ->
          {[key | order], Map.put(by_key, key, rule)}
      end
    end)
    |> then(fn {order, by_key} -> Enum.map(Enum.reverse(order), &Map.fetch!(by_key, &1)) end)
  end

  defp collect_rules([], done, nil), do: Enum.reverse(done)
  defp collect_rules([], done, open), do: Enum.reverse([open | done])

  defp collect_rules([{line, number} | rest], done, open) do
    cond do
      String.starts_with?(line, "%") ->
        collect_rules(rest, close(done, open), nil)

      String.trim(line) == "" ->
        collect_rules(rest, close(done, open), nil)

      match?({:ok, _rule}, start_of_rule(line, number)) ->
        {:ok, rule} = start_of_rule(line, number)
        collect_rules(rest, close(done, open), rule)

      open != nil ->
        collect_rules(rest, done, %{open | raw: open.raw <> " " <> String.trim(line)})

      true ->
        raise ArgumentError,
              "line #{number} of the BNF is neither a comment, a rule, nor a continuation: " <>
                inspect(line)
    end
  end

  defp close(done, nil), do: done
  defp close(done, open), do: [open | done]

  defp start_of_rule(line, number) do
    case Regex.run(~r/^<([A-Za-z_][A-Za-z_0-9]*)>\s*(::=|:==|::-|:::)\s?(.*)$/, line) do
      [_all, lhs, separator, raw] ->
        {:ok, %Rule{lhs: lhs, separator: separator, raw: String.trim(raw), line: number}}

      nil ->
        :error
    end
  end

  defp prefer_syntactic("::=", _new), do: "::="
  defp prefer_syntactic(_old, new), do: new

  defp finish_rule(%Rule{separator: separator} = rule) when separator in ["::=", ":=="] do
    %{rule | alternatives: parse_alternatives(rule)}
  end

  defp finish_rule(%Rule{} = rule), do: rule

  defp parse_alternatives(%Rule{raw: ""}), do: [[]]

  defp parse_alternatives(%Rule{raw: raw} = rule) do
    raw
    |> String.split("|")
    |> Enum.map(&parse_symbols(String.trim(&1), rule))
  end

  defp parse_symbols(text, rule), do: parse_symbols(text, rule, [])

  defp parse_symbols("", _rule, acc), do: Enum.reverse(acc)

  defp parse_symbols(<<c, rest::binary>>, rule, acc) when c in [?\s, ?\t] do
    parse_symbols(rest, rule, acc)
  end

  defp parse_symbols(<<"<", rest::binary>> = text, rule, acc) do
    case Regex.run(~r/^<([A-Za-z_][A-Za-z_0-9]*)>/, text) do
      [matched, name] ->
        parse_symbols(
          binary_part(text, byte_size(matched), byte_size(text) - byte_size(matched)),
          rule,
          [{:ref, name} | acc]
        )

      nil ->
        take_literal(<<"<", rest::binary>>, rule, acc)
    end
  end

  defp parse_symbols(text, rule, acc), do: take_literal(text, rule, acc)

  defp take_literal(text, rule, acc) do
    length = literal_length(text, 0)

    if length == 0 do
      raise ArgumentError, "cannot tokenise #{inspect(text)} on line #{rule.line} of the BNF"
    end

    literal = binary_part(text, 0, length)
    rest = binary_part(text, length, byte_size(text) - length)
    parse_symbols(rest, rule, [{:literal, literal} | acc])
  end

  defp literal_length(<<>>, taken), do: taken
  defp literal_length(<<c, _::binary>>, taken) when c in [?\s, ?\t], do: taken

  defp literal_length(<<"<", _::binary>> = text, taken) when taken > 0 do
    if Regex.match?(~r/^<[A-Za-z_][A-Za-z_0-9]*>/, text), do: taken, else: keep_going(text, taken)
  end

  defp literal_length(text, taken), do: keep_going(text, taken)

  defp keep_going(<<_c, rest::binary>>, taken), do: literal_length(rest, taken + 1)
end
