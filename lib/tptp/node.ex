defmodule Tptp.Node do
  @moduledoc """
  A node of the concrete syntax tree.

  ## Content

  A node records what the grammar matched and nothing further. It carries no type,
  no arity and no scope information, and does not classify `$i` as a type or `a` as
  a term. The grammar itself does not distinguish a THF type from a THF term, so
  the tree does not either; consumers requiring types elaborate them against a
  signature of their own.

  ## Positions

  `off` and `len` are byte offsets into the source. The file identifier is a
  property of the file rather than of each of its nodes, so `span/2` constructs a
  `Tptp.Span` on demand. Storing a span per node would approximately double the
  size of a tree in order to repeat a single value.

  A node's span covers the source it was built from including its own delimiters:
  `[a, b]` spans the brackets and `f(a)` spans the closing parenthesis. The
  generated grammar supplies the parser with the delimiters it omits from
  `children` for this purpose, which makes containment queries — whether a given
  comment falls inside a node — well defined.

  ## `text`

  A leaf carrying text — a word, a number, a quoted atom — has `text` set to a
  sub-binary of the source rather than a copy. Leaves whose spelling is determined
  by their kind, such as `:vline`, `:iff` and `:big_forall`, have `text: nil`. The
  invariant is that a non-`nil` `text` equals `binary_part(source, off, len)`.

  Sub-binaries keep the source reachable. `Tptp.File` retains it for that reason;
  `Tptp.detach/1` produces a copy owning its own binaries.

  ## `text` and `value/1`

  `text` is the spelling as written. It is not the identity of the symbol. The BNF
  defines a `<single_quoted>` as the enclosed `<atomic_word>` without the quotes,
  so `cat` and `'cat'` denote the same atomic word, and `'it\'s'` is one word whose
  fifth byte is an apostrophe. `text` retains quotes and escapes because the
  printer must reproduce the input.

  Symbol identity must therefore be taken from `value/1`. A table keyed on `text`
  separates one symbol into two entries, and a signature derived from it inherits
  that separation: `p` and `'p'` become distinct constants that never unify, which
  is unsound in whatever is built above.

  ## Production indices

  The generated grammar numbers the alternatives of each nonterminal. The parser
  discards that number: a node records the kind that produced it and its children,
  not which alternative was taken. Kind and children determine the alternative
  except in one case. Of the 28 nonterminals with more than one node-building
  alternative, only `<cnf_literal>` has two alternatives that agree on both, `~p`
  and `~(p)` each yielding a `:cnf_literal` over a single `:constant`.

  This does not affect `shape/1` or the printer round trip, which is why the index
  is not retained.

  ## Kinds

  `kind` is the grammar nonterminal that produced the node, or the token category
  for a leaf. The generator splices out chain rules such as `<functor> ::=
  <atomic_word>`, except for the significant ones listed in
  `Tptp.Bnf.Generator.significant/0`, which are collapsed onto their leaf so that
  the leaf retains the role the chain assigned it:

      f in f(a)           ->  %Node{kind: :functor,  text: "f"}
      f in p(f)           ->  %Node{kind: :constant, text: "f"}
      $i in tff(_,type,_) ->  %Node{kind: :defined_type, text: "$i"}

  This records the role of a symbol without additional nodes, and allows a lint
  rule to distinguish a constant from a functor without inspecting ancestors.

  The third example is TFF. In a THF statement the same `$i` arrives as
  `:defined_constant`, since TFF has separate productions for types and terms and
  THF does not. This reflects a distinction the language does not draw.

  ## Construction

  Nodes are ordinarily produced by the parser. Consumers that emit TPTP — a prover
  backend, a translation to another format, a derivation in TSTP — construct them
  instead. `new/3` defaults `off` and `len` to `0`, since a synthesised node
  corresponds to no source position and supplying a plausible one would produce
  diagnostics pointing at unrelated text. The sub-binary invariant above therefore
  describes parsed trees only.

  `Tptp.Printer.Canonical` operates on `kind`, `text` and `children` alone, so a
  constructed tree prints. Its well-formedness is established by the round trip:
  printing the tree and parsing the result must yield a tree with the same
  `shape/1`. Failure indicates a malformed tree, typically a kind given the wrong
  number of children or a leaf whose text does not lex as its kind.
  """

  alias Tptp.Span

  @enforce_keys [:kind, :off, :len]
  defstruct [:kind, :off, :len, :text, children: []]

  @typedoc """
  One CST node.

  `text` is set on leaves only, as a sub-binary of the file's source, so a tree
  costs no copies. `off` and `len` are byte offsets; a `Tptp.Span` — which needs
  the file id too — is built on demand.
  """
  @type t :: %__MODULE__{
          kind: atom(),
          off: non_neg_integer(),
          len: non_neg_integer(),
          text: binary() | nil,
          children: [t()]
        }

  @doc """
  Returns the node's extent as a span in the given file.
  """
  @spec span(t(), Span.file_id()) :: Span.t()
  def span(%__MODULE__{} = node, file \\ 0), do: Span.new(file, node.off, node.len)

  @doc """
  Returns the bytes the node covers, delimiters included.

  A sub-binary rather than a copy. For a leaf this is `text`; for an interior node
  it is the source of the entire subtree.
  """
  @spec text(t(), binary()) :: binary()
  def text(%__MODULE__{} = node, source) when is_binary(source) do
    binary_part(source, node.off, node.len)
  end

  @doc """
  Constructs a node with no corresponding source position.

  For consumers emitting TPTP rather than reading it. `off` and `len` are `0`,
  since a synthesised node indexes no source and a fabricated offset would be
  reported by any diagnostic referring to it.

  Well-formedness is established by the round trip: print the tree, parse the
  result, and compare `shape/1`.

      iex> alias Tptp.Node
      iex> tree = Node.new(:fof_and_formula, nil, [Node.new(:constant, "p"), Node.new(:constant, "q")])
      iex> text = Tptp.Printer.Canonical.to_string(tree)
      "p & q"
      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, " <> text <> ").")
      iex> Node.shape(statement.formula) == Node.shape(tree)
      true
  """
  @spec new(atom(), binary() | nil, [t()]) :: t()
  def new(kind, text \\ nil, children \\ []) when is_atom(kind) and is_list(children) do
    %__MODULE__{kind: kind, off: 0, len: 0, text: text, children: children}
  end

  @doc """
  Returns the leaf's canonical value: the atomic word rather than its spelling.

  A `<single_quoted>` has its quotes and escapes removed, since the BNF defines
  `cat` and `'cat'` as the same atomic word and `'it\\'s'` as one word containing
  an apostrophe. Any other leaf returns `text` unchanged, and `nil` returns `nil`.

  Use this value to identify a symbol, and `text` to print it.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, 'p'('q')).")
      iex> statement.formula |> Tptp.Node.walk() |> Enum.map(&Tptp.Node.value/1)
      [nil, "p", "q"]

  Distinctions the BNF draws are preserved. A `<distinct_object>` is not an atomic
  word, so `"cat"` denotes neither `'cat'` nor `cat`; and the body of a
  `<back_quoted>` is an `<upper_word>`, which no unquoted atomic word may be.
  Removing either delimiter would assert an identity the BNF does not state, so
  both retain their quotes:

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string(~S|fof(a, axiom, p("cat")).|)
      iex> statement.formula |> Tptp.Node.select(:distinct_object) |> Enum.map(&Tptp.Node.value/1)
      [~S|"cat"|]
  """
  @spec value(t()) :: binary() | nil
  def value(%__MODULE__{text: nil}), do: nil

  def value(%__MODULE__{text: <<?\', body::binary>>}) when byte_size(body) > 0 do
    body |> binary_part(0, byte_size(body) - 1) |> unescape()
  end

  def value(%__MODULE__{text: text}), do: text

  defp unescape(text) do
    if :binary.match(text, "\\") == :nomatch do
      text
    else
      text |> unescape([]) |> IO.iodata_to_binary()
    end
  end

  defp unescape(<<?\\, c, rest::binary>>, acc) when c == ?\' or c == ?\\ do
    unescape(rest, [acc, c])
  end

  defp unescape(<<c, rest::binary>>, acc), do: unescape(rest, [acc, c])
  defp unescape(<<>>, acc), do: acc

  @doc """
  Returns whether the node has no children.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> Tptp.Node.leaf?(statement.formula)
      true
  """
  @spec leaf?(t()) :: boolean()
  def leaf?(%__MODULE__{children: []}), do: true
  def leaf?(%__MODULE__{}), do: false

  @doc """
  Returns the nodes of the subtree in pre-order, left to right.

  Lazy: `Enum.find/2` over a large formula halts at the first match rather than
  materialising the full list.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p(X) & q).")
      iex> statement.formula |> Tptp.Node.walk() |> Enum.map(& &1.kind)
      [:fof_and_formula, :fof_plain_term, :functor, :variable, :constant]
  """
  @spec walk(t()) :: Enumerable.t()
  def walk(%__MODULE__{} = node) do
    Stream.resource(fn -> [node] end, &next/1, fn _stack -> :ok end)
  end

  defp next([]), do: {:halt, []}
  defp next([%__MODULE__{children: children} = node | rest]), do: {[node], children ++ rest}

  @doc """
  Folds over the subtree in pre-order.

  The eager counterpart to `walk/1`. Prefer it where the fold visits every node,
  as it avoids the per-element overhead of the stream.
  """
  @spec reduce(t(), acc, (t(), acc -> acc)) :: acc when acc: var
  def reduce(%__MODULE__{} = node, acc, fun) when is_function(fun, 2) do
    Enum.reduce(node.children, fun.(node, acc), &reduce(&1, &2, fun))
  end

  @doc """
  Returns the nodes of the given kind, in source order.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,![X]: p(X)).")
      iex> statement.formula |> Tptp.Node.select(:variable) |> Enum.map(& &1.text)
      ["X", "X"]
  """
  @spec select(t(), atom()) :: [t()]
  def select(%__MODULE__{} = node, kind) when is_atom(kind) do
    node
    |> reduce([], fn
      %__MODULE__{kind: ^kind} = found, acc -> [found | acc]
      _other, acc -> acc
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns the innermost node whose span contains `offset`, or `nil`.

  Descends the tree rather than searching it, so the cost is proportional to depth
  rather than to size.
  """
  @spec at(t(), non_neg_integer()) :: t() | nil
  def at(%__MODULE__{} = node, offset) when is_integer(offset) do
    if offset >= node.off and offset < node.off + node.len do
      Enum.find_value(node.children, node, &at(&1, offset))
    end
  end

  @doc """
  Returns the subtree with positions removed, for comparison by structure.

  Used by the printer round-trip property: `from_string(print(tree))` must have the
  same shape as `tree`, though every offset in it differs.

      iex> {:ok, one, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> {:ok, two, []} = Tptp.Parser.statement_from_string("fof( a , axiom , p ).")
      iex> Tptp.Node.shape(one.formula) == Tptp.Node.shape(two.formula)
      true
  """
  @spec shape(t()) :: tuple()
  def shape(%__MODULE__{} = node) do
    {node.kind, node.text, Enum.map(node.children, &shape/1)}
  end

  @doc """
  Returns a deep copy of the subtree with each `text` detached from the source.

  Every leaf's `text` is ordinarily a sub-binary of the source, so retaining one
  leaf retains the whole file. Copying each leaf's bytes allows the source to be
  collected. Use it when keeping a small number of statements from a large file.
  """
  @spec detach(t()) :: t()
  def detach(%__MODULE__{} = node) do
    %{
      node
      | text: node.text && :binary.copy(node.text),
        children: Enum.map(node.children, &detach/1)
    }
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # The derived implementation prints the entire subtree, which may be arbitrarily
    # large. This prints the node's kind, its spelling if it is a leaf, its number of
    # children and its extent. Use `Tptp.Node.walk/1` or `shape/1` to inspect the
    # subtree, or `inspect(node, structs: false)` for the underlying map.
    @impl true
    def inspect(node, opts) do
      concat([
        "#Tptp.Node<",
        to_doc(node.kind, opts),
        text(node.text, opts),
        children(node.children),
        " ",
        "#{node.off}..#{node.off + node.len}",
        ">"
      ])
    end

    defp text(nil, _opts), do: empty()
    defp text(text, opts), do: concat(" ", to_doc(text, opts))

    defp children([]), do: empty()
    defp children([_one]), do: ", 1 child"
    defp children(list), do: ", #{length(list)} children"
  end
end
