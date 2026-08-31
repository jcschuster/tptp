defmodule Tptp.Test.Corpus do
  @moduledoc """
  Locates a local TPTP library for the tests tagged `:corpus`.

  Those tests are excluded by default so that a contributor without the library
  can still run `mix test`. Point `$TPTP_ROOT` at a checkout to enable them, or
  rely on the conventional `/opt/TPTP`.
  """

  @conventional "/opt/TPTP"

  @doc """
  The library root, or `nil` when there is none to test against.
  """
  @spec root() :: Path.t() | nil
  def root do
    candidate = System.get_env("TPTP_ROOT") || System.get_env("TPTP") || @conventional
    if File.dir?(candidate), do: candidate
  end

  @doc """
  Problem and axiom files, optionally thinned and size-capped.

  `:every` takes one file in n, which keeps a full-coverage sweep affordable in
  CI. `:max_bytes` skips the handful of enormous axiom files, which belong in the
  streaming benchmark rather than in a correctness sweep.
  """
  @spec files(keyword()) :: [Path.t()]
  def files(options \\ []) do
    case root() do
      nil ->
        []

      root ->
        every = Keyword.get(options, :every, 1)
        max_bytes = Keyword.get(options, :max_bytes, 20_000_000)

        (Path.wildcard(Path.join([root, "Problems", "*", "*.p"])) ++
           Path.wildcard(Path.join([root, "Axioms", "*.ax"])) ++
           Path.wildcard(Path.join([root, "Axioms", "*", "*.ax"])))
        |> Enum.sort()
        |> Enum.take_every(every)
        |> Enum.filter(&(File.stat!(&1).size <= max_bytes))
    end
  end
end
