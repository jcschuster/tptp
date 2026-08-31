defmodule Tptp.Resolver.Cascade do
  @moduledoc """
  Tries each of a list of resolvers, in order, and takes the first that answers.

      {Tptp.Resolver.Cascade, resolvers: [Tptp.Resolver.Fs, Tptp.Resolver.Http]}

  That composition is the intended one: read from disk when the TPTP distribution
  is installed, fall back to tptp.org when it is not. It is still not a default —
  it reaches the network, so the caller writes it down.

  ## What it reports when everything fails

  Every resolver's reason, joined, rather than only the last one. "not found in
  /opt/TPTP" and "returned 404" are different failures with different fixes, and a
  cascade that reported one of them would hide the other.

  ## `:not_followed` stops the cascade

  A resolver that declines has decided, so the cascade decides too. Putting
  `Tptp.Resolver.None` in the middle of a list is a way to say "these, and if none
  of them, give up quietly" — though the clearer way to say that is to not use a
  cascade.
  """

  @behaviour Tptp.Resolver

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: Tptp.Resolver.result()
  def resolve(name, from, options) do
    options
    |> Keyword.get(:resolvers, [])
    |> try_each(name, from, [])
  end

  defp try_each([], name, _from, []) do
    {:error, "no resolver was configured to look for #{inspect(name)}"}
  end

  defp try_each([], _name, _from, reasons) do
    {:error, reasons |> Enum.reverse() |> Enum.join("; ")}
  end

  defp try_each([resolver | rest], name, from, reasons) do
    case Tptp.Resolver.resolve(resolver, name, from) do
      {:ok, path, contents} -> {:ok, path, contents}
      :not_followed -> :not_followed
      {:error, reason} -> try_each(rest, name, from, [reason | reasons])
    end
  end
end
