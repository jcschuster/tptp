defmodule Tptp.TstpTest do
  @moduledoc """
  Reading TSTP solution files: the archived ones the TSTP library serves, the
  `X2TPTP` replies SystemOnTPTP builds on the spot, and everything that only looks
  like one.

  The fixtures are captures, not examples — `test/fixtures/tstp/README.md` says
  where each came from — because a solution file's shape is whatever the TSTP's
  tooling writes, and the parts this reader relies on (a rule at the top, a `File`
  key, continuation lines, the `ORIGINAL SYSTEM OUTPUT` marker) are conventions
  rather than a grammar. So the two live files are asserted against in detail, and
  a hand-written minimal file covers the fields they do not exercise: a missing
  original section, an empty solution region, `\\r\\n` line ends.

  The negative cases matter as much. `{:error, :not_tstp}` is what a caller holding
  an arbitrary prover reply gets, so a raw log, a StarExec capture and an empty
  string all have to land there rather than be read as a file whose header is the
  prover's banner.
  """

  use ExUnit.Case, async: true

  doctest Tptp.Tstp
  doctest Tptp.Tstp.Solution

  alias Tptp.Diagnostic
  alias Tptp.Szs
  alias Tptp.Tstp
  alias Tptp.Tstp.Solution

  @archived "test/fixtures/tstp/E---3.5.1.THM-CRf.s"
  @reply "test/fixtures/tstp/e_cnfrefutation_x2tptp.txt"

  # Key, value, rule and marker lines are all this file cares about, so the rules are
  # written short; nothing reads their width.
  @minimal """
  %----------------
  % File     : x
  % Result   : Unsatisfiable 0.1s
  % Output   : Refutation 0.1s
  % Comments :
  %----------------
  fof(a, axiom, p).
  %----------------
  %----ORIGINAL SYSTEM OUTPUT
  % % SZS status Unsatisfiable
  % % done
  %----------------
  """

  describe "the archived solution file" do
    setup do
      {:ok, solution, diagnostics} = Tstp.from_file(@archived)

      %{input: File.read!(@archived), solution: solution, diagnostics: diagnostics}
    end

    test "reads the header, keys in the order the file writes them", %{solution: solution} do
      assert solution.header["File"] == "E---3.5.1"
      assert String.starts_with?(solution.header["Problem"], "PUZ001+1 : TPTP")

      assert solution.keys == [
               "File",
               "Problem",
               "Transfm",
               "Format",
               "Command",
               "Computer",
               "Model",
               "CPU",
               "Memory",
               "OS",
               "CPULimit",
               "WCLimit",
               "DateTime",
               "Result",
               "Output",
               "Verified",
               "SZS Type",
               "Syntax",
               "Comments"
             ]
    end

    test "joins continuation lines onto the key they continue", %{solution: solution} do
      assert solution.header["SZS Type"] ==
               "Refutation\nDerivation depth      :    8\nNumber of leaves      :   11"

      # `Verified :` with nothing after it is a key with an empty value, not a key the
      # file does not have.
      assert solution.header["Verified"] == ""
      assert "Verified" in solution.keys
    end

    test "resolves Result and Output through the ontology", %{solution: solution} do
      assert solution.result == :theorem
      assert solution.output == :cnf_refutation

      # The timings after the status word are a system's self-report and stay text.
      assert solution.header["Result"] == "Theorem 0.12s 0.45s"
    end

    test "parses the derivation and nothing else", %{solution: solution, diagnostics: []} do
      assert length(solution.solution.statements) == 54
      assert solution.solution.diagnostics == []

      # The header states what the solution holds; this is the one join between the
      # two halves of the file that can be checked.
      assert solution.header["Syntax"] =~ "Number of formulae    :   54"
    end

    test "spans index the whole file, not the region", %{input: input, solution: solution} do
      {offset, length} = solution.span.solution

      assert binary_part(input, offset, 4) == "fof("
      assert input |> binary_part(offset, length) |> String.ends_with?("[proof] ).")

      {original, _length} = solution.span.original
      assert binary_part(input, original, 12) == "% 0.00/0.03 "
    end

    test "hands the archived output back for the SZS reader", %{solution: solution} do
      assert String.starts_with?(solution.original, "0.00/0.03  % Problem  : PUZ001+1")
      assert Szs.status(solution.original) == {:ok, :theorem, nil, nil}

      # The proof block was lifted out into the solution region and never closed, so
      # there is no block left to find — with or without the StarExec stamps.
      assert solution.original =~ "% SZS output start CNFRefutation"
      assert solution.original =~ "See solution above"
      assert Szs.blocks(solution.original) == []
      assert Szs.blocks(solution.original, prefix: Szs.prefix(:starexec)) == []
    end

    test "names its system and its problem", %{solution: solution} do
      assert Solution.system(solution) == "E---3.5.1"
      assert Solution.problem(solution) == "PUZ001+1"
    end

    test "inspects as one line that does not print the log", %{solution: solution} do
      rendered = inspect(solution)

      assert rendered ==
               ~s(#Tptp.Tstp.Solution<"E---3.5.1": ) <>
                 ~s(:theorem/:cnf_refutation, 54 statements, 6.6 KB of output>)

      refute rendered =~ "Proof found"
    end
  end

  describe "the X2TPTP reply" do
    setup do
      {:ok, solution, diagnostics} = Tstp.from_file(@reply)

      %{solution: solution, diagnostics: diagnostics}
    end

    test "has the same shape as an archived file", %{solution: solution, diagnostics: []} do
      assert solution.header["File"] == "E---3.5.1"
      assert solution.result == :theorem
      assert solution.output == :cnf_refutation
      assert length(solution.solution.statements) == 54
      assert solution.header["SZS Type"] =~ "\n"
      assert Solution.problem(solution) == "PUZ001+1"
      assert List.last(solution.keys) == "Comments"
    end

    test "archives the system's own output, proof block and all", %{solution: solution} do
      assert solution.original =~ "% Proof found!"
      assert solution.original =~ "% SZS output start CNFRefutation"
      assert solution.original =~ "See solution above"
      assert Szs.status(solution.original) == {:ok, :theorem, nil, nil}
      assert Szs.blocks(solution.original) == []
    end
  end

  describe "a minimal file" do
    test "fills every field" do
      {:ok, solution, []} = Tstp.from_string(@minimal)

      assert solution.header == %{
               "File" => "x",
               "Result" => "Unsatisfiable 0.1s",
               "Output" => "Refutation 0.1s",
               "Comments" => ""
             }

      assert solution.keys == ["File", "Result", "Output", "Comments"]
      assert solution.result == :unsatisfiable
      assert solution.output == :refutation
      assert Enum.map(solution.solution.statements, & &1.name.text) == ["a"]
      assert solution.original == "% SZS status Unsatisfiable\n% done"

      {offset, length} = solution.span.solution
      assert binary_part(@minimal, offset, length) == "fof(a, axiom, p)."

      {offset, length} = solution.span.original
      assert binary_part(@minimal, offset, length) == "% % SZS status Unsatisfiable\n% % done"
    end

    test "reads the same with \\r\\n line ends" do
      source = String.replace(@minimal, "\n", "\r\n")

      {:ok, solution, []} = Tstp.from_string(source)

      assert solution.header["Result"] == "Unsatisfiable 0.1s"
      assert solution.keys == ["File", "Result", "Output", "Comments"]
      assert solution.result == :unsatisfiable
      assert length(solution.solution.statements) == 1
      assert Szs.status(solution.original) == {:ok, :unsatisfiable, nil, nil}
    end

    test "has no original section when the marker is absent" do
      source = String.replace(@minimal, "%----ORIGINAL SYSTEM OUTPUT\n", "")

      {:ok, solution, []} = Tstp.from_string(source)

      assert solution.original == nil
      assert solution.span.original == nil
      assert length(solution.solution.statements) == 1
    end

    test "has no original section when the file ends after the derivation" do
      source = """
      %----------------
      % File     : x
      %----------------
      fof(a, axiom, p).
      """

      {:ok, solution, []} = Tstp.from_string(source)

      assert solution.original == nil
      assert solution.span.original == nil
      assert length(solution.solution.statements) == 1
    end

    test "holds no solution when the region between the rules is empty" do
      source = String.replace(@minimal, "fof(a, axiom, p).\n", "\n")

      {:ok, solution, []} = Tstp.from_string(source)

      assert solution.solution == nil
      assert match?({_offset, 0}, solution.span.solution)
      assert solution.original == "% SZS status Unsatisfiable\n% done"
      assert inspect(solution) =~ "no solution"
    end

    test "a continuation before any key, and a bare % line, are skipped" do
      source = """
      %----------------
      %            orphaned
      %
      % File     : x
      %
      %----------------
      """

      {:ok, solution, []} = Tstp.from_string(source)

      assert solution.header == %{"File" => "x"}
      assert solution.keys == ["File"]
    end
  end

  describe "what is not a solution file" do
    test "an empty string" do
      assert Tstp.from_string("") == {:error, :not_tstp}
    end

    test "a raw prover log, whatever it found" do
      for fixture <- [
            "test/fixtures/tstp/e_cnfrefutation_raw.txt",
            "test/fixtures/tstp/e_saturation_raw.txt",
            "test/fixtures/tstp/vampire_proof_raw.txt",
            "test/fixtures/szs/starexec_e_theorem.txt"
          ] do
        assert Tstp.from_file(fixture) == {:error, :not_tstp}, fixture
      end
    end

    test "a problem file" do
      assert Tstp.from_string("fof(a, axiom, p).\n") == {:error, :not_tstp}
    end

    test "a rule that is not the first thing in the input" do
      source = "% SZS status Theorem\n%----------------\n% File : E\n%----------------\n"

      assert Tstp.from_string(source) == {:error, :not_tstp}
    end

    test "a header without a File key" do
      source = "%----------------\n% Result : Theorem\n%----------------\n"

      assert Tstp.from_string(source) == {:error, :not_tstp}
    end
  end

  describe "from_file/2" do
    test "fails with a diagnostic when the file cannot be read" do
      assert {:error, [%Diagnostic{} = diagnostic]} = Tstp.from_file("test/fixtures/tstp/nope.s")

      assert diagnostic.code == "TPTP0001"
      assert diagnostic.severity == :error
      assert diagnostic.message =~ "nope.s"
    end

    test "names the file in what it parses" do
      {:ok, solution, []} = Tstp.from_file(@reply)

      assert solution.solution.path == @reply
    end
  end
end
