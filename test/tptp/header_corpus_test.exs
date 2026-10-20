defmodule Tptp.HeaderCorpusTest do
  @moduledoc """
  `Tptp.Header` against the real TPTP library: every file has a header, every
  header line is a form the reader knows but the twelve it reports, and every
  `Status` is a value of the SZS ontology.

  Only the head of each file is read, so this costs seconds where the parse
  sweeps cost hours. Excluded by default. Run with `mix test --include corpus`.
  """

  use ExUnit.Case, async: true

  alias Tptp.Header
  alias Tptp.Test.Corpus

  @moduletag :corpus
  @moduletag timeout: Corpus.timeout()

  # The longest header in TPTP v9.3.1 is far below this; a header that reached it
  # would end without its closing rule, which the test below refuses.
  @head 262_144

  # Each writes `Refs`, `Source` and `Names` without a colon.
  @colonless ~w(MGT087+1.p MGT088+1.p MGT105+1.p MGT108+1.p)

  setup_all do
    files = Corpus.files(every: 3)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: files}
  end

  test "every file has a closed header that reads as the TPTP writes it", %{files: files} do
    failures =
      files
      |> Task.async_stream(&check/1, ordered: false, timeout: :infinity)
      |> Enum.flat_map(fn {:ok, result} -> result end)

    assert failures == []
  end

  defp check(path) do
    head = head(path)
    name = Path.basename(path)

    case Header.from_string(head) do
      {:ok, header, diagnostics} ->
        {offset, length} = header.span

        List.flatten([
          if(offset + length == byte_size(head), do: {name, :no_closing_rule}, else: []),
          if(Header.status(header) == nil, do: {name, :status}, else: []),
          case {name in @colonless, Enum.map(diagnostics, & &1.code)} do
            {true, ["TPTP0901", "TPTP0901", "TPTP0901"]} -> []
            {false, []} -> []
            {_expected, codes} -> {name, codes}
          end
        ])

      {:error, :no_header} ->
        [{name, :no_header}]
    end
  end

  defp head(path) do
    File.open!(path, [:read, :binary], fn device ->
      case IO.binread(device, @head) do
        :eof -> ""
        data -> data
      end
    end)
  end
end
