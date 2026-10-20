defmodule Tptp.Header do
  @moduledoc """
  Reads the `% Key : value` header the TPTP writes at the top of its files: of a
  problem, of an axiom set, and of a TSTP solution, which share the shape.

      iex> {:ok, header, []} = Tptp.Header.from_file("test/fixtures/headers/PUZ001+1.p")
      iex> {Tptp.Header.status(header), Tptp.Header.get(header, "Domain")}
      {:theorem, "Puzzles"}

  ## The shape

  The header is the region between the first two rules, lines of dashes, and the
  first rule has to be the first thing in the input:

      %--------------------------------------------------------------------------
      % File     : PUZ001+1 : TPTP v9.3.1. Released v2.0.0.                    key
      % Version  : Especial.
      %            Theorem formulation : Reduced > Complete.                  continuation
      % Refs     : [Pel86] Pelletier (1986), Seventy-five Problems for ...
      %          : [Hah94] Haehnle (1994), Email to G. Sutcliffe              entry
      %--------------------------------------------------------------------------

  A key line is `%`, one space, a key, ` : ` and a value. Only the first colon
  after the key divides the line, so `File` keeps `PUZ001+1 : TPTP v9.3.1` whole.
  A line whose `%` is followed by two or more spaces continues the value: when what
  follows the spaces is a `:`, it starts a further entry of the same key, as `Refs`,
  `Comments` and `Bugfixes` list theirs; otherwise it continues the entry before it,
  as `English` wraps its prose and `Syntax` lists its counts. A bare `%` and an empty
  line separate groups of keys and are skipped.

  Across the 29,334 problem and axiom files of TPTP v9.3.1 under 20 MB, every
  header line is one of these but twelve, in `MGT087+1.p`, `MGT088+1.p`,
  `MGT105+1.p` and `MGT108+1.p`: each writes `Refs`, `Source` and `Names` without
  the colon. Such a line is a `%`, one space and text with no ` : `, and it is
  reported as `TPTP0901` rather than read as a key it does not state or dropped
  without a word.

  ## Values

  `entries/2` gives a key's entries, each with its continuation lines joined by
  `"\\n"`; `get/2` gives them joined the same way. A key written twice keeps its
  first position in `keys` and its last value. Values are text: what they mean is
  for the caller, apart from the two that `status/1` and `spc/1` resolve, since
  both are written in the SZS ontology's vocabulary.

  ## Not a header

  `{:error, :no_header}` is the answer for input that does not open with a rule:
  a bare formula, an empty string, a prover log. Whether the header is a problem's
  or a solution's is not decided here; `Tptp.Tstp` reads a solution's, and requires
  its `File` key.
  """

  alias Tptp.Diagnostic
  alias Tptp.Span
  alias Tptp.Szs.Ontology

  @unreadable "TPTP0001"
  @not_a_header_line "TPTP0901"

  # Horizontal white space is `[ \t]`, never `\s`, which crosses line ends.
  @rule ~r/^%-{4,}[ \t]*\r?$/m
  @key ~r/^%[ \t](\S(?:[^:\r\n]*?\S)?)[ \t]*:[ \t]?([^\r\n]*?)[ \t]*\r?$/
  @entry ~r/^%[ \t]{2,}:[ \t]?([^\r\n]*?)[ \t]*\r?$/
  @continuation ~r/^%[ \t]{2,}([^\r\n]*?)[ \t]*\r?$/
  @keyless ~r/^%[ \t]\S/

  defstruct fields: %{}, keys: [], span: {0, 0}

  @typedoc "A byte range of the input, as `binary_part/3` takes it."
  @type region :: {non_neg_integer(), non_neg_integer()}

  @typedoc """
  A file's header.

  `fields` maps each key to its entries, `keys` lists the keys in the order the
  file writes them, which a map does not keep, and `span` is the region between
  the two rules.
  """
  @type t :: %__MODULE__{
          fields: %{binary() => [binary()]},
          keys: [binary()],
          span: region()
        }

  @typedoc """
  A Specialist Problem Class, as the `SPC` key writes it: `FOF_THM_RFO_SEQ` is
  form `"FOF"`, status `:theorem` and features `["RFO", "SEQ"]`.
  """
  @type spc :: %{form: binary(), status: Ontology.t() | nil, features: [binary()]}

  @doc """
  Reads the header at the top of `input`.

  The only option read is `:file`, the identifier recorded in the span of each
  diagnostic, as `Tptp.from_string/2` takes it; the rest are accepted and ignored,
  so the options of a parse can be passed as they are.

      iex> source = "%----\\n% Status   : Theorem\\n% SPC      : FOF_THM_RFO_SEQ\\n%----\\nfof(a, axiom, p).\\n"
      iex> {:ok, header, []} = Tptp.Header.from_string(source)
      iex> {header.keys, Tptp.Header.status(header)}
      {["Status", "SPC"], :theorem}

      iex> Tptp.Header.from_string("fof(a, axiom, p).\\n")
      {:error, :no_header}
  """
  @spec from_string(binary(), keyword()) :: {:ok, t(), [Diagnostic.t()]} | {:error, :no_header}
  def from_string(input, options \\ []) when is_binary(input) and is_list(options) do
    with [{offset, length}] <- Regex.run(@rule, input, return: :index),
         true <- blank?(binary_part(input, 0, offset)) do
      {header, diagnostics} = read(input, offset + length, Keyword.get(options, :file, 0))
      {:ok, header, diagnostics}
    else
      _otherwise -> {:error, :no_header}
    end
  end

  @doc """
  Reads the header of a file on disk.

  Fails with a diagnostic list when the file cannot be read, as `Tptp.from_file/2`
  does, and with `{:error, :no_header}` when it can be read and has no header.
  Only the header is held on to; to read the formulas as well, parse the file and
  pass its `source` to `from_string/2`.

      iex> {:ok, header, []} = Tptp.Header.from_file("test/fixtures/headers/PUZ001+1.p")
      iex> Tptp.Header.spc(header)
      %{form: "FOF", status: :theorem, features: ["RFO", "SEQ"]}
  """
  @spec from_file(Path.t(), keyword()) ::
          {:ok, t(), [Diagnostic.t()]} | {:error, :no_header} | {:error, [Diagnostic.t()]}
  def from_file(path, options \\ []) when is_list(options) do
    case File.read(path) do
      {:ok, input} ->
        from_string(input, options)

      {:error, reason} ->
        {:error, [unreadable(path, reason, Keyword.get(options, :file, 0))]}
    end
  end

  @doc """
  A key's value, its entries joined by `"\\n"`, or `nil` when the header does not
  have the key.

      iex> {:ok, header, []} = Tptp.Header.from_file("test/fixtures/headers/PUZ001+1.p")
      iex> Tptp.Header.get(header, "Version")
      "Especial.\\nTheorem formulation : Reduced > Complete."
  """
  @spec get(t(), binary()) :: binary() | nil
  def get(%__MODULE__{fields: fields}, key) when is_binary(key) do
    case Map.fetch(fields, key) do
      {:ok, entries} -> Enum.join(entries, "\n")
      :error -> nil
    end
  end

  @doc """
  A key's entries: one for each line that starts it, the `% Key :` line and every
  `%          :` line after, `[]` when the header does not have the key.

      iex> {:ok, header, []} = Tptp.Header.from_file("test/fixtures/headers/PUZ001+1.p")
      iex> Tptp.Header.entries(header, "Refs")
      ["[Pel86] Pelletier (1986), Seventy-five Problems for Testing Au",
       "[Hah94] Haehnle (1994), Email to G. Sutcliffe"]
  """
  @spec entries(t(), binary()) :: [binary()]
  def entries(%__MODULE__{fields: fields}, key) when is_binary(key) do
    Map.get(fields, key, [])
  end

  @doc """
  Every key with its value as `get/2` gives it.

      iex> {:ok, header, []} = Tptp.Header.from_string("%----\\n% File : x\\n% Status : Open\\n%----\\n")
      iex> Tptp.Header.to_map(header)
      %{"File" => "x", "Status" => "Open"}
  """
  @spec to_map(t()) :: %{binary() => binary()}
  def to_map(%__MODULE__{keys: keys} = header) do
    Map.new(keys, &{&1, get(header, &1)})
  end

  @doc """
  The SZS status the file records, resolved through `Tptp.Szs.Ontology`.

  That is the `Status` of a problem or an axiom set, which the TPTP states as known,
  and the `Result` of a solution, which a system claims; a header carries one or the
  other. Each is read from its first word, since a solution writes its times after
  it. `nil` when there is neither, or the word is not a value the ontology knows.

      iex> {:ok, header, []} = Tptp.Header.from_string("%----\\n% File : E\\n% Result : Unsatisfiable 0.1s\\n%----\\n")
      iex> Tptp.Header.status(header)
      :unsatisfiable
  """
  @spec status(t()) :: Ontology.t() | nil
  def status(%__MODULE__{} = header) do
    ontology_value(get(header, "Status") || get(header, "Result"))
  end

  @doc """
  The Specialist Problem Class the `SPC` key names, split into its fields.

  The first field is the form, the second the status as an SZS mnemonic, resolved
  through `Tptp.Szs.Ontology.from_mnemonic/1`, and the rest the features. `nil`
  when there is no `SPC` or it does not have both a form and a status, as the
  `UNK` of `SYN000-3.p` and the empty value of `CSR002+0.ax` do not; `get/2` still
  has the text.

      iex> {:ok, header, []} = Tptp.Header.from_string("%----\\n% SPC : TH0_THM_EQU_NAR\\n%----\\n")
      iex> Tptp.Header.spc(header)
      %{form: "TH0", status: :theorem, features: ["EQU", "NAR"]}
  """
  @spec spc(t()) :: spc() | nil
  def spc(%__MODULE__{} = header) do
    with value when is_binary(value) <- get(header, "SPC"),
         [form, status | features] <- String.split(value, "_") do
      %{form: form, status: mnemonic(status), features: features}
    else
      _otherwise -> nil
    end
  end

  # The header ends at the next rule, or at the end of the input when there is none.
  @spec read(binary(), non_neg_integer(), Span.file_id()) :: {t(), [Diagnostic.t()]}
  defp read(input, from, id) do
    to =
      case Regex.run(@rule, input, return: :index, offset: from) do
        [{next, _length}] -> next
        nil -> byte_size(input)
      end

    {fields, keys, diagnostics, _offset} =
      input
      |> binary_part(from, to - from)
      |> String.split("\n")
      |> Enum.reduce({%{}, [], [], from}, fn line, {fields, keys, diagnostics, offset} ->
        {fields, keys, diagnostics} = line(line, offset, id, {fields, keys, diagnostics})
        {fields, keys, diagnostics, offset + byte_size(line) + 1}
      end)

    header = %__MODULE__{
      fields: Map.new(fields, fn {key, entries} -> {key, Enum.reverse(entries)} end),
      keys: Enum.reverse(keys),
      span: {from, to - from}
    }

    {header, Enum.reverse(diagnostics)}
  end

  # `fields` holds each key's entries newest first while the header is read, and
  # `keys` the keys newest first, so the key being continued is `hd(keys)`.
  @spec line(binary(), non_neg_integer(), Span.file_id(), tuple()) :: tuple()
  defp line(line, offset, id, {fields, keys, diagnostics} = so_far) do
    cond do
      match = Regex.run(@key, line) ->
        [_whole, key, value] = match
        keys = if key in keys, do: keys, else: [key | keys]
        {Map.put(fields, key, [value]), keys, diagnostics}

      match = Regex.run(@entry, line) ->
        [_whole, text] = match
        continue(so_far, fn entries -> [text | entries] end)

      match = Regex.run(@continuation, line) ->
        [_whole, text] = match
        continue(so_far, fn [entry | rest] -> [join(entry, text) | rest] end)

      Regex.match?(@keyless, line) ->
        {fields, keys, [keyless(line, offset, id) | diagnostics]}

      true ->
        so_far
    end
  end

  # A continuation before any key has nothing to continue, and is skipped.
  @spec continue(tuple(), ([binary()] -> [binary()])) :: tuple()
  defp continue({_fields, [], _diagnostics} = so_far, _update), do: so_far

  defp continue({fields, [key | _rest] = keys, diagnostics}, update) do
    {Map.update!(fields, key, update), keys, diagnostics}
  end

  @spec join(binary(), binary()) :: binary()
  defp join("", text), do: text
  defp join(entry, text), do: entry <> "\n" <> text

  @spec ontology_value(binary() | nil) :: Ontology.t() | nil
  defp ontology_value(nil), do: nil

  defp ontology_value(value) do
    with [word | _rest] <- String.split(value),
         {:ok, found} <- Ontology.from_string(word) do
      found
    else
      _otherwise -> nil
    end
  end

  @spec mnemonic(binary()) :: Ontology.t() | nil
  defp mnemonic(text) do
    case Ontology.from_mnemonic(text) do
      {:ok, value} -> value
      _otherwise -> nil
    end
  end

  @spec blank?(binary()) :: boolean()
  defp blank?(text), do: String.trim(text) == ""

  @spec keyless(binary(), non_neg_integer(), Span.file_id()) :: Diagnostic.t()
  defp keyless(line, offset, id) do
    Diagnostic.new(
      @not_a_header_line,
      :warning,
      Span.new(id, offset, byte_size(String.trim_trailing(line))),
      "header line has no ` : ` after its key, so it states no key",
      hint: "a key line is `% Key : value`; a continuation has two or more spaces after the `%`"
    )
  end

  @spec unreadable(Path.t(), File.posix(), Span.file_id()) :: Diagnostic.t()
  defp unreadable(path, reason, id) do
    Diagnostic.new(
      @unreadable,
      :error,
      Span.new(id, 0, 0),
      "cannot read #{path}: #{:file.format_error(reason)}"
    )
  end
end
