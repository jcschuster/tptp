defmodule Tptp.Include do
  @moduledoc """
  Follows `include` directives, building the file graph a `Tptp.Unit` is made of.

  ## Memoised by resolved path, not by name

  Two files can reach one axiom set by different names — `Axioms/SET007+0.ax` from
  the library root and `SET007+0.ax` from beside it — and a graph that read it twice
  would double the work and then report every one of its formulae as duplicated.
  The resolver hands back a canonical path precisely so this table can key on it, so
  a diamond is read once.

  Reading once is not the same as *appearing* once. An `include` means textual
  inclusion, so `Tptp.Unit.statements/1` expands each directive where it stands and
  the same file's statements can appear twice under two directives. That is what
  the language says, and a consumer that wants the set rather than the sequence can
  take one.

  ## Cycles

  A file that includes itself, directly or through a chain, is cut at the edge that
  would close the loop: the edge resolves to nothing, `TPTP0602` names every file on
  the cycle, and the walk continues. So the resolved graph is always a DAG and
  expansion always terminates.

  ## Depth

  Bounded by `:max_depth`, 64 by default. Not because deep graphs are wrong but
  because a resolver returning surprising paths can otherwise turn a typo into an
  unbounded walk, and a limit that reports itself is friendlier than one that does
  not exist.

  ## Siblings are parsed in parallel

  The median problem in the TPTP library includes two files and resolves in about
  1.5 ms, which is the case that made a sequential walk look obviously right. The
  worst is `ITP022^4.p`: 144 sibling includes, 59 MB of axioms, and resolving them
  one after another takes 6.7 s of which 56 ms is I/O. Parsing dominates, so
  parsing is what runs in parallel.

  The awkward part of a concurrent graph walk is the memo table, and it is avoided
  rather than coordinated. Each level goes in three passes: resolve every sibling
  (sequential, and it is only I/O), work out which of them are genuinely new and
  pre-assign their file ids in source order, then parse those in parallel. Nothing
  is shared during the parallel pass, and because the ids were assigned before it,
  the result does not depend on the order the tasks finish — the same input builds
  the same graph, every time.

  `:max_concurrency` bounds it; set it to `1` for a strictly sequential walk.
  """

  alias Tptp.Diagnostic
  alias Tptp.Resolver
  alias Tptp.Span
  alias Tptp.Statement.Include

  @unresolved "TPTP0601"
  @cycle "TPTP0602"
  @missing_selection "TPTP0603"
  @too_deep "TPTP0605"

  @max_depth 64

  @typedoc """
  The graph as it is being built.

  `files` is keyed by the id stamped into that file's spans; `paths` maps a
  resolved path back to its id, which is the memo table; `resolutions` records
  where each `include` directive led, keyed by the directive's own position, which
  is unique within its file.
  """
  @type graph :: %{
          files: %{Span.file_id() => Tptp.File.t()},
          paths: %{Path.t() => Span.file_id()},
          resolutions: %{{Span.file_id(), non_neg_integer()} => Span.file_id()},
          diagnostics: [Diagnostic.t()],
          next: Span.file_id()
        }

  @doc """
  Read a root file's includes, transitively.

  The root file is already parsed; this adds everything it reaches. Returns the
  graph and every diagnostic raised along the way, the included files' own included.
  """
  @spec resolve(Tptp.File.t(), Resolver.t(), keyword()) :: graph()
  def resolve(%Tptp.File{} = root, resolver, options \\ []) do
    graph = %{
      files: %{root.id => root},
      paths: if(root.path, do: %{Path.expand(root.path) => root.id}, else: %{}),
      resolutions: %{},
      diagnostics: root.diagnostics,
      next: root.id + 1
    }

    graph
    |> descend(root, resolver, options, 0, [root.path && Path.expand(root.path)])
    |> check_selections()
  end

  @doc """
  Every statement of a file and of everything it includes, in reading order.

  Each `include` is replaced by what it names, right where it stands, which is what
  the language means by inclusion. `selection` filters the whole subtree by formula
  name; `nil` keeps all of it.

  Takes the graph `resolve/3` builds or the `Tptp.Unit` made from it — they carry
  the same two fields, and the walk needs nothing else.
  """
  @spec expand(graph() | Tptp.Unit.t(), Span.file_id(), [binary()] | nil) ::
          [{Span.file_id(), Tptp.Statement.t()}]
  def expand(graph, id, selection \\ nil) do
    graph.files
    |> Map.fetch!(id)
    |> Map.fetch!(:statements)
    |> Enum.flat_map(&contribute(graph, id, &1))
    |> select(selection)
  end

  defp contribute(graph, id, %Include{} = include) do
    case Map.fetch(graph.resolutions, {id, include.off}) do
      {:ok, target} -> expand(graph, target, Include.selected(include))
      :error -> []
    end
  end

  defp contribute(_graph, id, statement), do: [{id, statement}]

  defp select(statements, nil), do: statements

  defp select(statements, names) do
    wanted = MapSet.new(names)

    Enum.filter(statements, fn {_id, statement} ->
      match?(%Tptp.Statement.Annotated{}, statement) and
        MapSet.member?(wanted, statement.name.text)
    end)
  end

  @spec descend(graph(), Tptp.File.t(), Resolver.t(), keyword(), non_neg_integer(), [Path.t()]) ::
          graph()
  defp descend(graph, file, resolver, options, depth, chain) do
    includes = Tptp.File.includes(file)
    max_depth = Keyword.get(options, :max_depth, @max_depth)

    cond do
      includes == [] ->
        graph

      depth >= max_depth ->
        Enum.reduce(includes, graph, fn include, acc ->
          complain(acc, too_deep(file, include, Include.path(include), max_depth))
        end)

      true ->
        outcomes = Enum.map(includes, &{&1, attempt(resolver, Include.path(&1), file.path)})
        {graph, added} = read_all(graph, outcomes, chain, options)

        outcomes
        |> Enum.reduce(graph, &absorb(&2, file, &1, chain))
        |> recurse(added, resolver, options, depth, chain)
    end
  end

  defp attempt(resolver, name, from) do
    Resolver.resolve(resolver, name, from)
  catch
    kind, reason ->
      {:error, "the resolver raised #{Exception.format_banner(kind, reason)}"}
  end

  @spec read_all(graph(), [{Include.t(), Resolver.result()}], [Path.t()], keyword()) ::
          {graph(), [{Path.t(), Span.file_id()}]}
  defp read_all(graph, outcomes, chain, options) do
    assignments =
      outcomes
      |> Enum.flat_map(fn
        {_include, {:ok, path, contents}} -> [{Path.expand(path), contents}]
        {_include, _other} -> []
      end)
      |> Enum.reject(fn {canonical, _contents} ->
        canonical in chain or Map.has_key?(graph.paths, canonical)
      end)
      |> Enum.uniq_by(fn {canonical, _contents} -> canonical end)
      |> Enum.with_index(graph.next)

    parsed =
      assignments
      |> Task.async_stream(
        fn {{canonical, contents}, id} ->
          {:ok, file, _diagnostics} =
            Tptp.from_string(contents, Keyword.merge(options, file: id, path: canonical))

          file
        end,
        max_concurrency: Keyword.get(options, :max_concurrency, System.schedulers_online()),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, file} -> file end)

    graph =
      Enum.reduce(parsed, graph, fn file, acc ->
        %{
          acc
          | files: Map.put(acc.files, file.id, file),
            paths: Map.put(acc.paths, file.path, file.id),
            next: max(acc.next, file.id + 1),
            diagnostics: acc.diagnostics ++ file.diagnostics
        }
      end)

    {graph, Enum.map(parsed, &{&1.path, &1.id})}
  end

  defp absorb(graph, _file, {_include, :not_followed}, _chain), do: graph

  defp absorb(graph, file, {include, {:error, reason}}, _chain) do
    complain(graph, unresolved(file, include, reason))
  end

  defp absorb(graph, file, {include, {:ok, path, _contents}}, chain) do
    canonical = Path.expand(path)

    if canonical in chain do
      complain(graph, cycle(file, include, chain, canonical))
    else
      id = Map.fetch!(graph.paths, canonical)

      link(graph, file, include, id)
    end
  end

  defp recurse(graph, added, resolver, options, depth, chain) do
    Enum.reduce(added, graph, fn {canonical, id}, acc ->
      descend(acc, Map.fetch!(acc.files, id), resolver, options, depth + 1, [canonical | chain])
    end)
  end

  defp link(graph, file, include, target) do
    %{graph | resolutions: Map.put(graph.resolutions, {file.id, include.off}, target)}
  end

  @spec check_selections(graph()) :: graph()
  defp check_selections(graph) do
    for {_id, file} <- graph.files,
        include <- Tptp.File.includes(file),
        names = Include.selected(include),
        names != nil,
        reduce: graph do
      acc -> check_selection(acc, file, include, names)
    end
  end

  defp check_selection(graph, file, include, names) do
    reachable = graph |> names_under(file, include) |> MapSet.new()

    Enum.reduce(names, graph, fn name, acc ->
      if MapSet.member?(reachable, name) do
        acc
      else
        complain(acc, missing_selection(file, include, name))
      end
    end)
  end

  @spec names_under(graph(), Tptp.File.t(), Include.t()) :: [binary()]
  defp names_under(graph, file, include) do
    case Map.fetch(graph.resolutions, {file.id, include.off}) do
      {:ok, target} -> graph |> expand(target) |> Enum.map(fn {_id, s} -> s.name.text end)
      :error -> []
    end
  end

  defp complain(graph, diagnostic) do
    %{graph | diagnostics: graph.diagnostics ++ [diagnostic]}
  end

  defp unresolved(file, include, reason) do
    Diagnostic.new(
      @unresolved,
      :error,
      Tptp.Statement.span(include, file.id),
      "cannot resolve include #{inspect(Include.path(include))}",
      hint: reason
    )
  end

  defp cycle(file, include, chain, canonical) do
    between = chain |> Enum.take_while(&(&1 != canonical)) |> Enum.reverse()
    loop = [canonical | between] ++ [canonical]

    Diagnostic.new(
      @cycle,
      :error,
      Tptp.Statement.span(include, file.id),
      "including #{inspect(Include.path(include))} would close a cycle",
      hint: "the cycle runs #{Enum.join(loop, " -> ")}"
    )
  end

  defp missing_selection(file, include, name) do
    Diagnostic.new(
      @missing_selection,
      :warning,
      Tptp.Statement.span(include, file.id),
      "#{inspect(name)} is selected but nothing under " <>
        "#{inspect(Include.path(include))} defines it",
      hint: "the selection names a formula that is not in the included file or its own includes"
    )
  end

  defp too_deep(file, include, name, max_depth) do
    Diagnostic.new(
      @too_deep,
      :error,
      Tptp.Statement.span(include, file.id),
      "not following #{inspect(name)}: includes are nested more than #{max_depth} deep",
      hint: "raise `:max_depth` if the graph is really this tall"
    )
  end
end
