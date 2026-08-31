defmodule Tptp.SzsTest do
  @moduledoc """
  The SZS layer: the generated ontology, and the reader for what provers print.

  The gate the plan asks for here is narrower than the earlier phases' because the
  vocabulary is generated rather than written. What is worth asserting is that the
  generation agreed with the *other* vendored file — every `<status_value>` the BNF
  admits inside a `status(...)` annotation resolves to a success-ontology value —
  and that the reader survives the shapes real prover output comes in.
  """

  use ExUnit.Case, async: true

  doctest Tptp.Szs
  doctest Tptp.Szs.Ontology
  doctest Tptp.Szs.Extract

  alias Tptp.Bnf.Vocabulary
  alias Tptp.Szs
  alias Tptp.Szs.Ontology

  describe "the generated ontology" do
    test "holds the three ontologies, and nothing has escaped its own" do
      values = Ontology.values()

      assert length(values) == Ontology.count()
      assert Enum.count(values, &Ontology.success?/1) > 40
      assert Enum.count(values, &Ontology.no_success?/1) > 20
      assert Enum.count(values, &Ontology.data?/1) > 20

      for value <- values do
        assert Ontology.success?(value) or Ontology.no_success?(value) or Ontology.data?(value)
      end
    end

    test "every BNF <status_value> is a success-ontology mnemonic" do
      unresolved =
        for word <- Vocabulary.status_value_values(),
            Ontology.from_status_value(word) == :error,
            do: word

      assert unresolved == []
    end

    test "a status value resolves to a value the success ontology holds" do
      for word <- Vocabulary.status_value_values() do
        assert {:ok, value} = Ontology.from_status_value(word)
        assert Ontology.success?(value), "#{word} resolved outside the success ontology"
        assert String.downcase(Ontology.mnemonic(value)) == word
      end
    end

    test "names and atoms round-trip" do
      for value <- Ontology.values() do
        assert Ontology.from_string(Ontology.name(value)) == {:ok, value}
      end
    end

    test "case distinguishes two mnemonics the ontologies share" do
      assert Ontology.from_mnemonic("SAT") == {:ok, :satisfiable}
      assert Ontology.from_mnemonic("Sat") == {:ok, :saturation}
      assert Ontology.from_mnemonic("sat") == :error
    end

    test "a mnemonic the page reuses is reported as ambiguous, not guessed" do
      assert {:ambiguous, values} = Ontology.from_mnemonic("IIn")
      assert :infinite_interpretation in values
      assert :incomplete_interpretation in values
    end

    test "no atom is created from an unknown word" do
      before = :erlang.system_info(:atom_count)

      for word <- ["NotAStatus", "Th30rem", "", "theorem"] do
        assert Ontology.from_string(word) == :error
        assert Ontology.value?(word) == false
      end

      assert :erlang.system_info(:atom_count) == before
    end

    test "it says where it came from" do
      assert Ontology.source() =~ "tptp.org"
      assert Ontology.vendored() =~ "SZSOntology"
      assert String.length(Ontology.digest()) == 64
    end

    test "the page's own typo is preserved rather than corrected" do
      assert Ontology.name(:counter_tautologyy_preserving) == "CounterTautologyyPreserving"
      assert Ontology.from_status_value("ctp") == {:ok, :counter_tautologyy_preserving}
    end
  end

  describe "reading a status line" do
    test "the plain form" do
      assert Szs.status("% SZS status Theorem for PUZ001+1") == {:ok, :theorem, "PUZ001+1", nil}
    end

    test "the form with a comment" do
      output = "% SZS status GaveUp for X : Could not complete CNF conversion"

      assert Szs.status(output) == {:ok, :gave_up, "X", "Could not complete CNF conversion"}
    end

    test "it is found among the noise a prover actually prints" do
      output = """
      % Running in auto input_syntax mode.
      % Refutation found. Thanks to Tanya!
      % SZS status Unsatisfiable for GRP001-1
      % SZS output start Proof for GRP001-1
      cnf(c1, axiom, p).
      % SZS output end Proof for GRP001-1
      % Time elapsed: 0.012 s
      """

      assert Szs.status(output) == {:ok, :unsatisfiable, "GRP001-1", nil}
      assert Szs.success?(output)
    end

    test "the last word wins" do
      output = "% SZS status Theorem for X\n% SZS status GaveUp for X\n"

      assert Szs.status(output) == {:ok, :gave_up, "X", nil}
      assert length(Szs.statuses(output)) == 2
      refute Szs.success?(output)
    end

    test "an unrecognised value comes back as a binary" do
      assert Szs.status("% SZS status Unknown_thing for X") ==
               {:error, "Unknown_thing", "X", nil}

      refute Szs.success?("% SZS status Unknown_thing for X")
    end

    test "no status is not an error" do
      assert Szs.status("just some prover chatter") == :none
      assert Szs.value("") == :none
      refute Szs.success?("")
    end

    test "leading white space and spacing variations are tolerated" do
      for line <- [
            "  % SZS status Theorem for X",
            "%SZS status Theorem for X",
            "% SZS  status   Theorem   for   X  "
          ] do
        assert {:ok, :theorem, "X", nil} = Szs.status(line), "#{inspect(line)} did not parse"
      end
    end
  end

  describe "reading output blocks" do
    test "a delimited block yields its body without the markers" do
      output = """
      % SZS output start CNFRefutation for X
      cnf(c1, axiom, p).
      cnf(c2, axiom, ~p).
      % SZS output end CNFRefutation for X
      """

      assert [block] = Szs.blocks(output)
      assert block.dataform == :cnf_refutation
      assert block.problem == "X"
      assert block.body == "cnf(c1, axiom, p).\ncnf(c2, axiom, ~p)."
    end

    test "the body of a block parses as TPTP" do
      output = Szs.output_block(:proof, "X", "fof(a, axiom, p).\nfof(b, axiom, q).")

      assert [block] = Szs.blocks(output)
      assert {:ok, file, []} = Tptp.from_string(block.body)
      assert length(file.statements) == 2
    end

    test "several blocks come back in order" do
      output =
        Enum.join(
          [
            Szs.output_block(:proof, "A", "fof(a,axiom,p)."),
            Szs.output_block(:finite_model, "B", "fof(b,axiom,q).")
          ],
          "\n"
        )

      assert [one, two] = Szs.blocks(output)
      assert {one.dataform, one.problem} == {:proof, "A"}
      assert {two.dataform, two.problem} == {:finite_model, "B"}
    end

    test "an unterminated block is dropped, not guessed at" do
      assert Szs.blocks("% SZS output start Proof for X\nfof(a,axiom,p).\n") == []
    end

    test "a block whose dataform is not in the ontology is dropped" do
      output = "% SZS output start Nonsense for X\nbody\n% SZS output end Nonsense for X\n"

      assert Szs.blocks(output) == []
    end

    test "an end for a different problem does not close the block" do
      output = "% SZS output start Proof for A\nbody\n% SZS output end Proof for B\n"

      assert Szs.blocks(output) == []
    end
  end

  describe "writing" do
    test "a status line round-trips through the reader" do
      line = Szs.status_line(:counter_satisfiable, "PUZ001+1", "found a model")

      assert Szs.status(line) == {:ok, :counter_satisfiable, "PUZ001+1", "found a model"}
    end

    test "an output block round-trips through the reader" do
      block = Szs.output_block(:cnf_refutation, "X", "cnf(c, axiom, p).")

      assert [%{dataform: :cnf_refutation, problem: "X", body: "cnf(c, axiom, p)."}] =
               Szs.blocks(block)
    end

    test "every value can be written and read back" do
      for value <- Ontology.values() do
        line = Szs.status_line(value, "X")

        assert Szs.status(line) == {:ok, value, "X", nil}
      end
    end
  end

  describe "the vendored page" do
    test "there is exactly one, and it is what the ontology was built from" do
      path = Szs.vendored_path!()

      assert Path.basename(path) == Ontology.vendored()

      digest =
        path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

      assert digest == Ontology.digest()
    end
  end
end
