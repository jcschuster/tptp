defmodule Tptp.Unit do
  @moduledoc """
  A root file and everything its `include` directives reach.

  `Tptp.from_file/2` reads one file. This reads a *problem*: the root plus the
  axiom sets it pulls in, with every span still naming the file it came from, so a
  diagnostic about a symbol declared in an axiom file and used in the problem can
  point at both.

      {:ok, unit, diagnostics} =
        Tptp.Unit.from_file("Problems/PUZ/PUZ001+1.p", resolver: Tptp.Resolver.Fs)

      Tptp.Unit.statements(unit)   # [{file_id, statement}], includes expanded in place
      unit.files[unit.root]        # the root %Tptp.File{}

  ## Following includes is opt-in

  The default resolver is `Tptp.Resolver.None`, which records each directive and
  reads nothing. Following an include means reading a file the caller did not name,
  and with `Tptp.Resolver.Http` it means reaching the network, so it is a resolver
  the caller passes rather than a default they have to notice and switch off.

  ## Two views, because both are wanted

  `files` is the set of files, read once each even when a diamond reaches one of
  them twice. `statements/1` is the sequence, with each `include` expanded where it
  stands — which is what the language means and what a prover would see. A file
  read once can therefore appear twice in the sequence.

  ## Selections

  `include('big.ax', [key_lemma])` keeps only the named formulae, and the filter is
  applied to the whole subtree under that directive rather than to `big.ax` alone.
  The TPTP standard does not say what a selection means when the selected file has
  includes of its own; this reading is the one that makes `include(f, [x])` mean
  "give me x", which is what it is for. A name that is nowhere under the directive
  is a `TPTP0603` warning.
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
    * `:max_depth` — how deep the include graph may nest before the walk stops and
      says so. Defaults to 64.
  """
  @type option :: Tptp.option() | {:resolver, Resolver.t()} | {:max_depth, pos_integer()}

  @doc """
  Read a file and everything it includes.

      iex> resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a, axiom, p)."}}
      iex> {:ok, unit, []} = Tptp.Unit.from_string("include('a.ax'). fof(b, conjecture, p).", resolver: resolver)
      iex> unit |> Tptp.Unit.statements() |> Enum.map(fn {_id, statement} -> statement.name.text end)
      ["a", "b"]
  """
  @spec from_string(binary(), [option()]) :: {:ok, t(), [Diagnostic.t()]}
  def from_string(source, options \\ []) when is_binary(source) do
    {:ok, root, _diagnostics} = Tptp.from_string(source, options)
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
    case Tptp.from_file(path, options) do
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
end
