defmodule Tptp.Szs.Extract do
  @moduledoc """
  Reads the vendored SZS ontology page into a list of status values.

  `mix tptp.gen` runs this and writes `Tptp.Szs.Ontology`; nothing at runtime calls
  it. It is here rather than in `lib/mix/tasks/` so it can be tested directly and so
  its reading of the page is documented where the reading happens.

  ## Why a web page and not a data file

  There is no machine-readable SZS ontology to fetch. The BNF ships as a file and is
  vendored as one; the ontology exists as
  <https://tptp.org/UserDocs/SZSOntology>, and everything below is recovered from
  its markup. That markup is regular enough to parse strictly rather than
  heuristically: every value is one `<LI> <TT>Name</TT> (<TT>Mnc</TT>):<BR>` line
  followed by its description, and nothing else in the three ontology sections has
  that shape. A page that stops matching produces no values rather than wrong ones,
  and the generator refuses to write a suspiciously short table.

  ## What is recovered, and what is not

  Recovered: every value's `OneWord` name, its three-letter mnemonic, its
  description, which of the three ontologies it belongs to, and — from the nesting
  of the lists — which subontology of `Success` it sits in.

  Not recovered: the `isa` hierarchy. It is drawn in `Success.png`, `NoSuccess.png`
  and `Data.png` and appears nowhere in the text. Transcribing a dense diagram by
  eye into a library whose whole contract is faithfulness would be putting
  unverifiable claims where verified ones belong, so `Tptp.Szs.Ontology` offers the
  partition it can prove and no `parent/1`. See its documentation for what that
  costs and what would fix it.
  """

  @typedoc """
  One status value, exactly as the page states it.

  `ontology` is the section it was found in. `subontology` is the top-level `<LI>`
  it was nested under: in the `Success` section that is one of `SemanticSuccess`,
  `TypeCheckSuccess` or `VerifySuccess`, and in the other two sections, which are
  flat, it is the section's own root.
  """
  @type value :: %{
          name: binary(),
          mnemonic: binary(),
          description: binary(),
          ontology: :success | :no_success | :data,
          subontology: binary()
        }

  @sections [
    {~r{<H3>\s*The\s*<TT>Success</TT>\s*Ontology\s*</H3>}i, :success, "Success"},
    {~r{<H3>\s*The\s*<TT>NoSuccess+</TT>\s*Ontology\s*</H3>}i, :no_success, "NoSuccess"},
    {~r{<H3>\s*The\s*<TT>Data</TT>\s*Ontology\s*</H3>}i, :data, "Data"}
  ]

  @entry ~r"<LI>\s*<TT>([A-Za-z0-9]+)</TT>\s*\(<TT>([A-Za-z0-9]{3})</TT>\)\s*:\s*<BR>(.*?)(?=<LI>|</UL>|<H3>|\z)"is

  @doc """
  Read every status value out of the page at `path`.

  Raises if a section is missing, which means the page has been restructured and the
  generated module would be silently short.
  """
  @spec values!(Path.t()) :: [value()]
  def values!(path) do
    path |> File.read!() |> parse!()
  end

  @doc """
  Read every status value out of already-loaded page markup.

  All three ontology sections must be present; a page missing one has been
  restructured, and a short table is worse than a loud failure.

      iex> markup = "<H3> The <TT>Success</TT> Ontology </H3>" <>
      ...>   "<H3> The <TT>NoSuccess</TT> Ontology </H3>" <>
      ...>   "<H3> The <TT>Data</TT> Ontology </H3>" <>
      ...>   "<UL><LI> <TT>Proof</TT> (<TT>Prf</TT>):<BR>A proof.</UL>"
      iex> Tptp.Szs.Extract.parse!(markup)
      [%{name: "Proof", mnemonic: "Prf", description: "A proof.", ontology: :data, subontology: "Data"}]
  """
  @spec parse!(binary()) :: [value()]
  def parse!(markup) when is_binary(markup) do
    Enum.flat_map(@sections, fn {heading, ontology, root} ->
      markup |> section!(heading, ontology) |> entries(ontology, root)
    end)
  end

  @spec section!(binary(), Regex.t(), atom()) :: binary()
  defp section!(markup, heading, ontology) do
    case Regex.split(heading, markup, parts: 2) do
      [_before, rest] -> ~r{<H3>}i |> Regex.split(rest, parts: 2) |> List.first()
      _otherwise -> raise "the SZS ontology page has no #{ontology} section"
    end
  end

  @spec entries(binary(), atom(), binary()) :: [value()]
  defp entries(section, ontology, root) do
    @entry
    |> Regex.scan(section, return: :index)
    |> Enum.map_reduce(root, fn captures, carried ->
      value = entry(section, captures, ontology, root, carried)

      {value, value.subontology}
    end)
    |> elem(0)
  end

  @spec entry(binary(), [{integer(), integer()}], atom(), binary(), binary()) :: value()
  defp entry(section, [whole, name, mnemonic, description], ontology, root, carried) do
    name = slice(section, name)

    %{
      name: name,
      mnemonic: slice(section, mnemonic),
      description: section |> slice(description) |> text(),
      ontology: ontology,
      subontology: subontology(section, whole, ontology, root, carried, name)
    }
  end

  @spec subontology(binary(), {integer(), integer()}, atom(), binary(), binary(), binary()) ::
          binary()
  defp subontology(_section, _whole, ontology, root, _carried, _name) when ontology != :success,
    do: root

  defp subontology(section, whole, _ontology, _root, carried, name) do
    if nested?(section, whole), do: carried, else: name
  end

  @spec nested?(binary(), {integer(), integer()}) :: boolean()
  defp nested?(section, {start, _length}) do
    opened = section |> binary_part(0, start) |> count(~r{<UL>}i)
    closed = section |> binary_part(0, start) |> count(~r{</UL>}i)

    opened - closed > 1
  end

  @spec count(binary(), Regex.t()) :: non_neg_integer()
  defp count(markup, pattern), do: pattern |> Regex.scan(markup) |> length()

  @spec slice(binary(), {integer(), integer()}) :: binary()
  defp slice(source, {start, length}), do: binary_part(source, start, length)

  @spec text(binary()) :: binary()
  defp text(fragment) do
    fragment
    |> String.replace(~r{<[^>]*>}, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end
end
