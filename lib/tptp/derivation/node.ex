defmodule Tptp.Derivation.Node do
  @moduledoc """
  One named statement of a derivation, and where it says it came from.

  ## `origin`

  `<source>` is not one thing. A statement may name the file it was read from, an
  inference record, another statement by name, an introduction a system made of its
  own accord, or a bracketed list of alternative derivations. `origin` records
  which of those was written and the parts of it that are not a graph edge — a file
  name, an `<intro_type>` — while `parents` and `steps` record the structure.

  `:none` is a statement with no annotations at all, and `{:name, word}` a whole
  source that is a bare `<name>`: `<dag_source> ::= <name> | <inference_record>`,
  so a statement may be justified by naming another, and the literal `unknown`
  parses as a `<name>` too. `{:unknown, node}` is any shape this list does not
  cover, including a bracketed source whose alternatives are not all inference
  records; the node is kept, so nothing is lost by not classifying it.

  ## `parents` and `steps`

  `parents` is the graph: every `<name>` reachable in a parent position, in source
  order, each once. The `<name>` of a `<file_source>` is not one of them — in
  `file('x.p', ax1)` the formula `ax1` lives in `x.p` and is not a statement of
  this file — and neither is the `<inference_rule>` or the `<file_name>`, neither of
  which is a `<name>` to the grammar.

  `steps` has one list per alternative source, each list flattened by
  `Tptp.Derivation.Step.from_record/1`, and is `[]` when nothing in the source is
  an inference record. The names in `steps` and the names in `parents` are the same
  names; `parents` is what the graph is built from, because a step list also refers
  to records that are not statements.
  """

  alias Tptp.Derivation.Step
  alias Tptp.Node
  alias Tptp.Statement.Annotated

  @enforce_keys [:name, :statement, :origin, :steps, :parents]
  defstruct [:name, :statement, :origin, :steps, :parents]

  @typedoc """
  What a statement says it came from, as written.

  `info` and `node` are subtrees as parsed: an `<intro_type>`'s `<useful_info>`
  carries a system's own account of what it introduced, which this library does not
  interpret.
  """
  @type origin ::
          {:file, file_name :: binary(), formula :: binary() | nil}
          | {:introduced, intro_type :: binary(), info :: Node.t()}
          | {:name, binary()}
          | :inference
          | :none
          | {:unknown, Node.t()}

  @typedoc "One statement of a derivation: its name, its source as classified, and its edges."
  @type t :: %__MODULE__{
          name: binary(),
          statement: Annotated.t(),
          origin: origin(),
          steps: [[Step.t()]],
          parents: [binary()]
        }

  @doc """
  Read one annotated statement as a node of a derivation.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, p, file('x.p', ax1)).")
      iex> node = Tptp.Derivation.Node.from_statement(statement)
      iex> {node.name, node.origin, node.parents}
      {"a", {:file, "x.p", "ax1"}, []}

      iex> {:ok, statement, []} =
      ...>   Tptp.Parser.statement_from_string("cnf(c, plain, $false, inference(sr, [status(thm)], [c_1, c_2])).")
      iex> node = Tptp.Derivation.Node.from_statement(statement)
      iex> {node.origin, node.parents, length(hd(node.steps))}
      {:inference, ["c_1", "c_2"], 1}
  """
  @spec from_statement(Annotated.t()) :: t()
  def from_statement(%Annotated{} = statement) do
    %__MODULE__{
      name: Node.value(statement.name),
      statement: statement,
      origin: origin(statement.source),
      steps: steps(statement.source),
      parents: statement.source |> parent_nodes() |> Enum.map(&Node.value/1) |> Enum.uniq()
    }
  end

  @doc """
  Every `<name>` node in a parent position of a `<source>`, in source order.

  One entry per occurrence, so a name written twice is here twice. `parents` holds
  the same names once each; these are the nodes, for a caller that needs their
  positions.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(b, plain, q, inference(rw, [], [a, a])).")
      iex> statement.source |> Tptp.Derivation.Node.parent_nodes() |> Enum.map(&Tptp.Node.value/1)
      ["a", "a"]
  """
  @spec parent_nodes(Node.t() | nil) :: [Node.t()]
  def parent_nodes(nil), do: []
  def parent_nodes(%Node{kind: :name} = source), do: [source]

  def parent_nodes(%Node{kind: :inference_record, children: [_rule, _info, parents]}) do
    in_parents(parents)
  end

  def parent_nodes(%Node{kind: :internal_source, children: [_type, _info, parents]}) do
    in_parents(parents)
  end

  def parent_nodes(%Node{kind: :source, children: [child]}) do
    child |> alternatives() |> Enum.flat_map(&parent_nodes/1)
  end

  def parent_nodes(%Node{}), do: []

  @doc """
  The alternative sources of a bracketed `<source>`, in source order.

  `<sources> ::= <source> | <source>,<sources>` nests to the right, so three
  alternatives arrive as two nodes. This takes the one child of a `:source` node
  and returns the alternatives it holds.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(b, plain, q, [a, c, d]).")
      iex> [child] = statement.source.children
      iex> child |> Tptp.Derivation.Node.alternatives() |> Enum.map(&Tptp.Node.value/1)
      ["a", "c", "d"]
  """
  @spec alternatives(Node.t()) :: [Node.t()]
  def alternatives(%Node{kind: :sources, children: [left, right]}),
    do: [left | alternatives(right)]

  def alternatives(%Node{} = source), do: [source]

  @spec origin(Node.t() | nil) :: origin()
  defp origin(nil), do: :none
  defp origin(%Node{kind: :name} = source), do: {:name, Node.value(source)}

  defp origin(%Node{kind: :file_source, children: [file]}), do: {:file, Node.value(file), nil}

  defp origin(%Node{
         kind: :file_source,
         children: [file, %Node{kind: :file_info, children: [name]}]
       }) do
    {:file, Node.value(file), Node.value(name)}
  end

  defp origin(%Node{kind: :internal_source, children: [type, info, _parents]}) do
    {:introduced, Node.value(type), info}
  end

  defp origin(%Node{kind: :inference_record}), do: :inference

  # A bracketed source records alternative derivations of the same statement. They
  # are steps only if every one of them is an inference record; otherwise the shape
  # is handed back whole, and `steps` still holds the records among them.
  defp origin(%Node{kind: :source, children: [child]} = source) do
    if child |> alternatives() |> Enum.all?(&inference?/1) do
      :inference
    else
      {:unknown, source}
    end
  end

  defp origin(%Node{} = source), do: {:unknown, source}

  @spec steps(Node.t() | nil) :: [[Step.t()]]
  defp steps(%Node{kind: :inference_record} = source), do: [Step.from_record(source)]

  defp steps(%Node{kind: :source, children: [child]}) do
    child |> alternatives() |> Enum.filter(&inference?/1) |> Enum.map(&Step.from_record/1)
  end

  defp steps(_source), do: []

  @spec inference?(Node.t()) :: boolean()
  defp inference?(%Node{kind: :inference_record}), do: true
  defp inference?(%Node{}), do: false

  @spec in_parents(Node.t()) :: [Node.t()]
  defp in_parents(%Node{kind: :parents, children: [%Node{children: infos}]}) do
    Enum.flat_map(infos, &in_info/1)
  end

  defp in_parents(%Node{kind: :parents}), do: []

  @spec in_info(Node.t()) :: [Node.t()]
  defp in_info(%Node{kind: :parent_info, children: [source | _details]}), do: parent_nodes(source)
end
