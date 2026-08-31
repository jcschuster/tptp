defmodule Tptp.Szs do
  @moduledoc """
  Reads and writes the SZS result lines that ATP systems print around their output.

      iex> Tptp.Szs.status("% SZS status Theorem for PUZ001+1\\n")
      {:ok, :theorem, "PUZ001+1", nil}

  ## What the standard says, and why a parser is worth having

  A system reports its result on one comment line:

      % SZS status <value> for <problem>
      % SZS status <value> for <problem> : <free text>

  and delimits any output it offers to justify that result:

      % SZS output start <dataform> for <problem>
      ... the derivation, model or whatever it is ...
      % SZS output end <dataform> for <problem>

  Two things make this worth a module rather than a regular expression at each call
  site. The status value is a closed vocabulary — `Tptp.Szs.Ontology` — so a
  misspelling can be reported rather than propagated as a plausible-looking atom.
  And the lines arrive interleaved with everything else a prover writes to standard
  output, including its own banner, its own comments, and sometimes several
  candidate answers, so finding *the* status means scanning rather than matching.

  ## Where the status is taken from

  `status/1` returns the **last** status line in the output. A system that refines
  its answer prints the refinement afterwards, and a system that gives up after
  trying prints `GaveUp` last; in both cases the final word is the one it stands
  behind. `statuses/1` returns all of them in order for a caller that wants to see
  the sequence.

  ## No atom is created from prover output

  Every status and dataform name resolves through the generated tables in
  `Tptp.Szs.Ontology`, whose atoms all exist at compile time. Prover output is
  untrusted input like any other file this library reads, and an unrecognised value
  comes back as `{:error, word}` with the word as a binary — never as a new atom.
  """

  alias Tptp.Szs.Ontology

  @typedoc """
  A parsed SZS status line: the value, the problem it is about, and any trailing
  free text after the `:`.
  """
  @type status :: {:ok, Ontology.t(), binary(), binary() | nil}

  @typedoc "A status line whose value is not in the ontology, kept verbatim."
  @type unknown :: {:error, binary(), binary(), binary() | nil}

  @typedoc """
  A delimited output block: its dataform, the problem, and the lines between the
  `start` and `end` markers with the markers removed.
  """
  @type block :: %{dataform: Ontology.t(), problem: binary(), body: binary()}

  @status ~r{^\s*%\s*SZS\s+status\s+(\S+)\s+for\s+(\S+)\s*(?::\s*(.*?))?\s*$}im
  @start ~r{^\s*%\s*SZS\s+output\s+start\s+(\S+)\s+for\s+(\S+)\s*(?::.*)?$}im
  @stop ~r{^\s*%\s*SZS\s+output\s+end\s+(\S+)\s+for\s+(\S+)\s*(?::.*)?$}im

  @doc """
  The vendored SZS ontology page.

  Raises unless exactly one is present, the way `Tptp.Bnf.vendored_path!/0` does,
  because two would mean a regeneration read a file nobody chose.
  """
  @spec vendored_path!() :: Path.t()
  def vendored_path! do
    pattern = Path.join([Application.app_dir(:tptp, "priv"), "szs", "SZSOntology-*"])

    case Path.wildcard(pattern) do
      [path] ->
        path

      [] ->
        raise ArgumentError, "no SZS ontology found at #{pattern}"

      many ->
        raise ArgumentError,
              "expected exactly one vendored SZS ontology, found #{length(many)}: " <>
                Enum.map_join(many, ", ", &Path.basename/1)
    end
  end

  @doc """
  The status a system reported, taken from the last status line it printed.

      iex> Tptp.Szs.status("% SZS status Theorem for X\\n% SZS status GaveUp for X : ran out\\n")
      {:ok, :gave_up, "X", "ran out"}

      iex> Tptp.Szs.status("nothing to see here")
      :none

      iex> Tptp.Szs.status("% SZS status Nonsense for X")
      {:error, "Nonsense", "X", nil}
  """
  @spec status(binary()) :: status() | unknown() | :none
  def status(output) when is_binary(output) do
    case statuses(output) do
      [] -> :none
      found -> List.last(found)
    end
  end

  @doc """
  Every status line in the output, in the order they appear.

      iex> Tptp.Szs.statuses("% SZS status Theorem for A\\n% SZS status Timeout for B\\n")
      [{:ok, :theorem, "A", nil}, {:ok, :timeout, "B", nil}]
  """
  @spec statuses(binary()) :: [status() | unknown()]
  def statuses(output) when is_binary(output) do
    @status
    |> Regex.scan(output)
    |> Enum.map(&parse_status/1)
  end

  @doc """
  The last status, reduced to a plain value.

      iex> Tptp.Szs.value("% SZS status CounterSatisfiable for X")
      {:ok, :counter_satisfiable}
      iex> Tptp.Szs.value("% SZS status Nonsense for X")
      {:error, "Nonsense"}
      iex> Tptp.Szs.value("")
      :none
  """
  @spec value(binary()) :: {:ok, Ontology.t()} | {:error, binary()} | :none
  def value(output) when is_binary(output) do
    case status(output) do
      {:ok, value, _problem, _comment} -> {:ok, value}
      {:error, word, _problem, _comment} -> {:error, word}
      :none -> :none
    end
  end

  @doc """
  Whether the output reports a success-ontology value.

      iex> Tptp.Szs.success?("% SZS status Unsatisfiable for X")
      true
      iex> Tptp.Szs.success?("% SZS status Timeout for X")
      false
      iex> Tptp.Szs.success?("")
      false
  """
  @spec success?(binary()) :: boolean()
  def success?(output) when is_binary(output) do
    case value(output) do
      {:ok, value} -> Ontology.success?(value)
      _otherwise -> false
    end
  end

  @doc """
  Every delimited output block, in order.

  A `start` with no matching `end` is dropped rather than guessed at: a truncated
  block is exactly the case where guessing hands a consumer half a derivation and
  calls it whole.

      iex> output = "% SZS output start Proof for X\\nfof(a,axiom,p).\\n% SZS output end Proof for X\\n"
      iex> Tptp.Szs.blocks(output)
      [%{dataform: :proof, problem: "X", body: "fof(a,axiom,p)."}]
  """
  @spec blocks(binary()) :: [block()]
  def blocks(output) when is_binary(output) do
    starts = Regex.scan(@start, output, return: :index)
    stops = Regex.scan(@stop, output, return: :index)

    starts
    |> Enum.map(&block(output, &1, stops))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Write a status line.

      iex> Tptp.Szs.status_line(:theorem, "PUZ001+1")
      "% SZS status Theorem for PUZ001+1"
      iex> Tptp.Szs.status_line(:gave_up, "PUZ001+1", "no strategy left")
      "% SZS status GaveUp for PUZ001+1 : no strategy left"
  """
  @spec status_line(Ontology.t(), binary(), binary() | nil) :: binary()
  def status_line(value, problem, comment \\ nil) when is_binary(problem) do
    line = "% SZS status #{Ontology.name(value)} for #{problem}"

    if comment, do: "#{line} : #{comment}", else: line
  end

  @doc """
  Wrap a body in `output start` / `output end` markers.

      iex> Tptp.Szs.output_block(:proof, "X", "fof(a,axiom,p).")
      "% SZS output start Proof for X\\nfof(a,axiom,p).\\n% SZS output end Proof for X"
  """
  @spec output_block(Ontology.t(), binary(), binary()) :: binary()
  def output_block(dataform, problem, body) when is_binary(problem) and is_binary(body) do
    name = Ontology.name(dataform)

    "% SZS output start #{name} for #{problem}\n#{body}\n% SZS output end #{name} for #{problem}"
  end

  @spec parse_status([binary()]) :: status() | unknown()
  defp parse_status([_whole, word, problem]), do: parse_status([nil, word, problem, ""])

  defp parse_status([_whole, word, problem, comment]) do
    text = if comment == "", do: nil, else: comment

    case Ontology.from_string(word) do
      {:ok, value} -> {:ok, value, problem, text}
      :error -> {:error, word, problem, text}
    end
  end

  @spec block(binary(), [{integer(), integer()}], [[{integer(), integer()}]]) :: block() | nil
  defp block(output, [{start, length}, dataform, problem], stops) do
    name = slice(output, dataform)
    problem = slice(output, problem)
    after_marker = start + length

    with {:ok, value} <- Ontology.from_string(name),
         {stop, _length} <- closing(output, stops, name, problem, after_marker) do
      %{dataform: value, problem: problem, body: body(output, after_marker, stop)}
    else
      _otherwise -> nil
    end
  end

  @spec closing(binary(), [[{integer(), integer()}]], binary(), binary(), integer()) ::
          {integer(), integer()} | nil
  defp closing(output, stops, name, problem, after_marker) do
    Enum.find_value(stops, fn [whole, dataform, target] ->
      matches? =
        elem(whole, 0) > after_marker and slice(output, dataform) == name and
          slice(output, target) == problem

      if matches?, do: whole
    end)
  end

  @spec body(binary(), integer(), integer()) :: binary()
  defp body(output, from, to) do
    output |> binary_part(from, to - from) |> String.trim()
  end

  @spec slice(binary(), {integer(), integer()}) :: binary()
  defp slice(source, {start, length}), do: binary_part(source, start, length)
end
