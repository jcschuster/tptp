defmodule Tptp.Szs do
  @moduledoc """
  Reads and writes the SZS result lines that ATP systems emit around their output.

      iex> Tptp.Szs.status("% SZS status Theorem for PUZ001+1\\n")
      {:ok, :theorem, "PUZ001+1", nil}

  ## The convention

  A system reports its result on a single comment line:

      % SZS status <value> for <problem>
      % SZS status <value> for <problem> : <free text>

  and delimits any output offered in support of that result:

      % SZS output start <dataform> for <problem>
      ...
      % SZS output end <dataform> for <problem>

  Two properties make this worth a module rather than a regular expression at each
  call site. The status value is drawn from a closed vocabulary,
  `Tptp.Szs.Ontology`, so a misspelling can be reported rather than propagated. And
  the lines are interleaved with the remainder of a prover's output, including its
  banner, its own comments and possibly several candidate answers, so locating the
  status requires scanning rather than matching.

  ## What the reader accepts

  The writers, `status_line/3` and `output_block/3`, emit the form above, leaving
  out `for <problem>` when the problem is `nil`. The readers accept four departures
  from it that occur in practice:

    * `#` in place of `%` as the comment character. E writes
      `# SZS status Theorem`.
    * No `for <problem>`, as in the same line from E. The problem is then `nil`.
    * Anything before the comment character on the same line. StarExec prefixes
      each line of a job's output with a pair of elapsed times, as in
      `0.00/0.03\\t# SZS status Theorem`.
    * No comment character at all, as Paradox prints it:
      `SZS status Satisfiable for /tmp/SOT_KBdUKq.tptp:short`. Only horizontal
      white space may precede `SZS` in that form, so a mention of the convention
      within a sentence is not taken for a line.

  The value and dataform are not relaxed: each is looked up in
  `Tptp.Szs.Ontology` as written. Anything after the problem other than a
  `: <free text>` suffix means the line is not a status line. The SystemOnTPTP
  summary line, `... <system> says <value> ...`, is not an SZS status line and is
  not read here.

      iex> Tptp.Szs.status("# SZS status Theorem\\n")
      {:ok, :theorem, nil, nil}

      iex> Tptp.Szs.status("0.00/0.03\\t# SZS status CounterSatisfiable\\n")
      {:ok, :counter_satisfiable, nil, nil}

      iex> Tptp.Szs.status("SZS status Satisfiable for /tmp/SOT_KBdUKq.tptp:short\\n")
      {:ok, :satisfiable, "/tmp/SOT_KBdUKq.tptp:short", nil}

      iex> Tptp.Szs.status("The line SZS status Theorem is not a status line\\n")
      :none

      iex> Tptp.Szs.status("% RESULT: SOT_x - Vampire---5.0 says Theorem - CPU = 0.01\\n")
      :none

  ## Selection

  `status/1` returns the last status line in the output. A system refining its
  answer emits the refinement afterwards, and a system abandoning the attempt emits
  `GaveUp` last; in both cases the final line is the result the system asserts.
  `statuses/1` returns all of them in order.

  ## Atom creation

  Every status and dataform name resolves through the tables in
  `Tptp.Szs.Ontology`, whose atoms exist at compile time. Prover output is
  untrusted input, and an unrecognised value is returned as `{:error, word}` with
  the word as a binary rather than converted to an atom.
  """

  alias Tptp.Szs.Ontology

  @typedoc """
  A parsed SZS status line: the value, the problem it is about (`nil` when the line
  names none), and any trailing free text after the `:`.
  """
  @type status :: {:ok, Ontology.t(), binary() | nil, binary() | nil}

  @typedoc "A status line whose value is not in the ontology, kept verbatim."
  @type unknown :: {:error, binary(), binary() | nil, binary() | nil}

  @typedoc """
  A delimited output block: its dataform, the problem (`nil` when the markers name
  none), and the lines between the `start` and `end` markers with the markers
  removed. The body is verbatim, including any per-line prefix such as StarExec's.
  """
  @type block :: %{dataform: Ontology.t(), problem: binary() | nil, body: binary()}

  # Horizontal white space is spelled `[ \t]` rather than `\s` or `\h`: `\s` crosses
  # line ends, and `\h` matches the byte 0xA0, which occurs inside UTF-8 sequences.
  #
  # The leading alternation is the framing: anything at all before a comment
  # character, or horizontal white space and nothing else. The second alternative is
  # what admits Paradox's uncommented lines while keeping `SZS status` mid-sentence
  # out, since a word before it is neither.
  @status ~r{^(?:[^\r\n]*?[%#][ \t]*|[ \t]*)SZS[ \t]+status[ \t]+(\S+)(?:[ \t]+for[ \t]+(\S+))?[ \t]*(?::[ \t]*([^\r\n]*?))?[ \t]*\r?$}im
  @start ~r{^(?:[^\r\n]*?[%#][ \t]*|[ \t]*)SZS[ \t]+output[ \t]+start[ \t]+(\S+)(?:[ \t]+for[ \t]+(\S+))?[ \t]*(?::[^\r\n]*)?\r?$}im
  @stop ~r{^(?:[^\r\n]*?[%#][ \t]*|[ \t]*)SZS[ \t]+output[ \t]+end[ \t]+(\S+)(?:[ \t]+for[ \t]+(\S+))?[ \t]*(?::[^\r\n]*)?\r?$}im

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
  Write a status line. A `nil` problem leaves out `for <problem>`.

      iex> Tptp.Szs.status_line(:theorem, "PUZ001+1")
      "% SZS status Theorem for PUZ001+1"
      iex> Tptp.Szs.status_line(:gave_up, "PUZ001+1", "no strategy left")
      "% SZS status GaveUp for PUZ001+1 : no strategy left"
      iex> Tptp.Szs.status_line(:timeout, nil, "wall-clock limit")
      "% SZS status Timeout : wall-clock limit"
  """
  @spec status_line(Ontology.t(), binary() | nil, binary() | nil) :: binary()
  def status_line(value, problem, comment \\ nil) when is_binary(problem) or is_nil(problem) do
    line = "% SZS status #{Ontology.name(value)}#{for_problem(problem)}"

    if comment, do: "#{line} : #{comment}", else: line
  end

  @doc """
  Wrap a body in `output start` / `output end` markers. A `nil` problem leaves out
  `for <problem>` on both.

      iex> Tptp.Szs.output_block(:proof, "X", "fof(a,axiom,p).")
      "% SZS output start Proof for X\\nfof(a,axiom,p).\\n% SZS output end Proof for X"
      iex> Tptp.Szs.output_block(:proof, nil, "fof(a,axiom,p).")
      "% SZS output start Proof\\nfof(a,axiom,p).\\n% SZS output end Proof"
  """
  @spec output_block(Ontology.t(), binary() | nil, binary()) :: binary()
  def output_block(dataform, problem, body)
      when (is_binary(problem) or is_nil(problem)) and is_binary(body) do
    name = Ontology.name(dataform) <> for_problem(problem)

    "% SZS output start #{name}\n#{body}\n% SZS output end #{name}"
  end

  @spec for_problem(binary() | nil) :: binary()
  defp for_problem(nil), do: ""
  defp for_problem(problem), do: " for #{problem}"

  # `Regex.scan/2` omits trailing groups that did not participate and returns ""
  # for earlier ones. Neither the problem nor the dataform can match empty, so ""
  # means absent.
  @spec parse_status([binary()]) :: status() | unknown()
  defp parse_status([whole, word]), do: parse_status([whole, word, "", ""])
  defp parse_status([whole, word, problem]), do: parse_status([whole, word, problem, ""])

  defp parse_status([_whole, word, problem, comment]) do
    problem = present(problem)
    text = present(comment)

    case Ontology.from_string(word) do
      {:ok, value} -> {:ok, value, problem, text}
      :error -> {:error, word, problem, text}
    end
  end

  @spec present(binary()) :: binary() | nil
  defp present(""), do: nil
  defp present(text), do: text

  @spec block(binary(), [{integer(), integer()}], [[{integer(), integer()}]]) :: block() | nil
  defp block(output, [whole, dataform], stops),
    do: block(output, [whole, dataform, {-1, 0}], stops)

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

  @spec closing(binary(), [[{integer(), integer()}]], binary(), binary() | nil, integer()) ::
          {integer(), integer()} | nil
  defp closing(output, stops, name, problem, after_marker) do
    Enum.find_value(stops, fn [whole, dataform | target] ->
      matches? =
        elem(whole, 0) > after_marker and slice(output, dataform) == name and
          slice(output, List.first(target, {-1, 0})) == problem

      if matches?, do: whole
    end)
  end

  @spec body(binary(), integer(), integer()) :: binary()
  defp body(output, from, to) do
    output |> binary_part(from, to - from) |> String.trim()
  end

  # `{-1, 0}` is how `Regex.scan/3` reports a group that did not participate.
  @spec slice(binary(), {integer(), integer()}) :: binary() | nil
  defp slice(_source, {-1, 0}), do: nil
  defp slice(source, {start, length}), do: binary_part(source, start, length)
end
