defmodule Tptp.Resolver.Fs do
  @moduledoc """
  Resolves an `include` against the local filesystem.

  ## Search order

  1. the directory of the including file, when there is one;
  2. `:root`, or `$TPTP_ROOT` if the option is absent;
  3. `$TPTP`, the older variable the TPTP tools have always used;
  4. `:cwd`, or the current working directory.

  `$TPTP_ROOT` is the documented environment knob, and `:root` is the local
  override for it — a caller pointing at a vendored copy, a fixture directory or a
  second library should not have to set an environment variable to do it, and
  certainly should not have to mutate one for the whole VM.

      Tptp.Unit.from_file("PUZ001+1.p", resolver: Tptp.Resolver.Fs)
      Tptp.Unit.from_file("PUZ001+1.p", resolver: {Tptp.Resolver.Fs, root: "/opt/TPTP"})

  `:root` takes a list too, tried in order, for a caller layering a local override
  over a shared library:

      {Tptp.Resolver.Fs, root: ["priv/my_axioms", "/opt/TPTP"]}

  Passing `:root` suppresses neither `$TPTP` nor the cwd; it inserts ahead of them.
  To search nothing but what you named, pass `cwd: false` and leave the environment
  variables unset — or use `Tptp.Resolver.Map`, which is usually what a test wants.

  `$TPTP` is honoured after `:root` because a machine with the TPTP distribution
  installed usually already has it set, and failing to find `Axioms/SET007+0.ax` on
  such a machine would be a silly way to lose.

  ## Confinement

  An include name comes from a file that may not be trusted, so it must be a
  relative path that does not climb — see `Tptp.Resolver.safe?/1`. Checking the
  name rather than the joined result is what makes the rule easy to state and hard
  to get around: no absolute paths, no `..`, ever, regardless of which candidate
  directory it would have landed in.

  ## Paths are canonicalised

  The path handed back is expanded, so two routes to one file — `Axioms/a.ax` from
  the root and `a.ax` from the `Axioms` directory — memoise to the same entry and
  a diamond in the include graph is read once.
  """

  @behaviour Tptp.Resolver

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: Tptp.Resolver.result()
  def resolve(name, from, options) do
    if Tptp.Resolver.safe?(name) do
      name |> candidates(from, options) |> first_readable(name)
    else
      {:error, Tptp.Resolver.unsafe_reason(name)}
    end
  end

  @doc """
  The directories this resolver would look in, in order.

  Exposed because "it could not find the file" is a much less useful thing to be
  told than "it looked here, here and here".
  """
  @spec roots(Path.t() | nil, keyword()) :: [Path.t()]
  def roots(from, options \\ []) do
    [
      from && Path.dirname(from),
      overrides(options),
      System.get_env("TPTP"),
      cwd(options)
    ]
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == false))
    |> Enum.uniq()
  end

  defp overrides(options) do
    case Keyword.get(options, :root) do
      nil -> System.get_env("TPTP_ROOT")
      roots when is_list(roots) -> roots
      root when is_binary(root) -> [root]
    end
  end

  defp cwd(options) do
    case Keyword.get(options, :cwd, :default) do
      :default -> File.cwd!()
      other -> other
    end
  end

  defp candidates(name, from, options) do
    from
    |> roots(options)
    |> Enum.map(&Path.expand(Path.join(&1, name)))
    |> Enum.uniq()
  end

  defp first_readable(candidates, name), do: first_readable(candidates, name, candidates)

  defp first_readable([], name, tried) do
    {:error, "#{inspect(name)} was not found; looked in #{Enum.join(tried, ", ")}"}
  end

  defp first_readable([path | rest], name, tried) do
    case File.read(path) do
      {:ok, contents} -> {:ok, path, contents}
      {:error, _reason} -> first_readable(rest, name, tried)
    end
  end
end
