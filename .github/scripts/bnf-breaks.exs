# Prints, one per line, what a new SyntaxBNF takes away from an old one: a rule it
# no longer defines, an alternative it no longer admits, or a token rule whose text
# changed. Prints nothing when the new BNF only adds. Run under the project:
#
#     mix run --no-start .github/scripts/bnf-breaks.exs OLD NEW
#
# Each of these breaks a caller of this package. A rule is a node kind, so removing or
# renaming one breaks a match on it; an alternative removed from a `::=` rule is input
# that no longer parses, and one removed from a `:==` rule is a value the vocabulary
# no longer lists. A `::-` or `:::` rule keeps its regex text unparsed, so whether a
# change to one widens or narrows the lexer cannot be read off it, and any change
# counts. Additions break nothing: new input parses, and what parsed before still
# does.
#
# Comments are not rules, so a release that edits only comments prints nothing.

alias Tptp.Bnf

[old, new] = System.argv()

index = fn path ->
  path
  |> Bnf.read!()
  |> Enum.group_by(&{&1.lhs, &1.separator})
  |> Map.new(fn {key, rules} ->
    {key,
     case rules do
       [%{alternatives: nil} | _] -> {:raw, Enum.map_join(rules, "\n", &String.trim(&1.raw))}
       _ -> {:alternatives, rules |> Enum.flat_map(& &1.alternatives) |> MapSet.new()}
     end}
  end)
end

render = fn alternative ->
  Enum.map_join(alternative, "", fn
    {:ref, name} -> "<#{name}>"
    {:literal, text} -> text
  end)
end

before = index.(old)
now = index.(new)

for {{name, separator} = key, body} <- Enum.sort(before) do
  case {body, Map.get(now, key)} do
    {_body, nil} ->
      IO.puts("`<#{name}>` (`#{separator}`) is no longer defined")

    {{:raw, text}, {:raw, text}} ->
      :ok

    {{:raw, _text}, {:raw, _changed}} ->
      IO.puts("`<#{name}>` (`#{separator}`) changed")

    {{:alternatives, was}, {:alternatives, is}} ->
      for alternative <- was |> MapSet.difference(is) |> Enum.sort() do
        IO.puts("`<#{name}>` (`#{separator}`) no longer admits `#{render.(alternative)}`")
      end
  end
end
