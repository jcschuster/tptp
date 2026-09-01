defmodule Tptp.Node do
  @moduledoc """
  One node of the concrete syntax tree.

  ## What a node is, and what it deliberately is not

  A node is a faithful record of what the grammar matched, and nothing more. It
  carries no type, no arity, no scope, no notion that `$i` is a type and `a` is a
  term. That boundary is the point: the TPTP grammar cannot distinguish a THF type
  from a THF term, so neither can this tree, and pretending otherwise would mean
  guessing. Consumers that need types elaborate them themselves.

  ## Offsets, not spans

  `off` and `len` are bare byte offsets. The file id belongs to the file, not to
  each of its millions of nodes, so `span/2` builds a `Tptp.Span` on demand when a
  diagnostic needs one. Carrying a span struct per node would roughly double the
  size of a tree to repeat one number.

  A node's span covers exactly the source it was built from, its own brackets
  included — `[a, b]` spans the brackets, `f(a)` spans the closing paren. The
  generated grammar hands the parser the delimiters it drops from `children` for
  precisely this reason, so "is this comment inside this node?" has an answer.

  ## `text` is set on leaves, and is a sub-binary

  A leaf that carries text — a word, a number, a quoted atom — has `text` set to a
  sub-binary of the file, not a copy. Leaves whose spelling is fixed by their kind
  (`:vline`, `:iff`, `:big_forall`) have `text: nil`, because the kind already says
  what the bytes are. So the invariant is: when `text` is not `nil`, it equals
  `binary_part(source, off, len)`.

  Sub-binaries keep the whole file alive, which is what `Tptp.File` is for — it
  retains `source`, so nothing dangles. `Tptp.detach/1` is the escape hatch for a
  consumer that wants to keep a statement and drop the file.

  ## `text` is the spelling; `value/1` is the atomic word

  `text` is faithful, and faithfulness is not identity. The BNF is explicit that a
  `<single_quoted>` is "the enclosed `<atomic_word>` without the quotes", so `cat`
  and `'cat'` are *the same atomic word* written two ways, and `'it\\'s'` is one
  word whose fifth byte is an apostrophe. `text` carries the spelling — quotes,
  escapes and all — because the printer has to write back what was read.

  Anything that identifies a symbol must therefore key on `value/1` rather than on
  `text`. A table keyed on the spelling splits one symbol in two, and a consumer
  that builds a signature out of it inherits the split: `p` and `'p'` become two
  constants that never clash, which is a soundness bug in whatever is built on top
  rather than a cosmetic one here.

  ## The alternative index is not kept

  The generated grammar numbers a nonterminal's productions, and the parser drops
  that number: a node records the kind that built it and the children it got, and
  nothing about which `|` branch was taken. Kind and children recover the branch
  almost everywhere. Across the 28 nonterminals with more than one node-building
  alternative there is exactly one pair they do not separate — `<cnf_literal>`,
  where `~p` and `~(p)` both arrive as a `:cnf_literal` over one `:constant`.

  That is harmless for `shape/1` and for the printer round-trip, which is why the
  index is not carried; it is written down here so nobody has to rediscover it by
  finding two source spellings with one shape.

  ## Kinds, and what the chain rules leave behind

  `kind` is the grammar nonterminal that built the node, or the token category for
  a leaf. The generator splices away chain rules — `<functor> ::= <atomic_word>`
  and the like — but the *significant* ones are collapsed onto their leaf instead
  of being dropped, so the leaf keeps what the chain said about it:

      f in f(a)          ->  %Node{kind: :functor,  text: "f"}
      f in p(f)          ->  %Node{kind: :constant, text: "f"}
      $i in tff(_,type,_) ->  %Node{kind: :defined_type, text: "$i"}

  That is symbol-role information at zero extra nodes, and it is what lets a lint
  rule tell a constant from a functor without walking back up the tree.

  The third line is deliberately a TFF example. The same `$i` in a THF statement
  arrives as `:defined_constant`, because TFF has separate grammar rules for types
  and terms and THF does not. That is not a gap to paper over — it is the
  distinction the language itself declines to make.

  ## Constructing a tree

  Most nodes come from the parser, and a few do not: a consumer that emits TPTP —
  a prover backend, a bridge to another tool, a TSTP derivation it wrote itself —
  builds nodes rather than reading them. `new/3` is the constructor for that, and
  it defaults `off` and `len` to `0` because a synthesized node has no source to
  point into and inventing plausible offsets would be a lie a diagnostic would
  later repeat. So the sub-binary invariant above is a statement about parsed
  trees; a constructed node says "not from a file" by spanning nothing.

  `Tptp.Printer.Canonical` works from `kind`, `text` and `children` alone, so a
  constructed tree prints. Whether it prints *correctly* is the round trip:
  printing it and parsing the result must give a tree with the same `shape/1`. A
  hand-built tree that fails that check is malformed — a kind that takes three
  children given two, a leaf whose text does not lex as its kind — and the failure
  is the same one the printer's own property test makes over the whole library.
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
  The node's extent, as a span in the file it was read from.
  """
  @spec span(t(), Span.file_id()) :: Span.t()
  def span(%__MODULE__{} = node, file \\ 0), do: Span.new(file, node.off, node.len)

  @doc """
  The bytes the node covers, brackets included.

  A sub-binary, not a copy. For a leaf this is `text`; for an interior node it is
  the source the whole subtree came from.
  """
  @spec text(t(), binary()) :: binary()
  def text(%__MODULE__{} = node, source) when is_binary(source) do
    binary_part(source, node.off, node.len)
  end

  @doc """
  Build a node that did not come from a file.

  For a consumer emitting TPTP rather than reading it. `off` and `len` are `0`:
  a synthesized node points into no source, and saying so is better than inventing
  an offset that a diagnostic would later quote.

  The round trip is the validity check — print it, parse it back, compare `shape/1`:

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
  The leaf's canonical value: an atomic word rather than its spelling.

  A `<single_quoted>` loses its quotes and its escapes, because the BNF says `cat`
  and `'cat'` are the same atomic word and `'it\\'s'` is one word containing an
  apostrophe. Everything else is `text` unchanged, and `nil` stays `nil`.

  This is the key to identify a symbol by. `text` is the key to print.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, 'p'('q')).")
      iex> statement.formula |> Tptp.Node.walk() |> Enum.map(&Tptp.Node.value/1)
      [nil, "p", "q"]

  Two spellings the BNF keeps apart stay apart. A `<distinct_object>` is not an
  atomic word — `"cat"` is a different thing from `'cat'` and from `cat` — and a
  `<back_quoted>`'s body is an `<upper_word>`, which no unquoted atomic word can
  be, so stripping either delimiter would assert an identity the BNF never states.
  Both keep their quotes:

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
  Whether the node has no children.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a,axiom,p).")
      iex> Tptp.Node.leaf?(statement.formula)
      true
  """
  @spec leaf?(t()) :: boolean()
  def leaf?(%__MODULE__{children: []}), do: true
  def leaf?(%__MODULE__{}), do: false

  @doc """
  Every node of the subtree, parents before children, left to right.

  Lazy, so `Enum.find/2` over a large formula stops at the first hit rather than
  building the whole list.

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
  Fold over the subtree, parents before children.

  The eager counterpart to `walk/1`, and the one to reach for when the fold visits
  every node anyway — it avoids the stream's per-element overhead, which is the
  difference that shows up when `Tptp.Lint` walks a 455 MB file.
  """
  @spec reduce(t(), acc, (t(), acc -> acc)) :: acc when acc: var
  def reduce(%__MODULE__{} = node, acc, fun) when is_function(fun, 2) do
    Enum.reduce(node.children, fun.(node, acc), &reduce(&1, &2, fun))
  end

  @doc """
  Every node of `kind`, in reading order.

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
  The innermost node whose span contains `offset`, or `nil`.

  What an editor asks when the cursor moves. Descends rather than searching, so it
  costs the depth of the tree rather than its size.
  """
  @spec at(t(), non_neg_integer()) :: t() | nil
  def at(%__MODULE__{} = node, offset) when is_integer(offset) do
    if offset >= node.off and offset < node.off + node.len do
      Enum.find_value(node.children, node, &at(&1, offset))
    end
  end

  @doc """
  The subtree with every offset erased, for comparing shape rather than position.

  This is what the printer round-trip property compares: `from_string(print(tree))`
  must have the same shape as `tree`, but every offset in it will differ.

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
  A deep copy of the subtree, with every `text` detached from the source binary.

  Every leaf's `text` is a sub-binary of the file it was read from, so holding one
  leaf holds the whole file. That is the right trade while the file is in hand and
  the wrong one for a consumer that keeps a handful of statements from a 455 MB
  axiom set. This copies each leaf's bytes so the file can be collected.
  """
  @spec detach(t()) :: t()
  def detach(%__MODULE__{} = node) do
    %{
      node
      | text: node.text && :binary.copy(node.text),
        children: Enum.map(node.children, &detach/1)
    }
  end
end
