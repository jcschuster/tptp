defmodule Tptp.VendoredTest do
  @moduledoc """
  The vendored TPTP World file, against what `NOTICE` says about it.

  `NOTICE` is the package's attribution, and the TPTP's terms permit redistribution
  only of *verbatim* copies — so "unmodified" is a claim with legal weight, not a
  nicety. These tests read the digest out of `NOTICE` itself rather than repeating
  it, so the file cannot drift from the bytes it describes: editing the vendored
  file without updating its attribution fails here, and so does the reverse.

  The `:network` test is the other half, excluded by default because a test suite
  should not need tptp.org to pass. Run it when bumping a TPTP release:

      mix test --include network

  The BNF is reconstructed the way a browser copy does — `<BR>` to newline, tags
  stripped, entities and `&nbsp;` undone — because that is exactly how the vendored
  copy was made, and compared. Trailing white space is ignored on both sides: the
  page ends with a long run of `&nbsp;<P>` padding so that its anchors have
  somewhere to scroll to, and 43 spaces of scroll room are not part of the grammar.

  The SZS ontology was vendored here too until it was transcribed into
  `Tptp.Szs.Ontology` by hand; `NOTICE` attributes the transcription, and there is
  no longer a file to digest.
  """

  use ExUnit.Case, async: true

  alias Tptp.Resolver.Http

  @notice Path.join(__DIR__, "../../NOTICE") |> Path.expand()
  @bnf Path.join(__DIR__, "../../priv/bnf/SyntaxBNF-v9.3.1.3") |> Path.expand()

  @external_resource @notice

  defp digests do
    @notice
    |> File.read!()
    |> then(&Regex.scan(~r/^\s+(\S+)\n\s+sha256 ([0-9a-f]{64})$/m, &1))
    |> Map.new(fn [_whole, source, digest] -> {source, digest} end)
  end

  defp digest(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  test "NOTICE names the vendored file" do
    recorded = digests()

    assert map_size(recorded) == 1
    assert Map.has_key?(recorded, "https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html")
  end

  test "the vendored BNF is the file NOTICE attributes" do
    assert digest(@bnf) == digests()["https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html"]
  end

  @tag :network
  test "the vendored BNF still matches its page upstream" do
    assert {:ok, page} = fetch("https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html")

    assert String.trim_trailing(File.read!(@bnf)) == plain_text(page)
  end

  defp plain_text(page) do
    page
    |> String.replace(~r/<HEAD>.*?<\/HEAD>/is, "")
    |> String.replace(~r/<BR\s*\/?>[ \t]*\r?\n?/i, "\n")
    |> String.replace(~r/<[^>]*>/, "")
    |> unescape()
    |> String.trim_trailing()
    |> String.trim_leading("\n")
  end

  defp unescape(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
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
