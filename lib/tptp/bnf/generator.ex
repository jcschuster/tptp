defmodule Tptp.Bnf.Generator do
  @moduledoc """
  Turns the vendored `SyntaxBNF` into `src/tptp_parser.yrl`.

  The generated grammar is committed, so an installing user needs no Python, no
  awk and no BNF — only OTP, which already ships `yecc`. Regeneration is a
  maintainer action taken on a TPTP release, and the `.yrl` diff *is* the review
  of that release.

  * **Repetition.** `X*` becomes a right-recursive helper nonterminal with an
    empty production. Six `::=` rules use it.
  * **Literals.** Runs of literal text are split against `Tptp.Token.spellings/0`,
    longest match first, so `tpi(` becomes `kw_tpi lparen` and `).` becomes
    `rparen dot`.
  * **`<nothing>`.** An alternative that is only `<nothing>` becomes yecc's
    `'$empty'`, and the nonterminal itself disappears.
  * **Punctuation and fixed spellings are dropped from the children.** A node's
    `kind` and `alt` already determine every byte of fixed text, and
    `Tptp.Printer.Shapes` is generated from the same source so the two cannot
    drift. What survives as a child is a nonterminal or a value-carrying token.
  * **Single-terminal alternatives become leaves.** `<fof_quantifier> ::= !`
    yields `%Tptp.Node{kind: :forall}` rather than a wrapper around a token, which
    is why `<th1_defined_term> ::= !! | ?? | @@+ | @@- | @=` — the polymorphic
    constants of TH1 — arrive with a precise kind.
  * **Transparent rules are spliced.** A rule whose every alternative yields
    exactly one child carries no information; splicing it through keeps the CST
    roughly the size of the input rather than five times it.

  An alternative that is only `<nothing>` yields `nil` rather than an empty node.
  There are no tokens to take a span from, and `nil` says "absent" without a
  consumer having to distinguish it from a node that happens to have no children —
  `<thf_tuple> ::= []` is exactly that, and means something different.

  Three departures, each of which would otherwise be an LALR(1) conflict. They are
  reported by `generate/2` so they stay visible.

  1. `<source> ::= … | unknown` is dropped. `unknown` still parses, as
     `<dag_source> -> <name>`; keeping the literal alternative as well would make
     the two indistinguishable in source position.
  2. `inference`, `introduced` and `file` get terminals of their own but are also
     admitted as `<atomic_word>`, so `fof(file, axiom, p).` keeps working. The
     `(` lookahead separates the two readings. In that position they are relabelled
     `lower_word`, because their keyword-ness is an artefact of parsing and a
     formula named `file` is an ordinary lower word like any other.
  3. The six `$`-keywords (`$thf $tff $fof $cnf $fot $let`) are reserved: they are
     *not* admitted as `<atomic_defined_word>`. Admitting `$let` would make
     `$let(a,b,c)` ambiguous between `<thf_let>` and `<thf_fof_function>`. Upstream
     reserves them too.

  The seven language keywords (`thf tff tcf fof cnf tpi include`) need no such
  handling: they only ever occur as a statement's first token, so `Tptp.Splitter`
  promotes token zero and every other occurrence stays a `<lower_word>`. That is
  what keeps `fof(fof, axiom, p).` legal.
  """

  alias Tptp.Bnf
  alias Tptp.Bnf.Rule
  alias Tptp.Token

  @root "TPTP_input"

  @kept_terminals [:dw_thf, :dw_tff, :dw_fof, :dw_cnf, :dw_fot]

  @significant ~w(
    constant functor defined_constant defined_functor system_constant system_functor
    variable type_constant type_functor defined_type system_type
    name file_name inference_rule intro_type formula_role
  )a

  @significant_names Enum.map(@significant, &Atom.to_string/1)

  @dropped_alternatives [{"source", [{:literal, "unknown"}]}]

  @injected_productions [
    {"atomic_word", :kw_inference},
    {"atomic_word", :kw_introduced},
    {"atomic_word", :kw_file}
  ]

  @typedoc "A resolved grammar symbol."
  @type symbol :: {:nonterminal, binary()} | {:terminal, Token.category()} | {:repeat, binary()}

  @typedoc "Nonterminal name to its alternatives, each a sequence of symbols."
  @type grammar :: %{binary() => [[symbol()]]}

  @typedoc "Statistics and departures, for the task to report."
  @type report :: %{
          rules: non_neg_integer(),
          productions: non_neg_integer(),
          nonterminals: non_neg_integer(),
          terminals: non_neg_integer(),
          inlined: [binary()],
          transparent: [binary()],
          significant: [binary()],
          pruned: [binary()],
          dropped: [binary()],
          injected: non_neg_integer()
        }

  @doc """
  Build the `.yrl` source and a report from a BNF file.
  """
  @spec generate(Path.t()) :: {binary(), report()}
  def generate(bnf_path) do
    rules =
      bnf_path
      |> Bnf.read!()
      |> Bnf.merge_alternatives()

    definitions = Bnf.definitions(rules)
    syntactic = Bnf.with_separator(rules, "::=")

    {resolved, inlined} =
      syntactic
      |> Enum.map(&drop_alternatives/1)
      |> Enum.map(&resolve_rule(&1, definitions))
      |> Map.new(fn {lhs, alts} -> {lhs, alts} end)
      |> inline_terminal_rules()

    reachable = reachable_from(resolved, @root)
    pruned = resolved |> Map.keys() |> Enum.reject(&Map.has_key?(reachable, &1)) |> Enum.sort()
    kept = Map.take(resolved, Map.keys(reachable))

    transparent = Enum.sort(transparent_names(kept))
    order = Enum.filter(Enum.map(syntactic, & &1.lhs), &Map.has_key?(kept, &1))

    {productions, helpers} = build_productions(order, kept)
    all_productions = productions ++ injected_productions()

    nonterminals = Enum.uniq(order ++ helpers)
    terminals = collect_terminals(all_productions)

    source = render(nonterminals, terminals, all_productions, bnf_path)

    report = %{
      rules: map_size(kept),
      productions: length(all_productions),
      nonterminals: length(nonterminals),
      terminals: length(terminals),
      inlined: Enum.sort(inlined),
      transparent: transparent,
      significant: Enum.sort(Enum.filter(@significant_names, &Map.has_key?(kept, &1))),
      pruned: pruned,
      dropped: Enum.map(@dropped_alternatives, &elem(&1, 0)),
      injected: length(@injected_productions)
    }

    {source, report}
  end

  @doc """
  The nonterminals whose node `Tptp.Parser` collapses onto its leaf.

  These are the chain rules that say what *role* a symbol plays — `<constant>`,
  `<functor>`, `<variable>` and the rest. Each is a pure rename of the thing below
  it, so keeping a node for every level would cost three nodes to say one thing;
  collapsing keeps the outermost name and drops the nodes.

  The list is curated rather than derived, and that is the point. A rule like
  `<tff_arguments> ::= <tff_term>` is also a single-child chain, but its child is
  an *element* rather than a rename, and collapsing it would rewrite an argument's
  kind to `:tff_arguments` and lose what the argument actually was.
  """
  @spec significant() :: [atom()]
  def significant, do: @significant

  @doc """
  Build `Tptp.Bnf.Vocabulary` from the `:==` rules that are closed word lists.

  These are the semantic layer the grammar deliberately does not enforce. The
  syntactic rule for `<formula_role>` accepts any `<lower_word>`; only the `:==`
  rule names the thirteen that mean something. `fof(a, axim, p).` is therefore
  valid TPTP and semantically wrong, and the difference between those two is a
  warning-severity diagnostic rather than a parse failure.

  Emitted as multi-clause functions over binary literals, which the compiler turns
  into a direct dispatch — faster than a `MapSet`, and every atom involved stays a
  compile-time one.
  """
  @spec vocabularies(Path.t()) :: {binary(), [{binary(), [binary()]}]}
  def vocabularies(bnf_path) do
    rules = bnf_path |> Bnf.read!() |> Bnf.merge_alternatives()

    entries =
      rules
      |> Bnf.with_separator(":==")
      |> Enum.map(&{&1.lhs, closed_words(&1.alternatives)})
      |> Enum.filter(fn {_lhs, words} -> words != nil end)
      |> Enum.sort()

    entries = entries ++ [{"reserved_word", reserved_words(rules)}]

    {render_vocabulary(entries, bnf_path), entries}
  end

  @doc """
  Build `Tptp.Printer.Shapes` from the same grammar the parser is built from.

  A canonical printer has to know how each node kind is spelled — where the
  parentheses go, which literal separates the children — and that is exactly what
  the `::=` productions say. Hand-writing it would be a hundred clauses that agree
  with the grammar until someone regenerates the grammar, so it is derived from the
  same source in the same pass.

  A shape is keyed by node kind and child count, which is enough: of the groups the
  grammar produces, exactly one has two spellings — `<cnf_literal>` writes `~p` and
  `~(p)`. Those mean the same thing and the parentheses are redundant, since the
  operand is already atomic, so the shorter one is taken. The tie-break is "fewest
  literals" generally, which is safe because a tree carries its own parenthesisation
  nodes: `<fof_unitary_formula> ::= (<fof_logic_formula>)` is a node, so no
  parenthesis that changes a reading is ever a printer's to invent or omit.

  This is also why a leading comma is spliced away only for the `comma_*` list
  helpers, whose comma is a list separator the `{:separated, ","}` shape supplies.
  Everywhere else — `<optional_info> ::= ,<useful_info>` and its two siblings — the
  comma is syntax a printer has to emit, and splicing it would leave a shape with
  two adjacent slots and no way to know whether they need separating.
  """
  @spec shapes(Path.t()) :: {binary(), non_neg_integer()}
  def shapes(bnf_path) do
    entries =
      bnf_path
      |> productions_for_shapes()
      |> Enum.group_by(fn {kind, arity, _shape} -> {kind, arity} end, &elem(&1, 2))
      |> Enum.map(fn {key, spellings} -> {key, resolve_shape(spellings)} end)
      |> Enum.sort()

    {render_shapes(entries, bnf_path), length(entries)}
  end

  defp productions_for_shapes(bnf_path) do
    rules = bnf_path |> Bnf.read!() |> Bnf.merge_alternatives()
    definitions = Bnf.definitions(rules)

    {resolved, _inlined} =
      rules
      |> Bnf.with_separator("::=")
      |> Enum.map(&drop_alternatives/1)
      |> Enum.map(&resolve_rule(&1, definitions))
      |> Map.new(fn {lhs, alts} -> {lhs, alts} end)
      |> inline_terminal_rules()

    reachable = reachable_from(resolved, @root)
    kept = Map.take(resolved, Map.keys(reachable))

    for {lhs, alternatives} <- kept,
        symbols <- alternatives,
        symbols != [],
        positions = child_positions(symbols),
        not splice?(lhs, symbols, positions),
        not (match?([{:terminal, _category}], symbols) and positions == []),
        do: {lhs, length(positions), spelling_of(symbols, positions)}
  end

  defp spelling_of(symbols, positions) do
    if Enum.any?(symbols, &match?({:repeat, _name}, &1)) do
      {:separated, ","}
    else
      symbols
      |> Enum.with_index(1)
      |> Enum.map(fn {symbol, index} ->
        cond do
          index in positions -> :slot
          match?({:terminal, _category}, symbol) -> Token.spelling(elem(symbol, 1))
          true -> :slot
        end
      end)
    end
  end

  @doc false
  @spec atom_literal(binary()) :: binary()
  defp atom_literal(name), do: ~s(:"#{name}")

  defp resolve_shape([single]), do: single

  defp resolve_shape(spellings) do
    Enum.min_by(spellings, fn
      {:separated, _sep} -> 0
      items -> Enum.count(items, &is_binary/1)
    end)
  end

  @doc """
  Every `$`-prefixed literal the BNF mentions, in any rule and any position.

  The closed vocabularies above only catch rules whose alternatives are *nothing
  but* literals, and several reserved words are not written that way:
  `<ntf_domains_spec> :== $domains <identical> <ntf_domains_value>` puts `$domains`
  beside two other symbols, so it is a word the language knows that no closed list
  contains. Linting `$`-words against the closed lists alone reports those as
  unknown, which they are not.
  """
  @spec reserved_words([Rule.t()]) :: [binary()]
  def reserved_words(rules) do
    for rule <- rules,
        is_list(rule.alternatives),
        alternative <- rule.alternatives,
        {:literal, text} <- alternative,
        word = plain_word(text),
        is_binary(word),
        String.starts_with?(word, "$"),
        not String.starts_with?(word, "$$"),
        uniq: true,
        do: word
  end

  defp closed_words(alternatives) do
    {words, others} =
      alternatives
      |> Enum.map(&{&1, closed_word(&1)})
      |> Enum.split_with(fn {_alternative, word} -> is_binary(word) end)

    generalising? = Enum.all?(others, fn {alternative, _} -> single_ref?(alternative) end)

    if words != [] and generalising? do
      words |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    end
  end

  defp single_ref?([{:ref, _name}]), do: true
  defp single_ref?(_alternative), do: false

  defp closed_word([{:literal, text}]), do: plain_word(text)
  defp closed_word(_symbols), do: nil

  defp plain_word(<<"{", rest::binary>>) do
    case String.split(rest, "}") do
      [word, ""] -> plain_word(word)
      _other -> nil
    end
  end

  defp plain_word(text) do
    if Regex.match?(~r/^\$?\$?[A-Za-z_][A-Za-z_0-9]*$/, text), do: text
  end

  defp render_shapes(entries, bnf_path) do
    {variadic, fixed} =
      Enum.split_with(entries, fn {_key, shape} -> match?({:separated, _sep}, shape) end)

    clauses =
      Enum.map_join(variadic ++ fixed, "\n", fn
        {{kind, _arity}, {:separated, separator}} ->
          "  def shape(#{atom_literal(kind)}, arity) when is_integer(arity), " <>
            "do: {:separated, #{inspect(separator)}}"

        {{kind, arity}, shape} ->
          "  def shape(#{atom_literal(kind)}, #{arity}), do: #{inspect(shape)}"
      end)

    """
    defmodule Tptp.Printer.Shapes do
      @moduledoc \"\"\"
      How each node kind is spelled, derived from the grammar.

      DO NOT EDIT. Generated by `mix tptp.gen` from
      `#{Path.basename(bnf_path)}`.

      A shape is a list of items in source order: `:slot` takes the next child, a
      binary is a literal to emit. `{:separated, ","}` is a variadic list — every
      child, joined by that literal.

      Keyed by kind and child count, which the grammar makes sufficient. Anything
      not listed is a leaf, and prints its own text.

      A separated list is the exception, and matches any arity: the grammar writes
      `<tff_arguments> ::= <tff_term><comma_tff_term>*`, so its production has two
      symbols however many arguments the call actually has.
      \"\"\"

      @typedoc "One item of a shape: a child slot or a literal."
      @type item :: :slot | binary()

      @typedoc "How a node kind is spelled."
      @type t :: [item()] | {:separated, binary()}

      @doc \"\"\"
      The shape for a node kind at a child count, or `nil` for a leaf.
      \"\"\"
      @spec shape(atom(), non_neg_integer()) :: t() | nil
    #{clauses}
      def shape(kind, arity) when is_atom(kind) and is_integer(arity), do: nil
    end
    """
  end

  defp render_vocabulary(entries, bnf_path) do
    [
      """
      defmodule Tptp.Bnf.Vocabulary do
        @moduledoc \"\"\"
        The closed vocabularies of the TPTP `:==` semantic layer.

        DO NOT EDIT. Generated by `mix tptp.gen` from
        `priv/bnf/#{Path.basename(bnf_path)}`.

        The grammar accepts far more than these lists do: `<formula_role> ::=
        <lower_word>` admits any lower word, and `<defined_functor> ::=
        <atomic_defined_word>` admits any `$`-word. Membership here is what
        separates a well-formed statement from a merely parseable one, and it is
        checked by `Tptp.Lint` at warning severity rather than by the parser.
        \"\"\"
      """,
      Enum.map(entries, &render_vocabulary_entry/1),
      "end\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp render_vocabulary_entry({name, words}) do
    """

      @#{name}_values #{inspect(words, limit: :infinity)}

      @doc \"\"\"
      The #{length(words)} values the BNF lists for `<#{name}>`.
      \"\"\"
      @spec #{name}_values() :: [binary()]
      def #{name}_values, do: @#{name}_values

      @doc \"\"\"
      Whether `word` is one of the #{length(words)} `<#{name}>` values.
      \"\"\"
      @spec #{name}?(binary()) :: boolean()
    #{Enum.map_join(words, "\n", &"  def #{name}?(#{inspect(&1)}), do: true")}
      def #{name}?(word) when is_binary(word), do: false
    """
  end

  defp drop_alternatives(%Rule{} = rule) do
    dropped = for {lhs, alt} <- @dropped_alternatives, lhs == rule.lhs, do: alt
    %{rule | alternatives: Enum.reject(rule.alternatives, &(&1 in dropped))}
  end

  defp resolve_rule(%Rule{} = rule, definitions) do
    {rule.lhs, Enum.map(rule.alternatives, &resolve_alternative(&1, rule, definitions))}
  end

  defp resolve_alternative([{:ref, "nothing"}], _rule, _definitions), do: []

  defp resolve_alternative(symbols, rule, definitions) do
    symbols
    |> mark_repetition()
    |> Enum.flat_map(&resolve_symbol(&1, rule, definitions))
    |> rewrite_sequences()
  end

  defp mark_repetition(symbols), do: mark_repetition(symbols, [])

  defp mark_repetition([], acc), do: Enum.reverse(acc)

  defp mark_repetition([{:ref, name}, {:literal, "*"} | rest], acc) do
    mark_repetition(rest, [{:repeat, name} | acc])
  end

  defp mark_repetition([symbol | rest], acc), do: mark_repetition(rest, [symbol | acc])

  defp resolve_symbol({:repeat, name}, _rule, _definitions), do: [{:repeat, name}]

  defp resolve_symbol({:ref, name}, rule, definitions) do
    case Map.fetch(definitions, name) do
      {:ok, "::="} ->
        [{:nonterminal, name}]

      {:ok, separator} when separator in ["::-", ":::"] ->
        [{:terminal, token_category!(name, rule)}]

      {:ok, ":=="} ->
        raise ArgumentError,
              "<#{name}> is referenced from the syntactic rule <#{rule.lhs}> on line " <>
                "#{rule.line} but only defined by a :== semantic rule"

      :error ->
        raise ArgumentError,
              "<#{name}> is referenced from <#{rule.lhs}> on line #{rule.line} but never defined"
    end
  end

  defp resolve_symbol({:literal, text}, rule, _definitions) do
    Enum.map(split_literal(text, rule), &{:terminal, &1})
  end

  defp token_category!(name, rule) do
    Enum.find(Token.categories(), &(Atom.to_string(&1) == name)) ||
      raise(
        ArgumentError,
        "<#{name}> is a token rule referenced from <#{rule.lhs}> on line #{rule.line}, " <>
          "but Tptp.Token declares no such category"
      )
  end

  defp split_literal("", _rule), do: []

  defp split_literal(<<c, _::binary>> = text, rule) when c == ?$ or c == ?_ do
    split_word(text, rule)
  end

  defp split_literal(<<c, _::binary>> = text, rule)
       when c in ?a..?z or c in ?A..?Z do
    split_word(text, rule)
  end

  defp split_literal(text, rule) do
    case Enum.find(Token.spellings(), fn {_c, s} -> String.starts_with?(text, s) end) do
      {category, spelling} ->
        rest = binary_part(text, byte_size(spelling), byte_size(text) - byte_size(spelling))
        [category | split_literal(rest, rule)]

      nil ->
        raise ArgumentError,
              "no terminal matches #{inspect(text)} on line #{rule.line} of the BNF"
    end
  end

  defp split_word(text, rule) do
    length = word_length(text, 0)
    word = binary_part(text, 0, length)
    rest = binary_part(text, length, byte_size(text) - length)

    case Token.category_for(word) do
      nil ->
        raise ArgumentError,
              "#{inspect(word)} on line #{rule.line} of the BNF is not a declared keyword; " <>
                "add it to Tptp.Token"

      category ->
        [category | split_literal(rest, rule)]
    end
  end

  defp word_length(<<?$, rest::binary>>, 0), do: word_length(rest, 1)

  defp word_length(<<c, rest::binary>>, taken)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    word_length(rest, taken + 1)
  end

  defp word_length(_text, taken), do: taken

  defp rewrite_sequences(symbols), do: rewrite_sequences(symbols, [])

  defp rewrite_sequences([], acc), do: Enum.reverse(acc)

  defp rewrite_sequences([{:terminal, :tilde}, {:terminal, :vline} | rest], acc) do
    rewrite_sequences(rest, [{:terminal, :nor} | acc])
  end

  defp rewrite_sequences(
         [{:terminal, :less_sign}, {:terminal, :dot}, {:terminal, :arrow} | rest],
         acc
       ) do
    rewrite_sequences(rest, [{:terminal, :short_angle} | acc])
  end

  defp rewrite_sequences([symbol | rest], acc), do: rewrite_sequences(rest, [symbol | acc])

  defp inline_terminal_rules(resolved), do: inline_terminal_rules(resolved, [])

  defp inline_terminal_rules(resolved, done) do
    candidates =
      for {lhs, [[{:terminal, category}]]} <- resolved,
          lhs != @root,
          lhs not in @significant_names,
          do: {lhs, category}

    case candidates do
      [] ->
        {resolved, done}

      _some ->
        substitutions = Map.new(candidates)
        names = Map.keys(substitutions)

        resolved
        |> Map.drop(names)
        |> Map.new(fn {lhs, alternatives} ->
          {lhs, Enum.map(alternatives, &substitute(&1, substitutions))}
        end)
        |> inline_terminal_rules(done ++ names)
    end
  end

  defp substitute(symbols, substitutions) do
    Enum.map(symbols, fn
      {:nonterminal, name} = symbol ->
        case Map.fetch(substitutions, name) do
          {:ok, category} -> {:terminal, category}
          :error -> symbol
        end

      symbol ->
        symbol
    end)
  end

  @spec reachable_from(grammar(), binary()) :: %{binary() => true}
  defp reachable_from(resolved, root), do: reach(resolved, [root], %{})

  @spec reach(grammar(), [binary()], %{binary() => true}) :: %{binary() => true}
  defp reach(_resolved, [], seen), do: seen

  defp reach(resolved, [name | rest], seen) do
    if Map.has_key?(seen, name) do
      reach(resolved, rest, seen)
    else
      next =
        resolved
        |> Map.get(name, [])
        |> Enum.flat_map(& &1)
        |> Enum.flat_map(fn
          {:nonterminal, other} -> [other]
          {:repeat, other} -> [other]
          {:terminal, _category} -> []
        end)

      reach(resolved, next ++ rest, Map.put(seen, name, true))
    end
  end

  @spec transparent_names(grammar()) :: [binary()]
  defp transparent_names(kept) do
    for {lhs, alternatives} <- kept,
        lhs not in @significant_names,
        alternatives != [],
        Enum.all?(alternatives, &match?([_single], children_of(&1))),
        do: lhs,
        into: []
  end

  defp children_of(symbols) do
    Enum.filter(symbols, fn
      {:nonterminal, _name} -> true
      {:repeat, _name} -> true
      {:terminal, category} -> Token.spelling(category) == nil
    end)
  end

  defp build_productions(order, kept) do
    productions =
      Enum.flat_map(order, fn lhs ->
        kept
        |> Map.fetch!(lhs)
        |> Enum.with_index()
        |> Enum.map(fn
          {[], _index} ->
            {lhs, ["'$empty'"], "nil"}

          {symbols, index} ->
            {lhs, Enum.map(symbols, &render_symbol/1), action(lhs, symbols, index)}
        end)
      end)

    helpers =
      for lhs <- order,
          symbols <- Map.fetch!(kept, lhs),
          {:repeat, name} <- symbols,
          uniq: true,
          do: name

    {productions ++ Enum.flat_map(helpers, &helper_productions/1),
     Enum.map(helpers, &"#{&1}_rep")}
  end

  defp action(lhs, symbols, index) do
    positions = child_positions(symbols)

    cond do
      splice?(lhs, symbols, positions) ->
        [position] = positions
        "'$#{position}'"

      Enum.any?(symbols, &match?({:repeat, _name}, &1)) ->
        node(lhs, index, repetition_children(symbols, positions), symbols, positions)

      match?([{:terminal, _category}], symbols) and positions == [] ->
        [{:terminal, category}] = symbols
        "{'$leaf', '#{category}', #{index}, '$1'}"

      true ->
        children = "[" <> Enum.map_join(positions, ", ", &"'$#{&1}'") <> "]"
        node(lhs, index, children, symbols, positions)
    end
  end

  defp splice?(lhs, symbols, [position]) when lhs not in @significant_names do
    symbols
    |> Enum.with_index(1)
    |> Enum.reject(fn {_symbol, index} -> index == position end)
    |> Enum.map(fn {symbol, _index} -> symbol end)
    |> droppable?(lhs)
  end

  defp splice?(_lhs, _symbols, _positions), do: false

  defp droppable?([], _lhs), do: true

  defp droppable?([{:terminal, :comma}], lhs), do: String.starts_with?(lhs, "comma_")

  defp droppable?(_symbols, _lhs), do: false

  defp node(lhs, index, children, symbols, positions) do
    last = length(symbols)
    open = if 1 in positions, do: "nil", else: "'$1'"
    close = if last in positions, do: "nil", else: "'$#{last}'"

    "{'$node', '#{lhs}', #{index}, #{children}, #{open}, #{close}}"
  end

  defp repetition_children(symbols, positions) do
    symbols
    |> Enum.with_index(1)
    |> Enum.filter(fn {symbol, index} -> index in positions or match?({:repeat, _n}, symbol) end)
    |> Enum.map_join(" ++ ", fn
      {{:repeat, _name}, index} -> "'$#{index}'"
      {_symbol, index} -> "['$#{index}']"
    end)
  end

  defp child_positions(symbols) do
    symbols
    |> Enum.with_index(1)
    |> Enum.filter(fn {symbol, _index} -> keep_child?(symbol) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp keep_child?({:nonterminal, _name}), do: true
  defp keep_child?({:repeat, _name}), do: true

  defp keep_child?({:terminal, category}) do
    Token.spelling(category) == nil or category in @kept_terminals
  end

  defp helper_productions(name) do
    rep = "#{name}_rep"

    [
      {rep, ["'$empty'"], "[]"},
      {rep, [quoted(name), quoted(rep)], "['$1' | '$2']"}
    ]
  end

  defp injected_productions do
    Enum.map(@injected_productions, fn {lhs, category} ->
      {lhs, ["'#{category}'"], "{'$leaf', 'lower_word', 0, '$1'}"}
    end)
  end

  defp render_symbol({:nonterminal, name}), do: quoted(name)
  defp render_symbol({:repeat, name}), do: quoted("#{name}_rep")
  defp render_symbol({:terminal, category}), do: "'#{category}'"

  defp quoted(name), do: "'#{name}'"

  defp collect_terminals(productions) do
    productions
    |> Enum.flat_map(fn {_lhs, rhs, _action} -> rhs end)
    |> Enum.filter(&(&1 != "'$empty'"))
    |> Enum.uniq()
    |> Enum.filter(fn symbol ->
      Enum.any?(Token.categories(), &("'#{&1}'" == symbol))
    end)
  end

  defp render(nonterminals, terminals, productions, bnf_path) do
    [
      header(bnf_path),
      "Nonterminals\n",
      wrap(Enum.map(nonterminals, &quoted/1)),
      ".\n\nTerminals\n",
      wrap(terminals),
      ".\n\nRootsymbol ",
      quoted(@root),
      ".\n\n",
      Enum.map(productions, fn {lhs, rhs, action} ->
        [quoted(lhs), " -> ", Enum.join(rhs, " "), " : ", action, ".\n"]
      end)
    ]
    |> IO.iodata_to_binary()
  end

  defp header(bnf_path) do
    """
    %% DO NOT EDIT. Generated by `mix tptp.gen` from
    %% priv/bnf/#{Path.basename(bnf_path)}.
    %%
    %% Every action is one of three templates:
    %%
    %%   {'$node', Kind, Alt, Children, Open, Close}
    %%   {'$leaf', Category, Alt, Token}   an alternative that is a single fixed token
    %%   '$N'                              a transparent rule, spliced through
    %%
    %% Open and Close are the production's first and last symbols when those are
    %% punctuation, and so are dropped from Children -- they are what lets a node's
    %% span cover its own brackets. Either is nil when that position is already a
    %% child, which anchors the span by itself.
    %%
    %% `Tptp.Parser` turns these into `%Tptp.Node{}`, attaches spans and collapses
    %% the significant chain rules onto their leaves.

    """
  end

  defp wrap(names) do
    names
    |> Enum.chunk_every(6)
    |> Enum.map_join("\n", &("  " <> Enum.join(&1, " ")))
  end
end
