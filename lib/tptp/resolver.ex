defmodule Tptp.Resolver do
  @moduledoc """
  The behaviour by which an `include` name is resolved to bytes.

  An `include` directive names a file, and resolving it reads something the caller
  did not name, potentially from anywhere on the filesystem or over the network.
  That decision belongs to the caller, so it is expressed as a value passed in
  rather than as a default.

  ## Available implementations

  | Resolver | Reads |
  |----------|-------|
  | `Tptp.Resolver.Fs` | the including file's directory, then `$TPTP_ROOT`, `$TPTP`, the working directory |
  | `Tptp.Resolver.Http` | tptp.org over HTTPS, through a local cache |
  | `Tptp.Resolver.Cascade` | each of a list in turn |
  | `Tptp.Resolver.Map` | an in-memory map, for tests and Livebook |
  | `Tptp.Resolver.None` | nothing; records the directive |

  A resolver is a module, optionally paired with options:

      Tptp.Unit.from_file("problem.p", resolver: Tptp.Resolver.Fs)
      Tptp.Unit.from_file("problem.p", resolver: {Tptp.Resolver.Fs, root: "/opt/TPTP"})

  ## Implementing one

  `c:resolve/3` receives the name as it appeared in the source with quotes removed
  and escapes undone, the path of the including file where one exists, and the
  options supplied alongside the module. It returns one of:

    * `{:ok, path, contents}` — the bytes and a path identifying them. Memoisation
      is keyed on this path, so two routes to one file must agree on it; an
      absolute canonical path satisfies this.
    * `{:error, reason}` — a description for the diagnostic, not a term to match
      on.
    * `:not_followed` — a deliberate decline, producing no diagnostic.

  A resolver must not raise. `Tptp.Include` converts an escaping exception into a
  diagnostic so that a defective resolver cannot terminate a parse, but an
  implementation should not depend on this.
  """

  @typedoc "A resolver module, optionally paired with its options."
  @type t :: module() | {module(), keyword()}

  @typedoc "What a resolver hands back."
  @type result :: {:ok, Path.t(), binary()} | {:error, binary()} | :not_followed

  @doc """
  Turn an include name into bytes, or decline.

  `name` arrives unquoted and unescaped, `from` is the path of the including file
  when there is one, and `options` are whatever was passed alongside the module.
  See the module documentation for what each of the three answers means, and for
  why a resolver must not raise.
  """
  @callback resolve(name :: binary(), from :: Path.t() | nil, options :: keyword()) :: result()

  @doc """
  Ask a resolver for a name, whatever shape the resolver was given in.

      iex> resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a,axiom,p)."}}
      iex> Tptp.Resolver.resolve(resolver, "a.ax", nil)
      {:ok, "a.ax", "fof(a,axiom,p)."}
  """
  @spec resolve(t(), binary(), Path.t() | nil) :: result()
  def resolve(resolver, name, from) when is_binary(name) do
    {module, options} = split(resolver)
    module.resolve(name, from, options)
  end

  @doc """
  Whether a name is safe to resolve at all.

  An include name comes out of a file the caller may not trust, and a resolver that
  joins it onto a directory without looking will happily read `../../../etc/passwd`.
  Every shipped resolver checks this first: a name must be relative and must not
  climb.

      iex> Tptp.Resolver.safe?("Axioms/SET007+0.ax")
      true
      iex> Tptp.Resolver.safe?("../../etc/passwd")
      false
      iex> Tptp.Resolver.safe?("/etc/passwd")
      false
  """
  @spec safe?(binary()) :: boolean()
  def safe?(name) when is_binary(name) do
    name != "" and Path.type(name) == :relative and ".." not in Path.split(name)
  end

  @doc """
  The reason to report for a name that is not safe to resolve.
  """
  @spec unsafe_reason(binary()) :: binary()
  def unsafe_reason(name) do
    "#{inspect(name)} is not a relative path below the including file; " <>
      "an include may not name an absolute path or climb out with `..`"
  end

  @spec split(t()) :: {module(), keyword()}
  defp split({module, options}) when is_atom(module) and is_list(options), do: {module, options}
  defp split(module) when is_atom(module), do: {module, []}
end
