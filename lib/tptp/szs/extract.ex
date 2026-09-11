defmodule Tptp.Szs.Extract do
  @moduledoc """
  Reads the vendored SZS ontology page into a list of status values.

  `mix tptp.gen` invokes this and writes `Tptp.Szs.Ontology`; nothing calls it at
  runtime. It resides here rather than under `lib/mix/tasks/` so that it can be
  tested directly and its reading of the page documented alongside it.

  ## Source format

  No machine-readable SZS ontology is published. The BNF is distributed as a file
  and vendored as one; the ontology exists only as <https://szs.tptp.org>, and the
  values are recovered from its markup.

  That page is a Google Sites document, so the markup is generated and its class
  names are opaque. What it does have is a consistent shape for a value, and one
  the page's own rendering depends on: a list item whose paragraph opens with the
  `OneWord` name in a monospace face, followed by the mnemonic in parentheses, a
  colon, a line break, and the description.

      <li ...><p ...><span style="... font-family: 'Courier New' ...">Satisfiable</span>
      <span ...> (SAT):</span><span ...><br></span><span ...>Some interpretations
      are models of Ax, and some models of Ax are models of C.</span></p>

  The monospace face is what distinguishes a value from ordinary prose, exactly as
  `<TT>` did on the page's previous incarnation at `tptp.org/UserDocs/SZSOntology`.
  Three list items in the `Success` section describe the subontologies rather than
  naming a value, and those are the three that do not open with one.

  Subontology comes from the nesting of the lists, and the section a value belongs
  to from the `<H3>` it falls under.

  ## Completeness

  A pattern that ceases to match one entry is the failure mode of concern, since
  the result is a table correct in what it contains and short by one entry. This
  occurred on the previous page: `Assumed` is written with a mnemonic taking
  arguments, `ASS(U,S)`, and a pattern requiring three letters between the
  parentheses did not match it. A lower bound on the total does not detect this.

  So the count is checked against the page rather than against a constant. Every
  monospace-opening list item in a section must come back as a value, and a name
  that does not raises with its own spelling in the message. The mnemonic pattern
  is whatever stands between the parentheses, of which the leading three letters
  are the code — `ASS` for `ASS(U,S)` — so the arguments no longer cost the value
  its place in the table. What they are is in the value's own description, which is
  the page's sentence about them.

  ## Recovered fields

  Recovered: every value's `OneWord` name, its three-letter mnemonic, its
  description, which of the three ontologies it belongs to, and — from the nesting
  of the lists — which subontology of `Success` it sits in.

  Not recovered: the `isa` hierarchy. It is drawn in the three ontology figures and
  appears nowhere in the text. Transcribing a dense diagram by eye into a library
  whose whole contract is faithfulness would be putting unverifiable claims where
  verified ones belong, so `Tptp.Szs.Ontology` offers the partition it can prove
  and no `parent/1`. See its documentation for what that costs and what would fix
  it.
  """

  @typedoc """
  One status value, exactly as the page states it.

  `ontology` is the section it was found in. `subontology` is the outermost list
  item it was nested under: in the `Success` section that is one of
  `SemanticSuccess`, `TypeCheckSuccess` or `VerifySuccess`, and in the other two
  sections, which are flat, it is the section's own root.
  """
  @type value :: %{
          name: binary(),
          mnemonic: binary(),
          description: binary(),
          ontology: :success | :no_success | :data,
          subontology: binary()
        }

  # The page heads its NoSuccess section "The NoSuccesss Ontology"; the `s+` admits
  # both spellings so that a correction upstream does not lose the section.
  @sections [
    {~r{\AThe\s+Success\s+Ontology\z}i, :success, "Success"},
    {~r{\AThe\s+NoSuccess+\s+Ontology\z}i, :no_success, "NoSuccess"},
    {~r{\AThe\s+Data\s+Ontology\z}i, :data, "Data"}
  ]

  @heading ~r{<h3\b[^>]*>.*?</h3>}is

  @entry ~r{<li\b[^>]*>\s*<p\b[^>]*>(.*?)</p>}is

  @stated ~r{\A([A-Za-z0-9]+)\s*\((.*?)\)\s*:\s*(.*)\z}s

  @candidate ~r{<li\b[^>]*>\s*<p\b[^>]*>\s*<span\b[^>]*Courier[^>]*>([A-Za-z0-9]+)</span>}is

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

      iex> monospace = ~s(<span style="font-family: 'Courier New', Arial;">)
      iex> markup = "<h3>The Success Ontology</h3><h3>The NoSuccess Ontology</h3>" <>
      ...>   "<h3>The Data Ontology</h3><ul><li><p>" <> monospace <> "Proof</span>" <>
      ...>   "<span> (Prf):</span><span><br></span><span>A proof.</span></p></li></ul>"
      iex> Tptp.Szs.Extract.parse!(markup)
      [%{name: "Proof", mnemonic: "Prf", description: "A proof.", ontology: :data, subontology: "Data"}]
  """
  @spec parse!(binary()) :: [value()]
  def parse!(markup) when is_binary(markup) do
    sections = sections(markup)

    Enum.flat_map(@sections, fn {heading, ontology, root} ->
      sections |> section!(heading, ontology) |> entries(ontology, root)
    end)
  end

  @spec sections(binary()) :: [{binary(), binary()}]
  defp sections(markup) do
    headings = for [span] <- Regex.scan(@heading, markup, return: :index), do: span

    headings
    |> Enum.zip(Enum.drop(headings, 1) ++ [{byte_size(markup), 0}])
    |> Enum.map(fn {{start, length}, {next, _next_length}} ->
      opens = start + length

      {markup |> slice({start, length}) |> text(), slice(markup, {opens, next - opens})}
    end)
  end

  @spec section!([{binary(), binary()}], Regex.t(), atom()) :: binary()
  defp section!(sections, heading, ontology) do
    case Enum.find(sections, fn {title, _body} -> Regex.match?(heading, title) end) do
      {_title, body} -> body
      nil -> raise "the SZS ontology page has no #{ontology} section"
    end
  end

  @spec entries(binary(), atom(), binary()) :: [value()]
  defp entries(section, ontology, root) do
    values =
      @entry
      |> Regex.scan(section, return: :index)
      |> Enum.flat_map(&List.wrap(entry(section, &1, ontology, root)))
      |> Enum.map_reduce(root, fn {value, nested?}, carried ->
        value = %{value | subontology: subontology(value, nested?, ontology, root, carried)}

        {value, value.subontology}
      end)
      |> elem(0)

    complete!(section, values, ontology)
  end

  @spec complete!(binary(), [value()], atom()) :: [value()]
  defp complete!(section, values, ontology) do
    listed = for [_whole, name] <- Regex.scan(@candidate, section), do: name
    recovered = Enum.map(values, & &1.name)

    case listed -- recovered do
      [] ->
        values

      missing ->
        raise "the SZS #{ontology} section lists #{Enum.join(missing, ", ")}, " <>
                "which #{__MODULE__} did not recover; the page has changed shape"
    end
  end

  @spec entry(binary(), [{integer(), integer()}], atom(), binary()) :: {value(), boolean()} | nil
  defp entry(section, [whole, paragraph], ontology, root) do
    case Regex.run(@stated, section |> slice(paragraph) |> text()) do
      [_all, name, mnemonic, description] ->
        value = %{
          name: name,
          mnemonic: mnemonic!(mnemonic, name),
          description: String.trim(description),
          ontology: ontology,
          subontology: root
        }

        {value, nested?(section, whole)}

      nil ->
        nil
    end
  end

  @spec mnemonic!(binary(), binary()) :: binary()
  defp mnemonic!(fragment, name) do
    case String.split(fragment, "(", parts: 2) do
      [<<code::binary-size(3)>> | _arguments] -> code
      _otherwise -> raise "#{name} has no three-letter SZS mnemonic: #{inspect(fragment)}"
    end
  end

  @spec subontology(value(), boolean(), atom(), binary(), binary()) :: binary()
  defp subontology(_value, _nested?, ontology, root, _carried) when ontology != :success,
    do: root

  defp subontology(value, nested?, _ontology, _root, carried) do
    if nested?, do: carried, else: value.name
  end

  @spec nested?(binary(), {integer(), integer()}) :: boolean()
  defp nested?(section, {start, _length}) do
    opened = section |> binary_part(0, start) |> count(~r{<ul\b}i)
    closed = section |> binary_part(0, start) |> count(~r{</ul>}i)

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
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end
end
