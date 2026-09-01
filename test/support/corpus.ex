defmodule Tptp.Test.Corpus do
  @moduledoc """
  Locates a local TPTP library for the tests tagged `:corpus`.

  Those tests are excluded by default so that a contributor without the library
  can still run `mix test`. Point `$TPTP_ROOT` at a checkout to enable them, or
  rely on the conventional `/opt/TPTP`.

  ## Two sweeps, and which one is running

  A corpus test declares how far it thins the library for a pull request, where
  the whole point is to finish. `$TPTP_CORPUS_FULL=1` overrides every one of those
  to sweep the library entire, and that is what the nightly workflow sets: a check
  that skips four files in five is a check that never looks at four fifths of the
  library, and the only way that stops being a problem is to run the whole thing
  somewhere.

  `:max_bytes` is not thinning and is not overridden. It excludes the seventy files
  a complete TPTP holds above 20 MB — five axiom sets and sixty-five `HWV` problems,
  3.4 GB between them — which the streaming gate reads on purpose and in full.

  File selection itself is `Mix.Tasks.Tptp.Corpus`, so the committed report and
  these tests are describing the same set of files rather than two that drifted.

  ## The files this parser refuses

  `Mix.Tasks.Tptp.Corpus.known_failures/0` lists the library files that do not
  parse, each chased down to a gap between the vendored BNF release and the library
  that ships beside it. `files/1` leaves them out, because a sweep asserting "every
  file parses" cannot also carry an exception in its result, and
  `Tptp.CorpusTest` asserts separately that each of them still fails. An exception
  that stopped being needed would fail that test rather than sit here.
  """

  @doc """
  The library root, or `nil` when there is none to test against.
  """
  @spec root() :: Path.t() | nil
  defdelegate root(), to: Mix.Tasks.Tptp.Corpus

  @doc """
  Problem and axiom files, thinned for a pull request unless the full sweep is on.

  `:every` takes one file in n and is ignored when `$TPTP_CORPUS_FULL=1`.
  `:max_bytes` skips the enormous axiom files and always applies.
  """
  @spec files(keyword()) :: [Path.t()]
  def files(options \\ []) do
    options
    |> Keyword.put(:every, every(options))
    |> Mix.Tasks.Tptp.Corpus.files()
    |> Enum.reject(&Map.has_key?(known_failures(), Path.basename(&1)))
  end

  @doc """
  The library files this parser refuses, and why, keyed by base name.
  """
  @spec known_failures() :: %{binary() => binary()}
  defdelegate known_failures(), to: Mix.Tasks.Tptp.Corpus

  @doc """
  Whether the nightly full sweep is on.
  """
  @spec full?() :: boolean()
  def full?, do: System.get_env("TPTP_CORPUS_FULL") in ["1", "true"]

  defp every(options), do: if(full?(), do: 1, else: Keyword.get(options, :every, 1))
end
