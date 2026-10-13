defmodule Tptp.Derivation.Step do
  @moduledoc """
  One `<inference_record>`: the rule applied, what it was applied to, and the
  status claimed for it.

  ## Flattening

  A record nests. E writes

      inference(sr, [status(thm)], [inference(rw, [status(thm)], [c_0_19, c_0_51]), c_0_52])

  and the formula the inner `rw` produced is not a statement of the file: it has no
  name, and nothing can refer to it. `from_record/1` therefore returns a list of
  steps, innermost first, in which a parent that is one of those inner records is
  `{:step, index}` into the same list. No name is invented for a formula the file
  does not contain, which is why a step list belongs to one statement rather than
  to the graph `Tptp.Derivation` indexes.

  ## `status`

  `info` is the whole `<useful_info>` list as parsed, and is not interpreted.
  `status` is the one thing read out of it: an `<inference_status_value>` is the
  SZS success ontology's mnemonic in lower case, which `Tptp.Szs.Ontology` already
  models. A word the ontology does not know leaves `status: nil` and raises
  nothing — the word is still in `info`, which is where an annotation this library
  does not model belongs.
  """

  alias Tptp.Node
  alias Tptp.Szs.Ontology

  @enforce_keys [:rule, :status, :info, :parents, :details]
  defstruct [:rule, :status, :info, :parents, :details]

  @typedoc """
  What a step was applied to: a statement's name, or an inner record by its
  position in the same step list.
  """
  @type parent :: binary() | {:step, non_neg_integer()}

  @typedoc "One inference record: its `<inference_rule>`, its `<useful_info>` and its `<parents>`."
  @type t :: %__MODULE__{
          rule: binary(),
          status: Ontology.t() | nil,
          info: Node.t(),
          parents: [parent()],
          details: %{binary() => Node.t()}
        }

  @doc """
  Flatten an `<inference_record>` into its steps, innermost first.

      iex> {:ok, statement, []} =
      ...>   Tptp.Parser.statement_from_string("fof(b, plain, q, inference(sr, [], [inference(rw, [], [a, c]), d])).")
      iex> statement.source |> Tptp.Derivation.Step.from_record() |> Enum.map(&{&1.rule, &1.parents})
      [{"rw", ["a", "c"]}, {"sr", [{:step, 0}, "d"]}]

  `details` holds the `<parent_details>` of a named parent, uninterpreted:

      iex> {:ok, statement, []} =
      ...>   Tptp.Parser.statement_from_string("cnf(b, plain, q, inference(pm, [], [a:[bind(X, $fot(y))]])).")
      iex> [step] = Tptp.Derivation.Step.from_record(statement.source)
      iex> {step.status, Map.keys(step.details)}
      {nil, ["a"]}
  """
  @spec from_record(Node.t()) :: [t()]
  def from_record(%Node{kind: :inference_record, children: [rule, info, parents]}) do
    {steps, parents, details} = Enum.reduce(infos(parents), {[], [], %{}}, &absorb/2)

    steps ++
      [
        %__MODULE__{
          rule: Node.value(rule),
          status: status(info),
          info: info,
          parents: Enum.reverse(parents),
          details: details
        }
      ]
  end

  @doc """
  The names among a step's parents, dropping the references to inner steps.

      iex> {:ok, statement, []} =
      ...>   Tptp.Parser.statement_from_string("fof(b, plain, q, inference(sr, [], [inference(rw, [], [a]), d])).")
      iex> statement.source
      ...> |> Tptp.Derivation.Step.from_record()
      ...> |> List.last()
      ...> |> Tptp.Derivation.Step.named_parents()
      ["d"]
  """
  @spec named_parents(t()) :: [binary()]
  def named_parents(%__MODULE__{parents: parents}) do
    Enum.filter(parents, &is_binary/1)
  end

  # `<parents> ::= [] | [<parent_list>]`, so an empty parents list is a node without
  # children rather than an absent one.
  @spec infos(Node.t()) :: [Node.t()]
  defp infos(%Node{kind: :parents, children: [%Node{children: infos}]}), do: infos
  defp infos(%Node{kind: :parents}), do: []

  @spec absorb(Node.t(), {[t()], [parent()], %{binary() => Node.t()}}) ::
          {[t()], [parent()], %{binary() => Node.t()}}
  defp absorb(%Node{kind: :parent_info, children: [source | rest]}, state) do
    take(source, details(rest), state)
  end

  @spec take(Node.t(), Node.t() | nil, {[t()], [parent()], %{binary() => Node.t()}}) ::
          {[t()], [parent()], %{binary() => Node.t()}}
  defp take(%Node{kind: :name} = source, detail, {steps, parents, details}) do
    name = Node.value(source)

    {steps, [name | parents], if(detail, do: Map.put(details, name, detail), else: details)}
  end

  defp take(%Node{kind: :inference_record} = source, _detail, {steps, parents, details}) do
    inner = from_record(source)

    {steps ++ inner, [{:step, length(steps) + length(inner) - 1} | parents], details}
  end

  # A bracketed source in parent position records alternative derivations of the one
  # parent. Alternatives are not modelled below the top level, so each member is a
  # parent of this step; `Tptp.Derivation.Node` keeps them apart where the whole
  # source is bracketed.
  defp take(%Node{kind: :source, children: [child]}, detail, state) do
    child |> Tptp.Derivation.Node.alternatives() |> Enum.reduce(state, &take(&1, detail, &2))
  end

  # A `<file_source>` or `<internal_source>` in parent position names no statement of
  # this file. It stays reachable through `info` and through `statement.source`.
  defp take(%Node{}, _detail, state), do: state

  @spec details([Node.t()]) :: Node.t() | nil
  defp details([%Node{kind: :parent_details, children: [term]}]), do: term
  defp details(_rest), do: nil

  @spec status(Node.t()) :: Ontology.t() | nil
  defp status(%Node{kind: :general_list, children: [%Node{children: items}]}) do
    case Enum.find(items, &status?/1) do
      nil -> nil
      found -> resolve(found)
    end
  end

  defp status(%Node{}), do: nil

  # Only the direct items of the list are inspected: `status(thm)` nested inside
  # another list is an annotation on that list, not on this record.
  @spec status?(Node.t()) :: boolean()
  defp status?(%Node{
         kind: :general_function,
         children: [head, %Node{kind: :general_terms} = terms]
       }) do
    Node.value(head) == "status" and match?([%Node{children: []}], terms.children)
  end

  defp status?(%Node{}), do: false

  @spec resolve(Node.t()) :: Ontology.t() | nil
  defp resolve(%Node{children: [_head, %Node{children: [leaf]}]}) do
    with text when is_binary(text) <- Node.value(leaf),
         {:ok, value} <- Ontology.from_status_value(text) do
      value
    else
      _otherwise -> nil
    end
  end
end
