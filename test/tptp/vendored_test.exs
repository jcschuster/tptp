defmodule Tptp.VendoredTest do
  @moduledoc """
  The two vendored TPTP World files, against what `NOTICE` says about them.

  `NOTICE` is the package's attribution, and the TPTP's terms permit redistribution
  only of *verbatim* copies — so "unmodified" is a claim with legal weight, not a
  nicety. These tests read the digests out of `NOTICE` itself rather than repeating
  them, so the file cannot drift from the bytes it describes: editing a vendored
  file without updating its attribution fails here, and so does the reverse.

  The `:network` tests are the other half, excluded by default because a test suite
  should not need tptp.org to pass. Run them when bumping a TPTP release:

      mix test --include network

  There is one per vendored file, because `NOTICE` makes the same verbatim claim for
  both and a claim checked on one of two files is checked on neither.

  The BNF is reconstructed the way a browser copy does — `<BR>` to newline, tags
  stripped, entities and `&nbsp;` undone — because that is exactly how the vendored
  copy was made, and compared. Trailing white space is ignored on both sides: the
  page ends with a long run of `&nbsp;<P>` padding so that its anchors have
  somewhere to scroll to, and 43 spaces of scroll room are not part of the grammar.

  The SZS page needs none of that. It is vendored as its own markup, byte for byte,
  so the check is the digest and nothing else — and a difference there is a fact
  about the release rather than about how the copy was taken.
  """

  use ExUnit.Case, async: true

  alias Tptp.Resolver.Http
  alias Tptp.Szs.Ontology

  @notice Path.join(__DIR__, "../../NOTICE") |> Path.expand()
  @bnf Path.join(__DIR__, "../../priv/bnf/SyntaxBNF-v9.3.1.2") |> Path.expand()
  @szs Path.join(__DIR__, "../../priv/szs/SZSOntology-2026-08-31.html") |> Path.expand()

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

  test "NOTICE names both vendored files" do
    recorded = digests()

    assert map_size(recorded) == 2
    assert Map.has_key?(recorded, "https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html")
    assert Map.has_key?(recorded, "https://tptp.org/UserDocs/SZSOntology")
  end

  test "the vendored BNF is the file NOTICE attributes" do
    assert digest(@bnf) == digests()["https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html"]
  end

  test "the vendored SZS ontology is the file NOTICE attributes" do
    assert digest(@szs) == digests()["https://tptp.org/UserDocs/SZSOntology"]
  end

  test "the generated ontology was built from the vendored page" do
    assert Ontology.digest() == digest(@szs)
    assert Path.basename(@szs) == Ontology.vendored()
  end

  @tag :network
  test "the vendored BNF still matches its page upstream" do
    assert {:ok, page} = fetch("https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html")

    assert String.trim_trailing(File.read!(@bnf)) == plain_text(page)
  end

  @tag :network
  test "the vendored SZS ontology still matches its page upstream" do
    assert {:ok, page} = fetch("https://tptp.org/UserDocs/SZSOntology")

    assert :sha256 |> :crypto.hash(page) |> Base.encode16(case: :lower) == digest(@szs),
           "the SZS page has changed; re-vendor it, run `mix tptp.gen`, and update NOTICE"
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
