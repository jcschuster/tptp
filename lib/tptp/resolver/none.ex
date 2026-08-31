defmodule Tptp.Resolver.None do
  @moduledoc """
  Records an `include` and does not follow it.

  The right resolver when the include graph is somebody else's problem: a prover
  handed the file will resolve its own includes, and reading them here would be
  work done twice and a chance to disagree about what `Axioms/SET007+0.ax` means.

  Declining is not a failure, so no diagnostic is raised. `Tptp.Unit` still records
  the directive, so `Tptp.File.includes/1` reports what was skipped.
  """

  @behaviour Tptp.Resolver

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: :not_followed
  def resolve(_name, _from, _options), do: :not_followed
end
