defmodule Tptp.VendoredTest do
  @moduledoc """
  The vendored TPTP World files, against what `NOTICE` says about them.

  `NOTICE` is the package's attribution, and the TPTP's terms permit redistribution
  only of *verbatim* copies — so "unmodified" is a claim with legal weight, not a
  nicety. These tests read each digest out of `NOTICE` itself rather than repeating
  it, so a file cannot drift from the bytes its attribution describes: editing a
  vendored file without updating its attribution fails here, and so does the reverse.

  Each file is pinned in `NOTICE` to a raw URL at the commit it was taken from. The
  `:network` tests are the other half, excluded by default because a test suite
  should not need GitHub to pass: they fetch each file from the tip of its
  repository and report when upstream has moved on. Run them when bumping either
  file:

      mix test --include network
  """

  use ExUnit.Case, async: true

  alias Tptp.Resolver.Http

  @notice Path.join(__DIR__, "../../NOTICE") |> Path.expand()

  @external_resource @notice

  @vendored %{
    "priv/bnf/SyntaxBNF-v9.3.1.3" =>
      "https://raw.githubusercontent.com/TPTPWorld/SyntaxBNF/master/SyntaxBNF-v9.3.1.3",
    "priv/bnf/SZSOntology.bnf" =>
      "https://raw.githubusercontent.com/TPTPWorld/SZSOntologies/master/BNF/SZSOntology.bnf"
  }

  defp digests do
    @notice
    |> File.read!()
    |> then(&Regex.scan(~r/^\s+(\S+)\n\s+sha256 ([0-9a-f]{64})$/m, &1))
    |> Map.new(fn [_whole, url, digest] -> {url, digest} end)
  end

  defp path(file), do: Path.join(__DIR__, "../../#{file}") |> Path.expand()

  defp digest(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  test "NOTICE names both vendored files, pinned to a commit" do
    recorded = digests()

    assert map_size(recorded) == 2

    for {file, _tip} <- @vendored do
      assert Enum.any?(Map.keys(recorded), &String.ends_with?(&1, Path.basename(file))),
             "NOTICE carries no digest for #{file}"
    end

    for url <- Map.keys(recorded) do
      assert url =~ ~r"^https://raw\.githubusercontent\.com/TPTPWorld/\w+/[0-9a-f]{40}/"
    end
  end

  test "each vendored file is the file NOTICE attributes" do
    for {file, _tip} <- @vendored do
      {_url, recorded} =
        Enum.find(digests(), fn {url, _} -> String.ends_with?(url, Path.basename(file)) end)

      assert digest(path(file)) == recorded, "#{file} does not match its digest in NOTICE"
    end
  end

  for {file, tip} <- @vendored do
    @tag :network
    test "#{file} still matches the tip of its repository" do
      assert {:ok, upstream} = fetch(unquote(tip))
      assert File.read!(path(unquote(file))) == upstream
    end
  end

  defp fetch(url) do
    with :ok <- Http.started(),
         request = {String.to_charlist(url), [{~c"user-agent", ~c"tptp-elixir"}]},
         {:ok, {{_version, 200, _phrase}, _headers, body}} <-
           :httpc.request(:get, request, [timeout: 60_000, autoredirect: true],
             body_format: :binary
           ) do
      {:ok, body}
    else
      other -> {:error, other}
    end
  end
end
