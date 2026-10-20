defmodule Tptp.HeaderTest do
  use ExUnit.Case, async: true

  alias Tptp.Diagnostic
  alias Tptp.Header

  doctest Tptp.Header

  @puzzle "test/fixtures/headers/PUZ001+1.p"
  @colonless "test/fixtures/headers/MGT087+1.p"

  describe "a problem file" do
    setup do
      {:ok, header, diagnostics} = Header.from_file(@puzzle)

      %{header: header, diagnostics: diagnostics}
    end

    test "reads every key, in the order the file writes them", %{
      header: header,
      diagnostics: []
    } do
      assert header.keys == ~w(File Domain Problem Version English Refs Source Names
                               Status Rating Syntax SPC Comments)
    end

    test "keeps the value whole after the first colon", %{header: header} do
      assert Header.get(header, "File") == "PUZ001+1 : TPTP v9.3.1. Released v2.0.0."
    end

    test "joins wrapped prose into one entry", %{header: header} do
      assert [english] = Header.entries(header, "English")
      assert english =~ ~r/^Someone who lives in Dreadbury Mansion killed Aunt Agatha\.\nAgatha/
      assert String.ends_with?(english, "Therefore : Agatha killed herself.")
    end

    test "starts an entry at each `%          :` line", %{header: header} do
      assert Header.entries(header, "Comments") == [
               "Modified by Geoff Sutcliffe.",
               ~s(Also known as "Who killed Aunt Agatha")
             ]

      assert Header.get(header, "Comments") ==
               ~s(Modified by Geoff Sutcliffe.\nAlso known as "Who killed Aunt Agatha")
    end

    test "keeps the Syntax counts as continuation lines", %{header: header} do
      assert [syntax] = Header.entries(header, "Syntax")
      assert syntax =~ ~r/^Number of formulae    :   14/
      assert syntax =~ "\nNumber of variables   :   12"
    end

    test "resolves Status and SPC", %{header: header} do
      assert Header.status(header) == :theorem
      assert Header.spc(header) == %{form: "FOF", status: :theorem, features: ["RFO", "SEQ"]}
    end

    test "spans the region between the two rules", %{header: header} do
      source = File.read!(@puzzle)
      {offset, length} = header.span
      region = binary_part(source, offset, length)

      assert String.starts_with?(region, "\n% File     : PUZ001+1")
      assert String.ends_with?(region, ~s(Aunt Agatha"\n))
    end

    test "reads nothing past the header", %{header: header} do
      refute Map.has_key?(header.fields, "----Problem axioms")
      assert Header.get(header, "Missing") == nil
      assert Header.entries(header, "Missing") == []
    end
  end

  describe "a line with no colon" do
    test "is reported, not read as a key" do
      source = File.read!(@colonless)
      {:ok, header, diagnostics} = Header.from_string(source, file: 3)

      assert Enum.map(diagnostics, &{&1.code, &1.severity}) ==
               List.duplicate({"TPTP0901", :warning}, 3)

      assert Enum.map(diagnostics, &binary_part(source, &1.span.offset, &1.span.length)) == [
               "% Refs       [MC+26] Mustafa et al. (2026), Axis Decomposition for ODRL",
               "% Source     [MC+26]",
               "% Names      ODRL500-1.p [MC+26]"
             ]

      assert Enum.all?(diagnostics, &(&1.span.file == 3))
      refute Enum.any?(header.keys, &(&1 in ["Refs", "Source", "Names"]))
      assert Header.status(header) == :theorem
    end
  end

  describe "edge cases" do
    test "a continuation before any key, a bare %, and an empty line are skipped" do
      source = "%----\n%            orphaned\n%\n\n% File : x\n%   : more\n%----\n"

      assert {:ok, header, []} = Header.from_string(source)
      assert Header.entries(header, "File") == ["x", "more"]
    end

    test "an empty value continued keeps no leading line end" do
      source = "%----\n% English  :\n%            prose\n%----\n"

      assert {:ok, header, []} = Header.from_string(source)
      assert Header.get(header, "English") == "prose"
    end

    test "a key written twice keeps its first position and its last value" do
      source = "%----\n% A : 1\n% B : 2\n% A : 3\n%----\n"

      assert {:ok, header, []} = Header.from_string(source)
      assert header.keys == ["A", "B"]
      assert Header.get(header, "A") == "3"
    end

    test "reads the same with \\r\\n line ends" do
      source = File.read!(@puzzle)

      assert {:ok, lf, []} = Header.from_string(source)
      assert {:ok, crlf, []} = Header.from_string(String.replace(source, "\n", "\r\n"))
      assert Header.to_map(crlf) == Header.to_map(lf)
      assert crlf.keys == lf.keys
    end

    test "a header with no closing rule runs to the end of the input" do
      assert {:ok, header, []} = Header.from_string("%----\n% Status : Open\n")
      assert Header.status(header) == :open
    end

    test "an SPC without a form and a status, or a status the ontology lacks" do
      for value <- ["UNK", ""] do
        {:ok, header, []} = Header.from_string("%----\n% SPC : #{value}\n%----\n")
        assert Header.spc(header) == nil
        assert Header.get(header, "SPC") == value
      end

      {:ok, header, []} = Header.from_string("%----\n% SPC : FOF_XYZ\n%----\n")
      assert Header.spc(header) == %{form: "FOF", status: nil, features: []}

      {:ok, header, []} = Header.from_string("%----\n% Status : Unheardof\n%----\n")
      assert Header.status(header) == nil
    end

    test "prefers a problem's Status to a solution's Result" do
      {:ok, header, []} =
        Header.from_string("%----\n% Status : Theorem\n% Result : Open\n%----\n")

      assert Header.status(header) == :theorem
    end
  end

  describe "what has no header" do
    test "input that does not open with a rule" do
      for source <- [
            "",
            "fof(a, axiom, p).\n",
            "% SZS status Theorem\n%----\n% File : x\n%----\n"
          ] do
        assert Header.from_string(source) == {:error, :no_header}, source
      end
    end

    test "a file that cannot be read" do
      assert {:error, [%Diagnostic{code: "TPTP0001"}]} =
               Header.from_file("test/fixtures/headers/nope.p")
    end
  end

  describe "a solution file" do
    test "reads its header the way Tptp.Tstp does" do
      path = "test/fixtures/tstp/E---3.5.1.THM-CRf.s"

      {:ok, header, []} = Header.from_file(path)
      {:ok, solution, []} = Tptp.Tstp.from_file(path)

      assert Header.to_map(header) == solution.header
      assert header.keys == solution.keys
      assert Header.status(header) == solution.result
    end
  end
end
