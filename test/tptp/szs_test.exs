defmodule Tptp.SzsTest do
  @moduledoc """
  The SZS layer: the generated ontology, the hand-transcribed page, and the reader
  for what provers print.

  `Tptp.Szs.Ontology` is generated from the SZS BNF, so what these tests check is
  the shape the generator promises — a closed set of values, a partition into three
  ontologies, a hierarchy that is a DAG — and the two joins the BNF cannot make on
  its own: that `Tptp.Szs.Page` transcribes a mnemonic and a description for every
  value the BNF defines, and that the `<inference_status_value>` list the
  vocabulary takes from the BNF is exactly the success ontology's mnemonics in
  lower case. The rest assert that the reader survives the shapes real prover
  output comes in.
  """

  use ExUnit.Case, async: true

  doctest Tptp.Szs
  doctest Tptp.Szs.Ontology
  doctest Tptp.Szs.Page

  alias Tptp.Bnf
  alias Tptp.Bnf.Vocabulary
  alias Tptp.Szs
  alias Tptp.Szs.Ontology
  alias Tptp.Szs.Page

  describe "the ontology" do
    test "holds the three ontologies, and nothing has escaped its own" do
      values = Ontology.values()

      assert length(values) == Ontology.count()
      assert Ontology.ontologies() == [:success, :no_success, :data]
      assert Enum.count(values, &Ontology.success?/1) == 53
      assert Enum.count(values, &Ontology.no_success?/1) == 29
      assert Enum.count(values, &Ontology.data?/1) == 30

      for value <- values do
        assert Ontology.ontology(value) in Ontology.ontologies()
        assert Ontology.success?(value) or Ontology.no_success?(value) or Ontology.data?(value)
      end
    end

    test "matches the committed module" do
      {source, _report} = Tptp.Bnf.Szs.generate(Bnf.szs_path!())
      formatted = source |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")

      assert File.read!("lib/tptp/szs/ontology.ex") == formatted,
             "lib/tptp/szs/ontology.ex is stale; run `mix tptp.gen`"
    end

    test "names and atoms round-trip" do
      for value <- Ontology.values() do
        assert Ontology.from_string(Ontology.name(value)) == {:ok, value}
      end
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
      assert Ontology.source() =~ "TPTPWorld/SZSOntologies"
      assert Page.source() == "https://szs.tptp.org"
    end

    test "the values list and the lookups agree on membership" do
      assert length(Ontology.values()) == Ontology.count()
      assert length(Enum.uniq(Ontology.values())) == Ontology.count()

      for value <- Ontology.values() do
        assert Ontology.value?(value)
      end
    end

    test "no two values share a name" do
      names = Enum.map(Ontology.values(), &Ontology.name/1)

      assert length(Enum.uniq(names)) == length(names)
    end

    test "a name the page corrected is carried at its current spelling alone" do
      # The page spelled this `CounterTautologyyPreserving` until the move to
      # szs.tptp.org, and the BNF was written after the move.
      assert Ontology.name(:counter_tautology_preserving) == "CounterTautologyPreserving"
      assert Ontology.from_status_value("ctp") == {:ok, :counter_tautology_preserving}
      assert Ontology.from_mnemonic("CTP") == {:ok, :counter_tautology_preserving}
      assert Ontology.from_string("CounterTautologyyPreserving") == :error
    end
  end

  describe "the hierarchy" do
    test "parents and children are the two ends of the same edges" do
      for value <- Ontology.values(), child <- Ontology.children(value) do
        assert value in Ontology.parents(child)
      end

      for value <- Ontology.values(), parent <- Ontology.parents(value) do
        assert value in Ontology.children(parent)
      end
    end

    test "the three roots have no parents, and every other value has at least one" do
      for value <- Ontology.values() do
        if value in Ontology.ontologies() do
          assert Ontology.parents(value) == []
        else
          assert Ontology.parents(value) != []
        end
      end
    end

    test "it is acyclic: no value is among its own ancestors" do
      for value <- Ontology.values() do
        refute value in Ontology.ancestors(value)
        refute value in Ontology.descendants(value)
      end
    end

    test "ancestors and descendants are the closures of parents and children" do
      for value <- Ontology.values() do
        expected =
          Ontology.parents(value)
          |> Enum.flat_map(&[&1 | Ontology.ancestors(&1)])
          |> Enum.uniq()
          |> Enum.sort()

        assert Enum.sort(Ontology.ancestors(value)) == expected
      end

      for value <- Ontology.values(), descendant <- Ontology.descendants(value) do
        assert value in Ontology.ancestors(descendant)
      end
    end

    test "every value descends from exactly one root, which is its ontology" do
      for value <- Ontology.values() do
        above = [value | Ontology.ancestors(value)]
        assert Enum.filter(Ontology.ontologies(), &(&1 in above)) == [Ontology.ontology(value)]
      end
    end

    test "isa? is reflexive, follows the edges, and is not symmetric" do
      assert Ontology.isa?(:theorem, :theorem)
      assert Ontology.isa?(:theorem, :satisfiability_preserving)
      assert Ontology.isa?(:theorem, :tautology_preserving)
      assert Ontology.isa?(:theorem, :success)
      refute Ontology.isa?(:success, :theorem)
      refute Ontology.isa?(:theorem, :counter_theorem)
      refute Ontology.isa?(:theorem, :satisfiable)
    end

    test "the DAG is not a tree" do
      assert length(Ontology.parents(:theorem)) == 3
      assert Enum.any?(Ontology.values(), &(length(Ontology.parents(&1)) > 1))
    end

    test "the no-success ontology reaches Error through GaveUp alone" do
      assert Ontology.parents(:error) == [:gave_up]
      assert Ontology.isa?(:syntax_error, :gave_up)
      assert Ontology.isa?(:syntax_error, :unknown)
    end

    test "the one terminal with arguments names its domains, which are not its parents" do
      assert Ontology.arguments(:assumed) == [:unknown, :success]
      assert Ontology.children(:assumed) == []
      assert Ontology.parents(:assumed) == [:no_success]
      refute Ontology.isa?(:success, :assumed)

      for value <- Ontology.values(), value != :assumed do
        assert Ontology.arguments(value) == []
      end
    end
  end

  describe "the page" do
    test "transcribes a mnemonic and a description for every value the BNF defines" do
      for value <- Ontology.values() do
        assert Page.mnemonic(value) =~ ~r/^[A-Za-z]+$/, "#{value} has no mnemonic"
        assert Page.describe(value) != "", "#{value} has no description"
      end
    end

    test "mnemonics resolve back to their values" do
      for value <- Ontology.values() do
        assert {tag, resolved} = Page.from_mnemonic(Page.mnemonic(value))

        case tag do
          :ok -> assert resolved == value
          :ambiguous -> assert value in resolved
        end
      end
    end

    test "the ontology delegates to it" do
      for value <- Ontology.values() do
        assert Ontology.mnemonic(value) == Page.mnemonic(value)
        assert Ontology.describe(value) == Page.describe(value)
      end
    end

    test "case distinguishes two mnemonics the ontologies share" do
      assert Page.from_mnemonic("SAT") == {:ok, :satisfiable}
      assert Page.from_mnemonic("Sat") == {:ok, :saturation}
      assert Page.from_mnemonic("sat") == :error
    end

    test "a mnemonic the page reuses is reported as ambiguous, not guessed" do
      assert {:ambiguous, values} = Page.from_mnemonic("IIn")
      assert :infinite_interpretation in values
      assert :incomplete_interpretation in values
    end

    test "the one value whose mnemonic takes arguments is here, under its bare code" do
      assert Ontology.from_string("Assumed") == {:ok, :assumed}
      assert Page.mnemonic(:assumed) == "ASS"
      assert Page.from_mnemonic("ASS") == {:ok, :assumed}
      assert Ontology.ontology(:assumed) == :no_success
      assert Page.describe(:assumed) =~ "has been assumed"
    end

    test "ASS and Ass are two values, and case is what tells them apart" do
      assert Page.from_mnemonic("ASS") == {:ok, :assumed}
      assert Page.from_mnemonic("Ass") == {:ok, :assurance}
      assert Ontology.ontology(:assurance) == :data
    end
  end

  describe "<inference_status_value>" do
    test "every value the vocabulary admits in status(...) resolves to a success value" do
      for word <- Vocabulary.status_value_values() do
        assert {:ok, value} = Page.from_status_value(word), "#{word} is not transcribed"
        assert Ontology.success?(value), "#{word} resolved outside the success ontology"
        assert String.downcase(Page.mnemonic(value)) == word
      end
    end

    test "it is exactly Success and the semantic-success subtree, in lower case" do
      expected =
        [:success | Ontology.descendants(:semantic_success)]
        |> List.insert_at(1, :semantic_success)
        |> Enum.map(&String.downcase(Page.mnemonic(&1)))
        |> Enum.sort()

      assert Enum.sort(Vocabulary.status_value_values()) == expected

      for value <-
            Ontology.descendants(:type_check_success) ++ Ontology.descendants(:verify_success) do
        refute String.downcase(Page.mnemonic(value)) in Vocabulary.status_value_values()
      end
    end

    test "from_status_value/1 answers for the success ontology alone" do
      for value <- Ontology.values() do
        word = String.downcase(Page.mnemonic(value))

        case Page.from_status_value(word) do
          {:ok, resolved} -> assert Ontology.success?(resolved)
          :error -> refute Ontology.success?(value) and word in Vocabulary.status_value_values()
        end
      end
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
end
