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

  # Zero-byte axiom files in TPTP v9.3.1: `ITP115`, `ITP122` and `ITP125` in their
  # `+4 +5 ^4 ^5 ^7 _4 _5 _7` versions, which Geoff Sutcliffe removes in the next
  # release.
  @empty for n <- ~w(115 122 125),
             v <- ~w(+4 +5 ^4 ^5 ^7 _4 _5 _7),
             do: "ITP#{n}#{v}.ax"

  setup_all do
    files = Corpus.files(every: 3)

    if files == [] do
      raise "no TPTP library found; set $TPTP_ROOT to enable the corpus tests"
    end

    %{files: Enum.reject(files, &(Path.basename(&1) in @empty))}
  end

  test "every file has a closed header that reads as the TPTP writes it", %{files: files} do
    failures =
      files
      |> Task.async_stream(&check/1, ordered: false, timeout: :infinity)
      |> Enum.flat_map(fn {:ok, result} -> result end)

    assert failures == []
  end

  test "the files excluded as empty are still there and still empty" do
    # The same guarantee `Mix.Tasks.Tptp.Corpus.known_failures/0` gets: an exception
    # that stopped being needed fails here rather than sitting above unnoticed.
    found = Map.new(Corpus.files(), &{Path.basename(&1), &1})

    for name <- @empty do
      path = Map.get(found, name)

      assert path != nil, "#{name} is gone from the library — drop it from @empty"
      assert File.stat!(path).size == 0, "#{name} has content now — drop it from @empty"
    end
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
