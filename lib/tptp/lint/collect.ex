defmodule Tptp.Lint.Collect do
  @moduledoc """
  Builds the symbol table and the dialect feature set, during the one traversal.

  This is not a rule. It runs before the rules at every node and produces what the
  `c:Tptp.Lint.Rule.review/2` callbacks read afterwards, which is why the walk in
  `Tptp.Lint` costs one pass rather than one per thing that needs to know something.

  ## What counts as a declaration

  A `type`-role statement whose formula is an atom typing: `tff(f_decl, type, f: $i
  > $o).` The subject is declared, the right of the colon is stored verbatim as the
  declared type, and nothing about it is interpreted.

  ## What counts as a use

  A `constant`, `functor`, `defined_functor`, `system_functor` or their nullary
  counterparts, appearing in a formula — not in a name, a role, a source or an
  info. Never a `variable`: `X @ a` applies a bound variable, and a variable is
  bound by its quantifier rather than declared by a `type` statement. The annotations are full of atoms that look exactly like symbols and are
  not: `file` in a `<source>` is a keyword, `status(thm)` is a label, and a rule
  that counted them would report the whole TSTP vocabulary as undeclared.

  An `<ntf_index>` is the other place a word looks like a symbol and is not.
  `{$necessary(#agent)}` names a modality; `agent` is that modality's label, not a
  constant of the problem's signature, and `SYN000^7.p` — the reference example for
  the syntax — declares no type for it. So the whole subtree under an `ntf_index`
  is claimed before the walk reaches it, and none of it is counted.

  ## Symbols are keyed by their canonical value, not their spelling

  `'p'` and `p` are one symbol — the BNF says a `<single_quoted>` is the enclosed
  atomic word without its quotes — so every key handed to `Tptp.Lint.Table` comes
  from `Tptp.Node.value/1` rather than from `text`. Keying on the spelling splits
  `tff(t, type, 'p': $i > $o). tff(a, axiom, p(x)).` into two entries, which is a
  false undeclared-symbol finding, a missed arity clash and a missed duplicate
  name all at once, and hands the same split to anything built on
  `Tptp.Query.symbols/1`. The same goes for statement names and for the names an
  inference record gives as parents: `<name> ::= <atomic_word> | <integer>`, so a
  statement named `a` really is the statement a later `inference(r, [], ['a'])`
  refers to.

  ## Arity is the spine length, counted where the application node is

  `f(a, b)` is a `fof_plain_term` with a functor and an argument list, so the arity
  is the length of that list. `f @ a @ b` is a left-nested apply spine, so the arity
  is how deep the spine runs. Both are recorded; neither is judged here.

  The argument lists are not all the same shape, and the difference is in the BNF
  rather than in the generator: `<fof_arguments> ::= <fof_term> | <fof_term>,<fof_arguments>`
  nests to the right, while `<tff_arguments> ::= <tff_term><comma_tff_term>*` is
  flat. So `p(x, y, z)` is a two-child node in FOF and a three-child node in TFF,
  and counting children would call the first one binary. The count recurses through
  same-kind children instead, which is right for both.
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

  @features %{
    type_forall: :polymorphic,
    type_exists: :polymorphic,
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
