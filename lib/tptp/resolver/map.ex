defmodule Tptp.Resolver.Map do
  @moduledoc """
  Resolves from an in-memory map of name to contents.

  For tests, for Livebook, and for any caller that already has the bytes and wants
  the include graph assembled without touching a filesystem.

      Tptp.Unit.from_string(source,
        resolver: {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a, axiom, p)."}}
      )

  Names are matched exactly as written in the `include` directive, so a map keyed
  `"Axioms/a.ax"` does not answer `include('a.ax')`. That is deliberate: guessing
  at path equivalence is `Tptp.Resolver.Fs`'s job, and a test resolver that guesses
  is a test that passes for the wrong reason.
  """

  @behaviour Tptp.Resolver

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: Tptp.Resolver.result()
  def resolve(name, _from, options) do
    files = Keyword.get(options, :files, %{})

    case Map.fetch(files, name) do
      {:ok, contents} when is_binary(contents) ->
        {:ok, name, contents}

      :error ->
        {:error, "#{inspect(name)} is not in the resolver's map"}
    end
  end
end
