defmodule Tptp.Lint.Collect do
  @moduledoc """
  Constructs the symbol table and the dialect feature set during the traversal.

  Not a rule. It is applied before the rules at every node and produces the data
  read afterwards by the `c:Tptp.Lint.Rule.review/2` callbacks, which is what
  allows `Tptp.Lint` to require a single pass.

  ## Declarations

  A `type`-role statement whose formula is an atom typing, such as
  `tff(f_decl, type, f: $i > $o).` The subject is recorded as declared and the
  right-hand side of the colon is stored verbatim as the declared type. It is not
  interpreted.

  ## Uses

  A `constant`, `functor`, `defined_functor` or `system_functor`, or their nullary
  counterparts, occurring within a formula — not within a name, role, source or
  info field. Never a `variable`: in `X @ a` the head is bound by its quantifier
  rather than declared by a `type` statement.

  The annotations contain atoms indistinguishable in form from symbols that are not
  symbols: `file` in a `<source>` is a keyword and `status(thm)` is a label.
  Counting them would report the TSTP vocabulary as undeclared.

  An `<ntf_index>` is the second such position. In `{$necessary(#agent)}` the word
  `agent` labels a modality rather than denoting a constant of the problem's
  signature, and `SYN000^7.p`, the reference example for the syntax, declares no
  type for it. The subtree beneath an `ntf_index` is therefore claimed before the
  traversal reaches it, and none of it is counted.

  ## Symbol identity

  `'p'` and `p` denote one symbol, since the BNF defines a `<single_quoted>` as the
  enclosed atomic word without its quotes. Every key passed to `Tptp.Lint.Table` is
  therefore taken from `Tptp.Node.value/1` rather than from `text`. Keying on the
  spelling separates `tff(t, type, 'p': $i > $o). tff(a, axiom, p(x)).` into two
  entries, producing a spurious undeclared-symbol finding and a missed duplicate
  name, and propagates the separation to anything built on
  `Tptp.Query.symbols/1`. The same applies to statement names and to the names an
  inference record supplies as parents, since `<name> ::= <atomic_word> |
  <integer>`.

  ## Arity

  Arity is the length of the application spine, recorded at the application node.
  `f(a, b)` is a `fof_plain_term` with a functor and an argument list, so the arity
  is the length of that list; `f @ a @ b` is a left-nested application spine, so the
  arity is its depth. Both are recorded and neither is evaluated here.

  Argument lists differ in shape between dialects, and the difference originates in
  the BNF rather than the generator: `<fof_arguments> ::= <fof_term> |
  <fof_term>,<fof_arguments>` nests to the right, while `<tff_arguments> ::=
  <tff_term><comma_tff_term>*` is flat. `p(x, y, z)` is therefore a two-child node
  in FOF and a three-child node in TFF, and counting children directly would give
  the FOF form an arity of two. The count recurses through children of the same
  kind instead, which is correct for both.
  """

  alias Tptp.Bnf.Vocabulary
  alias Tptp.Lint.Context
  alias Tptp.Lint.Table
  alias Tptp.Node
  alias Tptp.Statement.Annotated

  @symbol_kinds [
    :constant,
    :functor,
    :defined_constant,
    :defined_functor,
    :system_constant,
    :system_functor,
    :type_constant,
    :type_functor
  ]

  @applications [
    :fof_plain_term,
    :fof_defined_plain_term,
    :fof_system_term,
    :tff_plain_atomic,
    :tff_system_atomic,
    :tff_atomic_type,
    :thf_fof_function
  ]

  @argument_lists [:fof_arguments, :tff_arguments, :tff_type_arguments, :thf_formula_list]

  @lets [:txf_let, :thf_let]
  @typings [:tff_atom_typing, :thf_atom_typing]

  @type_quantifiers [:type_forall, :type_exists]
  @quantified_types [:thf_quantification, :tf1_quantified_type]
  @typed_variables [:thf_typed_variable, :tff_typed_variable]
  @variable_lists [:thf_variable_list, :tff_variable_list]
  @mapping_types [:thf_mapping_type, :tff_mapping_type]
  @type_of_types "$tType"

  @features %{
    big_forall: :th1,
    big_exists: :th1,
    big_choice: :th1,
    big_desc: :th1,
    big_equal: :th1,
    lambda: :higher_order,
    thf_apply_formula: :higher_order,
    thf_tuple: :tuple,
    txf_tuple: :tuple,
    txf_tuple_type: :tuple,
    thf_let: :let_or_ite,
    txf_let: :let_or_ite,
    thf_subtype: :subtype,
    tff_subtype: :subtype,
    thf_sequent: :sequent,
    fof_sequent: :sequent,
    txf_sequent: :sequent,
    nhf_long_connective: :non_classical,
    nxf_long_connective: :non_classical,
    short_bracket: :non_classical,
    short_angle: :non_classical,
    short_brace: :non_classical,
    short_paren: :non_classical,
    ntf_index: :non_classical,
    choice: :choice,
    desc: :choice
  }

  @doc """
  Fold one node into the table.
  """
  @spec observe(Node.t(), Context.t(), Table.t()) :: Table.t()
  def observe(%Node{} = node, %Context{} = context, %Table{} = table) do
    table
    |> note_language(context)
    |> note_feature(node)
    |> note_type_binding(node)
    |> note_statement(node, context)
    |> note_conjecture(node, context)
    |> note_symbol(node, context)
    |> note_parent(node, context)
  end

  @typed ~w(thf tff tcf)a

  defp note_language(table, %Context{} = context) do
    language = Context.language(context)
    table = Table.feature(table, language)

    if language in @typed, do: Table.feature(table, :typed), else: table
  end

  defp note_feature(table, %Node{kind: kind}) do
    case Map.fetch(@features, kind) do
      {:ok, feature} -> Table.feature(table, feature)
      :error -> table
    end
  end

  # What a type quantifier binds says which of two different things it is doing.
  # `!>[A: $tType]` abstracts over a type and is polymorphism; `!>[A: nat]` abstracts
  # over a *term* and is a dependent type, which is DH0/DH1 rather than TH1. Reading
  # the quantifier alone cannot tell them apart, which is why this matches the
  # quantified type rather than the `!>` — and matching the quantified type is also
  # what keeps an ordinary term binder, `![X: $i]`, out of it entirely.
  #
  # `$tType` is spelled `defined_type` in TFF and `defined_constant` in THF, because
  # THF has no separate type nonterminals. The spelling is the same either way, so
  # this asks about the text and lets the kinds differ.
  @spec note_type_binding(Table.t(), Node.t()) :: Table.t()
  defp note_type_binding(table, %Node{kind: kind, children: children})
       when kind in @quantified_types do
    if Enum.any?(children, &(&1.kind in @type_quantifiers)) do
      children
      |> Enum.flat_map(&bound_types/1)
      |> Enum.reduce(table, &Table.feature(&2, feature_for(&1)))
    else
      table
    end
  end

  # A type constructor is declared by an arrow ending in `$tType`. `list: $tType >
  # $tType` takes a type and is polymorphism; `fin: nat > $tType` takes a term and is
  # a dependent type. `$tType` is legal only in type position, so an arrow that ends
  # in one is never a term.
  defp note_type_binding(table, %Node{kind: kind, children: [argument, result]})
       when kind in @mapping_types do
    if type_of_types?(result) do
      Table.feature(table, feature_for(argument))
    else
      table
    end
  end

  defp note_type_binding(table, %Node{}), do: table

  # One bound variable sits directly under the quantification; two or more are
  # wrapped in a list. Matching on the typed-variable kinds rather than on "a node
  # with two children" is what prevents the list itself from being read as a binding —
  # its second child is another variable, whose `text` is nil, which looked exactly
  # like a term type and reported every multi-variable `!>` as a dependent one.
  @spec bound_types(Node.t()) :: [Node.t()]
  defp bound_types(%Node{kind: kind, children: [_variable, bound]}) when kind in @typed_variables,
    do: [bound]

  defp bound_types(%Node{kind: kind, children: variables}) when kind in @variable_lists,
    do: Enum.flat_map(variables, &bound_types/1)

  defp bound_types(%Node{}), do: []

  defp feature_for(node), do: if(type_of_types?(node), do: :polymorphic, else: :dependent)

  defp type_of_types?(%Node{text: @type_of_types}), do: true
  defp type_of_types?(%Node{}), do: false

  defp note_statement(table, %Node{} = node, %Context{slot: :name, depth: 0} = context) do
    case context.statement do
      %Annotated{} -> Table.name(table, Node.value(node) || "", Context.span(context, node))
      _include -> table
    end
  end

  defp note_statement(table, _node, _context), do: table

  defp note_conjecture(table, %Node{} = node, %Context{slot: :role, depth: 0} = context) do
    case Node.value(node) do
      "conjecture" ->
        Table.conjecture(table, :conjecture, Context.span(context, node))

      "negated_conjecture" ->
        Table.conjecture(table, :negated_conjecture, Context.span(context, node))

      _other ->
        table
    end
  end

  defp note_conjecture(table, _node, _context), do: table

  defp note_symbol(table, %Node{kind: kind} = node, %Context{slot: :formula} = context)
       when kind in @symbol_kinds do
    if declaring?(context, node) do
      Table.declare(
        table,
        Node.value(node),
        kind,
        declared_type(context),
        Context.span(context, node)
      )
    else
      Table.use(table, Node.value(node), kind, 0, Context.span(context, node))
    end
  end

  defp note_symbol(table, %Node{kind: kind} = node, %Context{slot: :formula} = context)
       when kind in @applications do
    case node.children do
      [%Node{kind: head_kind, text: name} = head | rest]
      when is_binary(name) and head_kind != :variable ->
        Table.use(table, Node.value(head), head.kind, arity(rest), Context.span(context, head))

      _otherwise ->
        table
    end
  end

  # `$let(a: array(elt2), a := ..., body)` declares `a`, in a scope of its own,
  # inside an ordinary axiom. `declaring?/2` cannot see it: that asks whether the
  # statement's *role* is `type` and whether the node sits at depth 1, and a let
  # binding is neither. So the binding is picked up here, where the shape says it is
  # one, and the walk being top-down means these land before the body's uses of the
  # same name.
  #
  # The subject's position is claimed as well as declared. A `type`-role statement's
  # subject is recognised by `declaring?/2` and never reaches `Table.use/5`, but a let
  # binding is nested, so without the claim the walk reaches the bare `ff` in
  # `ff: ($int * $int) > $int` a moment later, sees no arguments, and records a use at
  # arity 0 — which then reads as `ff` applied at 0 and 2 arguments. `SYN000_4.p`,
  # the TPTP's own TXF syntax demonstration, was reported for exactly that.
  #
  # The table is flat and this does not make it scoped: two `$let`s binding one name
  # produce one entry. That is enough for `Tptp.Lint.Rules.Declaration`, which asks
  # only whether a name was ever declared, and `Table.declare/5` merges rather than
  # reporting a clash, so nothing false comes of it. A rule that wanted to say a let
  # binding shadows a global one would need real scopes.
  defp note_symbol(table, %Node{kind: kind} = node, %Context{slot: :formula} = context)
       when kind in @lets do
    node.children
    |> Enum.take(1)
    |> Enum.flat_map(&bindings/1)
    |> Enum.reduce(table, fn %Node{children: [subject, type | _rest]}, acc ->
      span = Context.span(context, subject)

      acc
      |> Table.declare(Node.value(subject), subject.kind, type, span)
      |> Table.ignore(span)
    end)
  end

  defp note_symbol(table, %Node{kind: :ntf_index} = node, %Context{slot: :formula} = context) do
    node
    |> Node.walk()
    |> Enum.reduce(table, &Table.ignore(&2, Context.span(context, &1)))
  end

  defp note_symbol(
         table,
         %Node{kind: :thf_apply_formula} = node,
         %Context{slot: :formula} = context
       ) do
    case spine(node) do
      {%Node{kind: head_kind, text: name} = head, count}
      when is_binary(name) and head_kind != :variable ->
        Table.use(table, Node.value(head), head.kind, count, Context.span(context, head))

      _otherwise ->
        table
    end
  end

  defp note_symbol(table, _node, _context), do: table

  defp note_parent(table, %Node{kind: :name} = node, %Context{slot: :source} = context) do
    Table.parent(table, Node.value(node) || "", Context.span(context, node))
  end

  defp note_parent(table, _node, _context), do: table

  @doc """
  Whether a statement declares a symbol rather than asserting something.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("tff(d, type, f: $i).")
      iex> Tptp.Lint.Collect.typing?(statement)
      true
  """
  @spec typing?(Annotated.t()) :: boolean()
  def typing?(%Annotated{role: role, formula: formula}) do
    role.text == "type" and formula.kind in [:tff_atom_typing, :thf_atom_typing]
  end

  def typing?(_statement), do: false

  # Every typing in a let's types section, whether it is the bare one the chain rule
  # collapses to or a bracketed list of them. Only the two-child form binds a name;
  # the parenthesised `(a: $i)` wraps another typing and is reached by the walk.
  @spec bindings(Node.t()) :: [Node.t()]
  defp bindings(%Node{} = node) do
    node
    |> Node.reduce([], fn
      %Node{kind: kind, children: [_subject, _type | _rest]} = typing, found
      when kind in @typings ->
        [typing | found]

      _node, found ->
        found
    end)
    |> Enum.reverse()
  end

  defp declaring?(%Context{statement: %Annotated{} = statement} = context, node) do
    context.depth == 1 and typing?(statement) and
      match?([^node | _rest], statement.formula.children)
  end

  defp declaring?(_context, _node), do: false

  defp declared_type(%Context{statement: %Annotated{formula: formula}}) do
    case formula.children do
      [_subject, type | _rest] -> type
      _otherwise -> nil
    end
  end

  defp arity([]), do: 0

  defp arity([%Node{kind: kind} = arguments]) when kind in @argument_lists do
    count(arguments, kind)
  end

  defp arity(rest), do: length(rest)

  defp count(%Node{kind: kind, children: children}, kind) do
    Enum.reduce(children, 0, fn child, total -> total + count(child, kind) end)
  end

  defp count(%Node{}, _kind), do: 1

  defp spine(%Node{kind: :thf_apply_formula, children: [left, _right]}), do: descend(left, 1)
  defp spine(_node), do: nil

  defp descend(%Node{kind: :thf_apply_formula, children: [left, _right]}, count) do
    descend(left, count + 1)
  end

  defp descend(%Node{} = node, count), do: {node, count}

  @doc """
  Whether a `$`-word is one the BNF mentions anywhere.

  Every `$`-literal in every rule, not only the closed vocabularies: several
  reserved words appear beside other symbols rather than alone —
  `<ntf_domains_spec> :== $domains <identical> <ntf_domains_value>` — and checking
  only the closed lists reports those as unknown.

      iex> Tptp.Lint.Collect.known_dollar_word?("$sum")
      true
      iex> Tptp.Lint.Collect.known_dollar_word?("$wibble")
      false
  """
  @spec known_dollar_word?(binary()) :: boolean()
  def known_dollar_word?(word) when is_binary(word), do: Vocabulary.reserved_word?(word)
end
