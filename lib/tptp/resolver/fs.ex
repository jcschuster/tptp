defmodule Tptp.Resolver.Fs do
  @moduledoc """
  Resolves an `include` against the local filesystem.

  ## Search order

  1. the directory of the including file, when there is one;
  2. `:root`, when given;
  3. `$TPTP`, the variable the TPTP tools use;
  4. `:cwd`, or the current working directory.

  `:root` is the local override, so that a caller directing resolution at a vendored
  copy, a fixture directory or a second library need not set an environment
  variable for the whole VM.

      Tptp.Unit.from_file("PUZ001+1.p", resolver: Tptp.Resolver.Fs)
      Tptp.Unit.from_file("PUZ001+1.p", resolver: {Tptp.Resolver.Fs, root: "/opt/TPTP"})

  `:root` takes a list too, tried in order, for a caller layering a local override
  over a shared library:

      {Tptp.Resolver.Fs, root: ["priv/my_axioms", "/opt/TPTP"]}

  `:root` does not suppress `$TPTP` or the working directory; it is inserted ahead
  of them. To search only the named directories, pass `cwd: false` and leave `$TPTP`
  unset, or use `Tptp.Resolver.Map`.

  ## Confinement

  An include name originates in a file that may not be trusted, so it must be a
  relative path that does not ascend; see `Tptp.Resolver.safe?/1`. The name is
  checked rather than the joined result, which makes the condition independent of
  the candidate directory: no absolute paths and no `..`, in any position.

  ## Canonicalisation

  The returned path is expanded, so two routes to one file — `Axioms/a.ax` from the
  root and `a.ax` from the `Axioms` directory — memoise to the same entry and a
  diamond in the include graph is read once.
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
  The directories this resolver would look in, in order, expanded so that a `~`
  quoted into `$TPTP` reads as the home directory. `$TPTP` set to the empty string
  is skipped rather than read as the working directory.

  Exposed because "it could not find the file" is a much less useful thing to be
  told than "it looked here, here and here".
  """
  @spec roots(Path.t() | nil, keyword()) :: [Path.t()]
  def roots(from, options \\ []) do
    [
      from && Path.dirname(from),
      Keyword.get(options, :root),
      System.get_env("TPTP"),
      # Undocumented and to be removed: the variable this library used to document.
      System.get_env("TPTP_ROOT"),
      cwd(options)
    ]
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
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
