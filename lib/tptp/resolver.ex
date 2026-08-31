defmodule Tptp.Resolver do
  @moduledoc """
  How an `include` name becomes bytes.

  An `include` directive names a file, and following it means reading something the
  caller did not name — possibly from anywhere on the filesystem, possibly over the
  network. That is a decision for the caller, not for a parser, so it is expressed
  as a value they pass in rather than a default they have to notice and turn off.

  ## Choosing one

  | Resolver | Reads |
  |----------|-------|
  | `Tptp.Resolver.Fs` | the including file's directory, then `$TPTP_ROOT`, `$TPTP`, the cwd |
  | `Tptp.Resolver.Http` | tptp.org over HTTPS, through a local cache |
  | `Tptp.Resolver.Cascade` | each of a list in turn |
  | `Tptp.Resolver.Map` | an in-memory map, for tests and Livebook |
  | `Tptp.Resolver.None` | nothing; records the directive and stops |

  A resolver is a module, or a module with options:

      Tptp.Unit.from_file("problem.p", resolver: Tptp.Resolver.Fs)
      Tptp.Unit.from_file("problem.p", resolver: {Tptp.Resolver.Fs, root: "/opt/TPTP"})

  ## Writing one

  `c:resolve/3` gets the name exactly as it appeared in the source with its quotes
  removed and escapes undone, the path of the including file when there is one, and
  whatever options were passed alongside the module. Three answers:

    * `{:ok, path, contents}` — the bytes, and a path to identify them by. The path
      is what memoisation keys on, so two routes to the same file must agree on it;
      an absolute canonical path is the safe choice.
    * `{:error, reason}` — a sentence for the diagnostic, not a term to match on.
    * `:not_followed` — a deliberate decline. No diagnostic is raised, because
      nothing went wrong.

  A resolver must not raise. `Tptp.Include` catches what escapes anyway and turns
  it into a diagnostic, because a badly behaved resolver should not take down a
  parse, but a resolver that relies on that is passing its bugs to its caller.
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
