defmodule Tptp.Resolver.Map do
  @moduledoc """
  Resolves from an in-memory map of name to contents.

  For tests, for Livebook, and for any caller that has the bytes and requires the
  include graph assembled without filesystem access.

      Tptp.Unit.from_string(source,
        resolver: {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a, axiom, p)."}}
      )

  Names are matched exactly as written in the `include` directive, so a map keyed
  `"Axioms/a.ax"` does not resolve `include('a.ax')`. Path equivalence is
  `Tptp.Resolver.Fs`'s concern; a test resolver inferring it would admit tests that
  pass for the wrong reason.
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
