defmodule Tptp.Tstp.Solution do
  @moduledoc """
  One TSTP solution file: its header, the derivation it states, and the system
  output it archives.

  `Tptp.Tstp` builds this; see that module for the shape of the file and for what
  is and is not interpreted here.

  ## Two views of the same bytes

  `solution` is a `Tptp.File` over the derivation region alone, so the offsets
  inside it index that region rather than the whole file, and `span.solution` says
  where the region begins. The pair is deliberate: the region is a sub-binary, so
  nothing is copied, and a caller rendering a position in the solution file adds
  the offset while a caller reading the derivation on its own does not have to.

  `span` holds `{offset, length}` pairs rather than `t:Tptp.Span.t/0` because they
  are what `binary_part/3` takes and the file identifier is already on
  `solution.id`.

  ## Header

  `header` maps a key to its value with continuation lines joined by `"\\n"`, and
  `keys` lists the keys in the order the file writes them, which a map does not
  keep. A key written twice keeps its first position in `keys` and its last value
  in `header`.

  `result` and `output` are the first word of the `Result` and `Output` values
  resolved through `Tptp.Szs.Ontology`, and `nil` when the key is absent, empty or
  not a value the ontology knows. The rest of the header stays text: `Computer`,
  `DateTime` and the `Syntax` counts are a system's self-report, not something this
  library can check.
  """

  alias Tptp.Szs.Ontology

  defstruct header: %{},
            keys: [],
            result: nil,
            output: nil,
            solution: nil,
            original: nil,
            span: %{solution: nil, original: nil}

  @typedoc "A byte range of the input the solution was read from, as `binary_part/3` takes it."
  @type region :: {non_neg_integer(), non_neg_integer()}

  @typedoc """
  Where the two regions of the file are, `nil` for one the file does not have.
  """
  @type spans :: %{solution: region() | nil, original: region() | nil}

  @typedoc "A TSTP solution file: what the header says, what was derived, and what the system printed."
  @type t :: %__MODULE__{
          header: %{binary() => binary()},
          keys: [binary()],
          result: Ontology.t() | nil,
          output: Ontology.t() | nil,
          solution: Tptp.File.t() | nil,
          original: binary() | nil,
          span: spans()
        }

  @doc """
  What the file is a solution by: the `File` key, which names the system.

      iex> {:ok, solution, []} = Tptp.Tstp.from_string("%----\\n% File     : E---3.5.1\\n%----\\n")
      iex> Tptp.Tstp.Solution.system(solution)
      "E---3.5.1"
  """
  @spec system(t()) :: binary() | nil
  def system(%__MODULE__{header: header}), do: Map.get(header, "File")

  @doc """
  The problem the solution is for: the `Problem` key, up to its first ` : `.

  The value is written `PUZ001+1 : TPTP v9.3.1. Released v2.0.0.`, which names the
  problem and then the release it was taken from.

      iex> source = "%----\\n% File     : E\\n% Problem  : PUZ001+1 : TPTP v9.3.1\\n%----\\n"
      iex> {:ok, solution, []} = Tptp.Tstp.from_string(source)
      iex> Tptp.Tstp.Solution.problem(solution)
      "PUZ001+1"
  """
  @spec problem(t()) :: binary() | nil
  def problem(%__MODULE__{header: header}) do
    case Map.get(header, "Problem") do
      nil -> nil
      value -> value |> String.split(" : ", parts: 2) |> hd() |> String.trim()
    end
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # `original` is a prover's whole log and `solution` holds its own source, so the
    # derived implementation prints both in full — see `Tptp.File`'s for why that is
    # a hazard rather than a nicety. `inspect(solution, structs: false)` still shows
    # the map.
    @impl true
    def inspect(solution, opts) do
      concat([
        "#Tptp.Tstp.Solution<",
        to_doc(@for.system(solution) || @for.problem(solution), opts),
        ": ",
        result(solution.result),
        dataform(solution.output),
        ", ",
        statements(solution.solution),
        original(solution.original),
        ">"
      ])
    end

    # Both are printed as the atoms they are, so that what the line says is what the
    # field holds; the file's own `Theorem`/`CNFRefutation` spelling is
    # `Tptp.Szs.Ontology.name/1`.
    defp result(nil), do: "no result"
    defp result(value), do: Kernel.inspect(value)

    defp dataform(nil), do: ""
    defp dataform(output), do: "/" <> Kernel.inspect(output)

    defp statements(nil), do: "no solution"
    defp statements(file), do: count(length(file.statements), "statement")

    defp original(nil), do: ""
    defp original(text), do: ", #{bytes(byte_size(text))} of output"

    defp count(1, noun), do: "1 #{noun}"
    defp count(n, noun), do: "#{n} #{noun}s"

    defp bytes(n) when n < 1024, do: "#{n} B"
    defp bytes(n) when n < 1024 * 1024, do: "#{Float.round(n / 1024, 1)} KB"
    defp bytes(n), do: "#{Float.round(n / (1024 * 1024), 1)} MB"
  end
end
