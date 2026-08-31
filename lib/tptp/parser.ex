defmodule Tptp.Parser do
  @moduledoc """
  Turns one statement's tokens into a `Tptp.Statement`.

  The grammar itself is generated: `mix tptp.gen` translates the `::=` rules of the
  vendored BNF into `src/tptp_parser.yrl`, and `yecc` compiles that to an LALR(1)
  parser. This module drives it and converts what it hands back.

  ## One statement at a time

  `yecc` has no error recovery: a parser generated from a whole-file grammar stops
  at the first bad byte and reports nothing about the rest. Parsing per statement
  makes recovery structural rather than clever — a statement that fails to parse
  becomes a diagnostic and the file carries on. It also bounds the blast radius on
  hostile input, gives the editor path an incremental unit (find the statement
  containing offset *n*, reparse it, splice), and makes statements a parallelism
  unit.

  ## The post-pass

  The generated actions build three shapes — `{'$node', kind, alt, children, open,
  close}`, `{'$leaf', category, alt, token}` and raw tokens spliced through from
  chain rules — and a single bottom-up walk turns them into `Tptp.Node`:

    * **Spans are composed**, not carried by the actions, which keeps every action
      one template. `open` and `close` are the production's delimiters, which the
      generator drops from `children` and hands over separately, so a node's span
      covers its own brackets.
    * **Leaf text is materialised** with `binary_part/3` — a sub-binary, no copy.
    * **Significant chain rules collapse onto their leaf.** When one of the
      role-naming nonterminals in `Tptp.Bnf.Generator.significant/0` wraps a single
      text-carrying leaf, the node becomes that leaf and keeps the outer kind, so
      `f` in `p(f)` arrives as `:constant` and `f` in `f(a)` as `:functor` at no
      cost in nodes. The set is curated, not "any single child": `<tff_arguments>
      ::= <tff_term>` is the same shape, but its child is an argument rather than
      a rename, and collapsing it would erase what the argument was.

  ## Polymorphic constants

  Nothing here elaborates, saturates, uncurries or instantiates anything. `f @ $i @
  a` keeps its full left-nested apply spine with `$i` present as an ordinary
  argument carrying its own kind and span; `!!`, `??`, `@@+`, `@@-` and `@=` arrive
  as their own leaf kinds; `!>` and `?*` schemes are kept verbatim. Guide §14 puts
  every bit of that in `holtk`, and the CST cannot help there anyway — the TPTP
  grammar does not distinguish a THF type from a THF term, so neither can this
  tree.
  """

  alias Tptp.Diagnostic
  alias Tptp.Input
  alias Tptp.Node
  alias Tptp.Span
  alias Tptp.Splitter
  alias Tptp.Statement.Annotated
  alias Tptp.Statement.Include
  alias Tptp.Token

  @syntax_error "TPTP0301"
  @unexpected_end "TPTP0302"
  @not_a_statement "TPTP0303"

  @value_categories Token.value_categories()
  @significant Tptp.Bnf.Generator.significant()

  @annotated [
    thf_annotated: :thf,
    tff_annotated: :tff,
    tcf_annotated: :tcf,
    fof_annotated: :fof,
    cnf_annotated: :cnf,
    tpi_annotated: :tpi
  ]

  @annotated_kinds Keyword.keys(@annotated)

  @typedoc """
  A parse either produces a statement or explains why it could not.

  Diagnostics ride along with success too: a statement can parse and still be worth
  complaining about, and the caller decides what is fatal.
  """
  @type result ::
          {:ok, Tptp.Statement.t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}

  @doc """
  Parse one split input.

  `source` is the file the input's offsets index into; `file` is the id stamped
  into any diagnostic's span.

      iex> {[input], _comments, []} = Tptp.Splitter.inputs("fof(a,axiom,p).")
      iex> {:ok, statement, []} = Tptp.Parser.statement_from_input(input, "fof(a,axiom,p).")
      iex> {statement.language, statement.name.text, statement.role.text}
      {:fof, "a", "axiom"}
  """
  @spec statement_from_input(Input.t(), binary(), Span.file_id()) :: result()
  def statement_from_input(input, source, file \\ 0)

  def statement_from_input(%Input{language: :unknown} = input, _source, _file) do
    {:error, input.diagnostics}
  end

  def statement_from_input(%Input{} = input, source, file) when is_binary(source) do
    case :tptp_parser.parse(input.tokens) do
      {:ok, tree} ->
        {:ok, statement(tree, input, source), input.diagnostics}

      {:error, reason} ->
        {:error, [syntax_diagnostic(reason, input, source, file) | input.diagnostics]}
    end
  end

  @doc """
  Parse a source that holds exactly one statement.

  A convenience for tests, doctests and single-formula input such as a prover's
  answer. Anything file-shaped wants `Tptp.from_string/2`, which reports every
  statement rather than refusing the second.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("cnf(c,axiom,p | ~q).")
      iex> statement.language
      :cnf
  """
  @spec statement_from_string(binary(), Span.file_id()) :: result()
  def statement_from_string(source, file \\ 0) when is_binary(source) do
    case Splitter.inputs(source, file) do
      {[input], _comments, _diagnostics} ->
        statement_from_input(input, source, file)

      {inputs, _comments, diagnostics} ->
        {:error, [one_statement_diagnostic(inputs, file) | diagnostics]}
    end
  end

  defp one_statement_diagnostic(inputs, file) do
    Diagnostic.new(
      @not_a_statement,
      :error,
      Span.new(file, 0, 0),
      "expected exactly one statement, found #{length(inputs)}",
      hint: "use `Tptp.from_string/2` for a source that holds more than one"
    )
  end

  @spec syntax_diagnostic({term(), module(), term()}, Input.t(), binary(), Span.file_id()) ::
          Diagnostic.t()
  defp syntax_diagnostic({_offset, _module, [_prefix, []]}, input, _source, file) do
    truncated(input, file)
  end

  defp syntax_diagnostic({offset, _module, _message}, input, source, file) do
    case Enum.find(input.tokens, fn {_category, at, _length} -> at == offset end) do
      nil ->
        truncated(input, file)

      {category, at, length} = token ->
        Diagnostic.new(
          @syntax_error,
          :error,
          Span.new(file, at, length),
          "unexpected #{describe(category, token, source)}",
          hint: "the grammar for a `#{input.language}` statement does not allow it here"
        )
    end
  end

  defp truncated(input, file) do
    {_category, at, length} = List.last(input.tokens)

    Diagnostic.new(
      @unexpected_end,
      :error,
      Span.new(file, at, length),
      "the statement ends before the grammar expects it to",
      hint: "an incomplete `#{input.language}` statement"
    )
  end

  defp describe(category, {_category, offset, length}, source) do
    case Token.spelling(category) do
      nil -> "`#{binary_part(source, offset, length)}`"
      spelling -> "`#{spelling}`"
    end
  end

  @spec statement(term(), Input.t(), binary()) :: Tptp.Statement.t()
  defp statement(
         {:"$node", kind, _alt, [name, role, formula, annotations], _open, _close},
         input,
         source
       )
       when kind in @annotated_kinds do
    {origin, info} = annotations(annotations, source)

    %Annotated{
      language: Keyword.fetch!(@annotated, kind),
      name: build(name, source),
      role: build(role, source),
      formula: build(formula, source),
      source: origin,
      info: info,
      off: input.offset,
      len: input.length
    }
  end

  defp statement({:"$node", :include, _alt, [file_name, optionals], _open, _close}, input, source) do
    {selection, space_name} = include_optionals(optionals, source)

    %Include{
      file_name: build(file_name, source),
      selection: selection,
      space_name: space_name,
      off: input.offset,
      len: input.length
    }
  end

  defp annotations(nil, _source), do: {nil, nil}

  defp annotations({:"$node", :annotations, _alt, [origin, info], _open, _close}, source) do
    {build(origin, source), build(unwrap(info, :optional_info), source)}
  end

  defp include_optionals(nil, _source), do: {nil, nil}

  defp include_optionals(
         {:"$node", :include_optionals, _alt, [selection, space], _open, _close},
         source
       ) do
    {build(selection, source), build(space, source)}
  end

  defp include_optionals(
         {:"$node", :include_optionals, _alt, [selection], _open, _close},
         source
       ) do
    {build(selection, source), nil}
  end

  defp include_optionals(selection, source), do: {build(selection, source), nil}

  @spec unwrap(term(), atom()) :: term()
  defp unwrap({:"$node", kind, _alt, [only], _open, _close}, kind), do: only
  defp unwrap(other, _kind), do: other

  @spec build(term(), binary()) :: Node.t() | nil
  defp build(nil, _source), do: nil

  defp build({:"$node", kind, _alt, children, open, close}, source) do
    converted = children |> Enum.map(&build(&1, source)) |> Enum.reject(&is_nil/1)

    case converted do
      [%Node{children: [], text: text} = only] when kind in @significant and is_binary(text) ->
        %{only | kind: kind}

      _otherwise ->
        {off, len} = extent(open, close, converted)
        %Node{kind: kind, off: off, len: len, children: converted}
    end
  end

  defp build({:"$leaf", category, _alt, {_category, offset, length}}, source) do
    leaf(category, offset, length, source)
  end

  defp build({category, offset, length}, source) when is_atom(category) do
    leaf(category, offset, length, source)
  end

  defp leaf(category, offset, length, source) when category in @value_categories do
    %Node{kind: category, off: offset, len: length, text: binary_part(source, offset, length)}
  end

  defp leaf(category, offset, length, _source) do
    %Node{kind: category, off: offset, len: length}
  end

  @spec extent(Token.t() | nil, Token.t() | nil, [Node.t()]) ::
          {non_neg_integer(), non_neg_integer()}
  defp extent(open, close, children) do
    from = opens_at(open, children)
    {from, closes_at(close, children) - from}
  end

  defp opens_at({_category, offset, _length}, _children), do: offset
  defp opens_at(nil, [%Node{off: offset} | _rest]), do: offset

  defp closes_at({_category, offset, length}, _children), do: offset + length
  defp closes_at(nil, children), do: children |> List.last() |> then(&(&1.off + &1.len))
end
