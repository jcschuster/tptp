defmodule Tptp.Unit do
  @moduledoc """
  A root file together with everything its `include` directives reach.

  `Tptp.from_file/2` reads a single file. This reads a problem: the root and the
  axiom sets it includes, with every span identifying the file it originates in, so
  that a diagnostic concerning a symbol declared in an axiom file and used in the
  problem can refer to both.

      {:ok, unit, diagnostics} =
        Tptp.Unit.from_file("Problems/PUZ/PUZ001+1.p", resolver: Tptp.Resolver.Fs)

      Tptp.Unit.statements(unit)   # [{file_id, statement}], includes expanded in place
      unit.files[unit.root]        # the root %Tptp.File{}

  ## Resolution is explicit

  The default resolver is `Tptp.Resolver.None`, which records each directive and
  reads nothing. Resolution reads files the caller did not name and, under
  `Tptp.Resolver.Http`, performs network access, so the resolver is supplied by the
  caller rather than defaulted.

  ## Two representations

  `files` is the set of files, each read once even where a diamond in the graph
  reaches it twice. `statements/1` is the sequence, with each `include` expanded in
  position, which is what textual inclusion denotes and what a prover observes. A
  file read once may therefore occur twice in the sequence.

  ## Formula selection

  `include('big.ax', [key_lemma])` retains only the named formulae, and the filter
  applies to the whole subtree beneath that directive rather than to `big.ax`
  alone. The TPTP standard does not define the meaning of a selection when the
  selected file has includes of its own; this reading makes `include(f, [x])`
  denote the formula `x` wherever it occurs beneath the directive. A name occurring
  nowhere beneath it produces a `TPTP0603` warning.
  """

  alias Tptp.Diagnostic
  alias Tptp.Include
  alias Tptp.Resolver
  alias Tptp.Span
  alias Tptp.Statement
  alias Tptp.Statement.Annotated

  @enforce_keys [:root, :files]
  defstruct [:root, :files, resolutions: %{}, diagnostics: []]

  @typedoc "A root file and everything reachable from it through `include`, with the resolutions that got there."
  @type t :: %__MODULE__{
          root: Span.file_id(),
          files: %{Span.file_id() => Tptp.File.t()},
          resolutions: %{{Span.file_id(), non_neg_integer()} => Span.file_id()},
          diagnostics: [Diagnostic.t()]
        }

  @typedoc """
  Options accepted by the entry points.

  Everything `t:Tptp.option/0` accepts, plus:

    * `:resolver` — how an `include` name becomes bytes. Defaults to
      `Tptp.Resolver.None`, which follows nothing.
    * `:max_concurrency` — how many sibling includes are parsed at once. Defaults to
      `System.schedulers_online()`; set it to `1` for a strictly sequential walk, which
      is what a caller running under its own `max_heap_size` needs, since that ceiling
      is not inherited by the processes `Tptp.Include` spawns.
    * `:max_depth` — how deep the include graph may nest before the walk stops and
      says so. Defaults to 64.
  """
  @type option ::
          Tptp.option()
          | {:resolver, Resolver.t()}
          | {:max_depth, pos_integer()}
          | {:max_concurrency, pos_integer()}

  @doc """
  Read a file and everything it includes.

      iex> resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a, axiom, p)."}}
      iex> {:ok, unit, []} = Tptp.Unit.from_string("include('a.ax'). fof(b, conjecture, p).", resolver: resolver)
      iex> unit |> Tptp.Unit.statements() |> Enum.map(fn {_id, statement} -> statement.name.text end)
      ["a", "b"]
  """
  @spec from_string(binary(), [option()]) :: {:ok, t(), [Diagnostic.t()]}
  def from_string(source, options \\ []) when is_binary(source) do
    {:ok, root, _diagnostics} = Tptp.from_string(source, reading(options))
    resolved(root, options)
  end

  @doc """
  Read a file from disk and everything it includes.

  Fails only when the root file cannot be read; an include that cannot be resolved
  is a diagnostic on an otherwise usable unit.
  """
  @spec from_file(Path.t(), [option()]) ::
          {:ok, t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def from_file(path, options \\ []) do
    case Tptp.from_file(path, reading(options)) do
      {:ok, root, _diagnostics} -> resolved(root, options)
      {:error, diagnostics} -> {:error, diagnostics}
    end
  end

  @doc """
  Read a file the resolver knows by name, and everything it includes.

  The entry point for a caller who has a TPTP name rather than a path — from a
  problem list, a benchmark set, or a user typing `PUZ001+1.p`. The root goes
  through the same resolver as its includes, so pointing `$TPTP_ROOT` at a local
  library or passing `Tptp.Resolver.Http` changes where everything comes from at
  once.

      Tptp.Unit.from_name("Problems/PUZ/PUZ001+1.p", resolver: Tptp.Resolver.Fs)
  """
  @spec from_name(binary(), [option()]) ::
          {:ok, t(), [Diagnostic.t()]} | {:error, [Diagnostic.t()]}
  def from_name(name, options \\ []) when is_binary(name) do
    resolver = Keyword.get(options, :resolver, Tptp.Resolver.None)

    case Resolver.resolve(resolver, name, nil) do
      {:ok, path, contents} ->
        {:ok, root, _diagnostics} =
          Tptp.from_string(contents, Keyword.put(options, :path, path))

        resolved(root, options)

      :not_followed ->
        {:error, [declined(name, resolver)]}

      {:error, reason} ->
        {:error, [unresolvable(name, reason)]}
    end
  end

  @doc """
  Read a file and everything it includes, raising `Tptp.Error` on any error.
  """
  @spec from_file!(Path.t(), [option()]) :: t()
  def from_file!(path, options \\ []) do
    case from_file(path, options) do
      {:ok, unit, diagnostics} ->
        if Diagnostic.any_errors?(diagnostics) do
          raise Tptp.Error,
            diagnostics: diagnostics,
            path: path,
            source: unit.files[unit.root].source
        end

        unit

      {:error, diagnostics} ->
        raise Tptp.Error, diagnostics: diagnostics, path: path
    end
  end

  @doc """
  Every statement, with `include` directives expanded where they stand.

  Each element is `{file_id, statement}`, because the statement itself carries only
  offsets — the file it belongs to is what turns those into a position. The
  directives themselves are not in the result; they have been replaced by what they
  name. An unresolved directive contributes nothing, and said so at read time.
  """
  @spec statements(t()) :: [{Span.file_id(), Statement.t()}]
  def statements(%__MODULE__{} = unit), do: Include.expand(unit, unit.root)

  @doc """
  Every annotated formula, `include` directives expanded and filtered by selection.
  """
  @spec formulae(t()) :: [{Span.file_id(), Annotated.t()}]
  def formulae(%__MODULE__{} = unit) do
    Enum.filter(statements(unit), fn {_id, statement} -> match?(%Annotated{}, statement) end)
  end

  @doc """
  The file a span or id belongs to.
  """
  @spec file(t(), Span.file_id() | Span.t()) :: Tptp.File.t() | nil
  def file(%__MODULE__{} = unit, %Span{file: id}), do: Map.get(unit.files, id)
  def file(%__MODULE__{} = unit, id) when is_integer(id), do: Map.get(unit.files, id)

  @doc """
  The bytes a span names, wherever in the unit it points.
  """
  @spec text(t(), Span.t()) :: binary() | nil
  def text(%__MODULE__{} = unit, %Span{} = span) do
    case file(unit, span) do
      nil -> nil
      found -> Span.text(span, found.source)
    end
  end

  @doc """
  Whether anything error-severity was found, in any file.
  """
  @spec any_errors?(t()) :: boolean()
  def any_errors?(%__MODULE__{} = unit), do: Diagnostic.any_errors?(unit.diagnostics)

  @doc """
  Every diagnostic, rendered one per line against the file it belongs to.
  """
  @spec format_diagnostics(t()) :: [binary()]
  def format_diagnostics(%__MODULE__{} = unit) do
    indexes = Map.new(unit.files, fn {id, found} -> {id, Tptp.File.line_index(found)} end)

    Enum.map(unit.diagnostics, fn diagnostic ->
      id = diagnostic.span.file
      Diagnostic.format(diagnostic, Map.fetch!(indexes, id), unit.files[id].path)
    end)
  end

  @spec resolved(Tptp.File.t(), [option()]) :: {:ok, t(), [Diagnostic.t()]}
  # A unit's options are a superset of a file's, and the extra ones are not a file's
  # business. Forwarding the lot happened to work — `Tptp.from_string/2` reads the keys
  # it knows and ignores the rest — but it made the call a type error that nothing in
  # `lib/` was making, so nothing caught it. Handing on only what the callee documents
  # is both the honest call and the one Dialyzer can check.
  @spec reading([option()]) :: [Tptp.option()]
  defp reading(options), do: Keyword.take(options, [:file, :path, :max_statements])

  defp resolved(root, options) do
    resolver = Keyword.get(options, :resolver, Tptp.Resolver.None)
    graph = Include.resolve(root, resolver, options)

    unit = %__MODULE__{
      root: root.id,
      files: graph.files,
      resolutions: graph.resolutions,
      diagnostics: Diagnostic.sort(graph.diagnostics)
    }

    {:ok, unit, unit.diagnostics}
  end

  defp unresolvable(name, reason) do
    Diagnostic.new(
      "TPTP0601",
      :error,
      Span.new(0, 0, 0),
      "cannot resolve #{inspect(name)}",
      hint: reason
    )
  end

  defp declined(name, resolver) do
    Diagnostic.new(
      "TPTP0606",
      :error,
      Span.new(0, 0, 0),
      "#{inspect(name)} was not fetched",
      hint:
        "#{inspect(resolver)} declines to read anything; pass a resolver that can, " <>
          "such as Tptp.Resolver.Fs"
    )
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    # A unit holds every file in the include closure, and `CSR031+6.p` reaches 455 MB
    # of them. See the note on `Tptp.File`'s implementation.
    @impl true
    def inspect(unit, opts) do
      root = Map.get(unit.files, unit.root)

      concat([
        "#Tptp.Unit<",
        to_doc((root && root.path) || unit.root, opts),
        ", ",
        count(map_size(unit.files), "file"),
        diagnostics(unit.diagnostics),
        ">"
      ])
    end

    defp count(1, noun), do: "1 #{noun}"
    defp count(n, noun), do: "#{n} #{noun}s"

    defp diagnostics([]), do: ""
    defp diagnostics(list), do: ", " <> count(length(list), "diagnostic")
  end
end
