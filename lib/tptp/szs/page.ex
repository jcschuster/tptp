defmodule Tptp.Szs.Page do
  @moduledoc """
  What <https://szs.tptp.org> says about the SZS values and the BNF does not:
  their mnemonics and their descriptions.

  This module is written by hand and maintained by hand. `Tptp.Szs.Ontology` is
  generated from the vendored `SZSOntology.bnf`, which is the TPTP World's source
  of truth for the values and the `isa` hierarchy among them, and delegates to this
  module for everything else. The page publishes the mnemonics and descriptions in
  prose only, so they are transcribed here and edited when the page changes; the
  test suite checks that every generated value has both, so a value added to the
  BNF fails the build until its entry is transcribed.

  Each value's `describe/1` text is quoted from the page. `NOTICE` carries the
  attribution the TPTP's terms require for it.

  ## Case sensitivity

  `SAT` is `Satisfiable` and `Sat` is `Saturation`, so `from_mnemonic/1` is case
  sensitive. The lower-case three-letter form occurring inside a TPTP
  `status(...)` annotation has a separate entry point, `from_status_value/1`,
  which searches the success ontology alone, that being the only source
  `<inference_status_value>` draws from, as the test suite verifies against the BNF.

  `Ass` and `ASS` are a second such pair: `Ass` is `Assurance` in the data
  ontology and `ASS` is `Assumed` in the no-success ontology.

  ## Arguments of `Assumed`

  Every mnemonic on the page is three letters except one. `Assumed` is
  `ASS(U,S)`: the success value `S` was assumed because the actual result is
  unknown for the no-success reason `U`, where `U` is drawn from the subontology
  beneath `Unknown`. The BNF states the same as
  `<Assumed> ::= Assumed(<Unknown>,<Success>)`, and
  `Tptp.Szs.Ontology.arguments/1` reports the two domains. `mnemonic(:assumed)`
  returns `"ASS"` and `from_mnemonic/1` accepts `"ASS"` alone, since a pair of
  arguments is not a member of a closed set of atoms.

  A consumer reading such a status line must decompose it: take the text
  preceding the first `(`, resolve it here, and resolve the two arguments, which
  are themselves mnemonics, with further calls. The page does not state how the
  form is written in a `% SZS status` line, and the TPTP BNF cannot express it:
  `<status_value>` is a list of plain words, so `status(ass(...))` has no
  derivation. Treat `ASS(...)` as a form to recognise rather than to emit.
  """

  alias Tptp.Szs.Ontology

  @doc """
  The page these mnemonics and descriptions are transcribed from.

  The page carries no version number, so there is nothing finer to report. The
  transcription was last checked against it on 2026-09-10.
  """
  @spec source() :: binary()
  def source, do: "https://szs.tptp.org"

  @doc """
  Turn a three-letter mnemonic into an atom. Case sensitive, because case is
  meaningful: `SAT` is `Satisfiable` and `Sat` is `Saturation`.

  A mnemonic the page reuses answers `{:ambiguous, values}` rather than picking
  one — `IIn` is both `InfiniteInterpretation` and `IncompleteInterpretation`.

      iex> Tptp.Szs.Page.from_mnemonic("THM")
      {:ok, :theorem}
      iex> Tptp.Szs.Page.from_mnemonic("IIn")
      {:ambiguous, [:infinite_interpretation, :incomplete_interpretation]}
      iex> Tptp.Szs.Page.from_mnemonic("thm")
      :error
  """
  @spec from_mnemonic(binary()) :: {:ok, Ontology.t()} | {:ambiguous, [Ontology.t()]} | :error
  def from_mnemonic("ASS"), do: {:ok, :assumed}
  def from_mnemonic("Ass"), do: {:ok, :assurance}
  def from_mnemonic("CAX"), do: {:ok, :contradictory_axioms}
  def from_mnemonic("CEQ"), do: {:ok, :counter_equivalent}
  def from_mnemonic("CMX"), do: {:ok, :counter_model_extending}
  def from_mnemonic("CRf"), do: {:ok, :cnf_refutation}
  def from_mnemonic("CSA"), do: {:ok, :counter_satisfiable}
  def from_mnemonic("CSP"), do: {:ok, :counter_satisfiability_preserving}
  def from_mnemonic("CTH"), do: {:ok, :counter_theorem}
  def from_mnemonic("CTO"), do: {:ok, :cpu_timeout}
  def from_mnemonic("CTP"), do: {:ok, :counter_tautology_preserving}
  def from_mnemonic("CUP"), do: {:ok, :counter_unsatisfiability_preserving}
  def from_mnemonic("Com"), do: {:ok, :comment}
  def from_mnemonic("DIn"), do: {:ok, :domain_interpretation}
  def from_mnemonic("DMo"), do: {:ok, :domain_model}
  def from_mnemonic("Dat"), do: {:ok, :data}
  def from_mnemonic("Der"), do: {:ok, :derivation}
  def from_mnemonic("ECA"), do: {:ok, :equi_counter_tautologous}
  def from_mnemonic("ECS"), do: {:ok, :equi_counter_satisfiable}
  def from_mnemonic("ECT"), do: {:ok, :equivalent_counter_theorem}
  def from_mnemonic("EQV"), do: {:ok, :equivalent}
  def from_mnemonic("ERR"), do: {:ok, :error}
  def from_mnemonic("ESA"), do: {:ok, :equi_satisfiable}
  def from_mnemonic("ETA"), do: {:ok, :equi_tautologous}
  def from_mnemonic("ETH"), do: {:ok, :equivalent_theorem}
  def from_mnemonic("FCS"), do: {:ok, :finitely_counter_satisfiable}
  def from_mnemonic("FCT"), do: {:ok, :finite_counter_theorem}
  def from_mnemonic("FHi"), do: {:ok, :formula_herbrand_interpretation}
  def from_mnemonic("FHm"), do: {:ok, :formula_herbrand_model}
  def from_mnemonic("FIn"), do: {:ok, :finite_interpretation}
  def from_mnemonic("FMo"), do: {:ok, :finite_model}
  def from_mnemonic("FOR"), do: {:ok, :forced}
  def from_mnemonic("FSA"), do: {:ok, :finitely_satisfiable}
  def from_mnemonic("FTH"), do: {:ok, :finite_theorem}
  def from_mnemonic("FTT"), do: {:ok, :finite_tautology}
  def from_mnemonic("FTx"), do: {:ok, :free_text}
  def from_mnemonic("FUN"), do: {:ok, :finitely_unsatisfiable}
  def from_mnemonic("FVE"), do: {:ok, :failed_verified}
  def from_mnemonic("GUP"), do: {:ok, :gave_up}
  def from_mnemonic("HIn"), do: {:ok, :herbrand_interpretation}
  def from_mnemonic("HMo"), do: {:ok, :herbrand_model}
  def from_mnemonic("IAP"), do: {:ok, :inappropriate}
  def from_mnemonic("ICT"), do: {:ok, :incorrect}

  def from_mnemonic("IIn"),
    do: {:ambiguous, [:infinite_interpretation, :incomplete_interpretation]}

  def from_mnemonic("IMo"), do: {:ok, :infinite_model}
  def from_mnemonic("INC"), do: {:ok, :incomplete}
  def from_mnemonic("INE"), do: {:ok, :input_error}
  def from_mnemonic("INP"), do: {:ok, :in_progress}
  def from_mnemonic("IPr"), do: {:ok, :incomplete_proof}
  def from_mnemonic("Int"), do: {:ok, :interpretation}
  def from_mnemonic("LDa"), do: {:ok, :logical_data}
  def from_mnemonic("Lof"), do: {:ok, :list_of_formulae}
  def from_mnemonic("MEX"), do: {:ok, :model_extending}
  def from_mnemonic("MMO"), do: {:ok, :memory_out}
  def from_mnemonic("Mod"), do: {:ok, :model}
  def from_mnemonic("NLd"), do: {:ok, :non_logical_data}
  def from_mnemonic("NOC"), do: {:ok, :no_consequence}
  def from_mnemonic("NOS"), do: {:ok, :no_success}
  def from_mnemonic("NSo"), do: {:ok, :not_a_solution}
  def from_mnemonic("NTT"), do: {:ok, :not_tried}
  def from_mnemonic("NTY"), do: {:ok, :not_tried_yet}
  def from_mnemonic("NVE"), do: {:ok, :not_verified}
  def from_mnemonic("Non"), do: {:ok, :none}
  def from_mnemonic("OPN"), do: {:ok, :open}
  def from_mnemonic("OSE"), do: {:ok, :os_error}
  def from_mnemonic("Prf"), do: {:ok, :proof}
  def from_mnemonic("RSO"), do: {:ok, :resource_out}
  def from_mnemonic("Ref"), do: {:ok, :refutation}
  def from_mnemonic("SAP"), do: {:ok, :satisfiability_preserving}
  def from_mnemonic("SAT"), do: {:ok, :satisfiable}
  def from_mnemonic("SCA"), do: {:ok, :satisfiable_conclusion_contradictory_axioms}
  def from_mnemonic("SCC"), do: {:ok, :satisfiable_counter_conclusion_contradictory_axioms}
  def from_mnemonic("SCT"), do: {:ok, :satisfiable_axioms_counter_theorem}
  def from_mnemonic("SEE"), do: {:ok, :semantic_error}
  def from_mnemonic("SSU"), do: {:ok, :semantic_success}
  def from_mnemonic("STH"), do: {:ok, :satisfiable_axioms_theorem}
  def from_mnemonic("STP"), do: {:ok, :stopped}
  def from_mnemonic("SUC"), do: {:ok, :success}
  def from_mnemonic("SYE"), do: {:ok, :syntax_error}
  def from_mnemonic("Sat"), do: {:ok, :saturation}
  def from_mnemonic("Sln"), do: {:ok, :solution}
  def from_mnemonic("TAC"), do: {:ok, :tautologous_conclusion}
  def from_mnemonic("TAP"), do: {:ok, :tautology_preserving}
  def from_mnemonic("TAU"), do: {:ok, :tautology}
  def from_mnemonic("TCA"), do: {:ok, :tautologous_conclusion_contradictory_axioms}
  def from_mnemonic("TCP"), do: {:ok, :type_check_partial}
  def from_mnemonic("THM"), do: {:ok, :theorem}
  def from_mnemonic("TMO"), do: {:ok, :timeout}
  def from_mnemonic("TSC"), do: {:ok, :type_checked_complete}
  def from_mnemonic("TSU"), do: {:ok, :type_check_success}
  def from_mnemonic("TYE"), do: {:ok, :type_error}
  def from_mnemonic("UCA"), do: {:ok, :unsatisfiable_conclusion_contradictory_axioms}
  def from_mnemonic("UNC"), do: {:ok, :unsatisfiable_conclusion}
  def from_mnemonic("UNK"), do: {:ok, :unknown}
  def from_mnemonic("UNP"), do: {:ok, :unsatisfiability_preserving}
  def from_mnemonic("UNS"), do: {:ok, :unsatisfiable}
  def from_mnemonic("USE"), do: {:ok, :usage_error}
  def from_mnemonic("USM"), do: {:ok, :unsemantic}
  def from_mnemonic("USR"), do: {:ok, :user}
  def from_mnemonic("VSB"), do: {:ok, :verified_bad}
  def from_mnemonic("VSG"), do: {:ok, :verified_good}
  def from_mnemonic("VSU"), do: {:ok, :verify_success}
  def from_mnemonic("Ver"), do: {:ok, :verification}
  def from_mnemonic("WCA"), do: {:ok, :weaker_conclusion_contradictory_axioms}
  def from_mnemonic("WCC"), do: {:ok, :weaker_counter_conclusion}
  def from_mnemonic("WCT"), do: {:ok, :weaker_counter_theorem}
  def from_mnemonic("WEC"), do: {:ok, :weaker_conclusion}
  def from_mnemonic("WTC"), do: {:ok, :weaker_tautologous_conclusion}
  def from_mnemonic("WTH"), do: {:ok, :weaker_theorem}
  def from_mnemonic("WTO"), do: {:ok, :wc_timeout}
  def from_mnemonic("WUC"), do: {:ok, :weaker_unsatisfiable_conclusion}
  def from_mnemonic(word) when is_binary(word), do: :error

  @doc """
  Turn the lower-case mnemonic inside a TPTP `status(...)` annotation into an atom.

  `<inference_status_value>` in the SZS BNF is the success ontology's mnemonic,
  lower-cased, and the test suite checks that all of them are present here.

      iex> Tptp.Szs.Page.from_status_value("thm")
      {:ok, :theorem}
      iex> Tptp.Szs.Page.from_status_value("prf")
      :error
  """
  @spec from_status_value(binary()) :: {:ok, Ontology.t()} | :error
  def from_status_value("suc"), do: {:ok, :success}
  def from_status_value("ssu"), do: {:ok, :semantic_success}
  def from_status_value("unp"), do: {:ok, :unsatisfiability_preserving}
  def from_status_value("sap"), do: {:ok, :satisfiability_preserving}
  def from_status_value("tap"), do: {:ok, :tautology_preserving}
  def from_status_value("esa"), do: {:ok, :equi_satisfiable}
  def from_status_value("eta"), do: {:ok, :equi_tautologous}
  def from_status_value("mex"), do: {:ok, :model_extending}
  def from_status_value("sat"), do: {:ok, :satisfiable}
  def from_status_value("fsa"), do: {:ok, :finitely_satisfiable}
  def from_status_value("fth"), do: {:ok, :finite_theorem}
  def from_status_value("thm"), do: {:ok, :theorem}
  def from_status_value("sth"), do: {:ok, :satisfiable_axioms_theorem}
  def from_status_value("eqv"), do: {:ok, :equivalent}
  def from_status_value("tac"), do: {:ok, :tautologous_conclusion}
  def from_status_value("wec"), do: {:ok, :weaker_conclusion}
  def from_status_value("eth"), do: {:ok, :equivalent_theorem}
  def from_status_value("tau"), do: {:ok, :tautology}
  def from_status_value("wtc"), do: {:ok, :weaker_tautologous_conclusion}
  def from_status_value("wth"), do: {:ok, :weaker_theorem}
  def from_status_value("ftt"), do: {:ok, :finite_tautology}
  def from_status_value("cup"), do: {:ok, :counter_unsatisfiability_preserving}
  def from_status_value("csp"), do: {:ok, :counter_satisfiability_preserving}
  def from_status_value("ctp"), do: {:ok, :counter_tautology_preserving}
  def from_status_value("ecs"), do: {:ok, :equi_counter_satisfiable}
  def from_status_value("eca"), do: {:ok, :equi_counter_tautologous}
  def from_status_value("cmx"), do: {:ok, :counter_model_extending}
  def from_status_value("csa"), do: {:ok, :counter_satisfiable}
  def from_status_value("fcs"), do: {:ok, :finitely_counter_satisfiable}
  def from_status_value("fct"), do: {:ok, :finite_counter_theorem}
  def from_status_value("cth"), do: {:ok, :counter_theorem}
  def from_status_value("sct"), do: {:ok, :satisfiable_axioms_counter_theorem}
  def from_status_value("ceq"), do: {:ok, :counter_equivalent}
  def from_status_value("unc"), do: {:ok, :unsatisfiable_conclusion}
  def from_status_value("wcc"), do: {:ok, :weaker_counter_conclusion}
  def from_status_value("ect"), do: {:ok, :equivalent_counter_theorem}
  def from_status_value("uns"), do: {:ok, :unsatisfiable}
  def from_status_value("wuc"), do: {:ok, :weaker_unsatisfiable_conclusion}
  def from_status_value("wct"), do: {:ok, :weaker_counter_theorem}
  def from_status_value("fun"), do: {:ok, :finitely_unsatisfiable}
  def from_status_value("cax"), do: {:ok, :contradictory_axioms}
  def from_status_value("sca"), do: {:ok, :satisfiable_conclusion_contradictory_axioms}
  def from_status_value("scc"), do: {:ok, :satisfiable_counter_conclusion_contradictory_axioms}
  def from_status_value("tca"), do: {:ok, :tautologous_conclusion_contradictory_axioms}
  def from_status_value("wca"), do: {:ok, :weaker_conclusion_contradictory_axioms}
  def from_status_value("uca"), do: {:ok, :unsatisfiable_conclusion_contradictory_axioms}
  def from_status_value("noc"), do: {:ok, :no_consequence}
  def from_status_value("tsu"), do: {:ok, :type_check_success}
  def from_status_value("tcp"), do: {:ok, :type_check_partial}
  def from_status_value("tsc"), do: {:ok, :type_checked_complete}
  def from_status_value("vsu"), do: {:ok, :verify_success}
  def from_status_value("vsg"), do: {:ok, :verified_good}
  def from_status_value("vsb"), do: {:ok, :verified_bad}
  def from_status_value(word) when is_binary(word), do: :error

  @doc """
  The three-letter mnemonic for a status value.

      iex> Tptp.Szs.Page.mnemonic(:theorem)
      "THM"
  """
  @spec mnemonic(Ontology.t()) :: binary()
  def mnemonic(:success), do: "SUC"
  def mnemonic(:semantic_success), do: "SSU"
  def mnemonic(:unsatisfiability_preserving), do: "UNP"
  def mnemonic(:satisfiability_preserving), do: "SAP"
  def mnemonic(:tautology_preserving), do: "TAP"
  def mnemonic(:equi_satisfiable), do: "ESA"
  def mnemonic(:equi_tautologous), do: "ETA"
  def mnemonic(:model_extending), do: "MEX"
  def mnemonic(:satisfiable), do: "SAT"
  def mnemonic(:finitely_satisfiable), do: "FSA"
  def mnemonic(:finite_theorem), do: "FTH"
  def mnemonic(:theorem), do: "THM"
  def mnemonic(:satisfiable_axioms_theorem), do: "STH"
  def mnemonic(:equivalent), do: "EQV"
  def mnemonic(:tautologous_conclusion), do: "TAC"
  def mnemonic(:weaker_conclusion), do: "WEC"
  def mnemonic(:equivalent_theorem), do: "ETH"
  def mnemonic(:tautology), do: "TAU"
  def mnemonic(:weaker_tautologous_conclusion), do: "WTC"
  def mnemonic(:weaker_theorem), do: "WTH"
  def mnemonic(:finite_tautology), do: "FTT"
  def mnemonic(:counter_unsatisfiability_preserving), do: "CUP"
  def mnemonic(:counter_satisfiability_preserving), do: "CSP"
  def mnemonic(:counter_tautology_preserving), do: "CTP"
  def mnemonic(:equi_counter_satisfiable), do: "ECS"
  def mnemonic(:equi_counter_tautologous), do: "ECA"
  def mnemonic(:counter_model_extending), do: "CMX"
  def mnemonic(:counter_satisfiable), do: "CSA"
  def mnemonic(:finitely_counter_satisfiable), do: "FCS"
  def mnemonic(:finite_counter_theorem), do: "FCT"
  def mnemonic(:counter_theorem), do: "CTH"
  def mnemonic(:satisfiable_axioms_counter_theorem), do: "SCT"
  def mnemonic(:counter_equivalent), do: "CEQ"
  def mnemonic(:unsatisfiable_conclusion), do: "UNC"
  def mnemonic(:weaker_counter_conclusion), do: "WCC"
  def mnemonic(:equivalent_counter_theorem), do: "ECT"
  def mnemonic(:unsatisfiable), do: "UNS"
  def mnemonic(:weaker_unsatisfiable_conclusion), do: "WUC"
  def mnemonic(:weaker_counter_theorem), do: "WCT"
  def mnemonic(:finitely_unsatisfiable), do: "FUN"
  def mnemonic(:contradictory_axioms), do: "CAX"
  def mnemonic(:satisfiable_conclusion_contradictory_axioms), do: "SCA"
  def mnemonic(:satisfiable_counter_conclusion_contradictory_axioms), do: "SCC"
  def mnemonic(:tautologous_conclusion_contradictory_axioms), do: "TCA"
  def mnemonic(:weaker_conclusion_contradictory_axioms), do: "WCA"
  def mnemonic(:unsatisfiable_conclusion_contradictory_axioms), do: "UCA"
  def mnemonic(:no_consequence), do: "NOC"
  def mnemonic(:type_check_success), do: "TSU"
  def mnemonic(:type_check_partial), do: "TCP"
  def mnemonic(:type_checked_complete), do: "TSC"
  def mnemonic(:verify_success), do: "VSU"
  def mnemonic(:verified_good), do: "VSG"
  def mnemonic(:verified_bad), do: "VSB"
  def mnemonic(:no_success), do: "NOS"
  def mnemonic(:unknown), do: "UNK"
  def mnemonic(:stopped), do: "STP"
  def mnemonic(:in_progress), do: "INP"
  def mnemonic(:not_tried), do: "NTT"
  def mnemonic(:not_tried_yet), do: "NTY"
  def mnemonic(:error), do: "ERR"
  def mnemonic(:forced), do: "FOR"
  def mnemonic(:gave_up), do: "GUP"
  def mnemonic(:os_error), do: "OSE"
  def mnemonic(:input_error), do: "INE"
  def mnemonic(:syntax_error), do: "SYE"
  def mnemonic(:semantic_error), do: "SEE"
  def mnemonic(:type_error), do: "TYE"
  def mnemonic(:unsemantic), do: "USM"
  def mnemonic(:usage_error), do: "USE"
  def mnemonic(:user), do: "USR"
  def mnemonic(:resource_out), do: "RSO"
  def mnemonic(:timeout), do: "TMO"
  def mnemonic(:cpu_timeout), do: "CTO"
  def mnemonic(:wc_timeout), do: "WTO"
  def mnemonic(:memory_out), do: "MMO"
  def mnemonic(:incomplete), do: "INC"
  def mnemonic(:inappropriate), do: "IAP"
  def mnemonic(:incorrect), do: "ICT"
  def mnemonic(:assumed), do: "ASS"
  def mnemonic(:open), do: "OPN"
  def mnemonic(:not_verified), do: "NVE"
  def mnemonic(:failed_verified), do: "FVE"
  def mnemonic(:data), do: "Dat"
  def mnemonic(:logical_data), do: "LDa"
  def mnemonic(:solution), do: "Sln"
  def mnemonic(:proof), do: "Prf"
  def mnemonic(:interpretation), do: "Int"
  def mnemonic(:list_of_formulae), do: "Lof"
  def mnemonic(:derivation), do: "Der"
  def mnemonic(:refutation), do: "Ref"
  def mnemonic(:cnf_refutation), do: "CRf"
  def mnemonic(:model), do: "Mod"
  def mnemonic(:domain_interpretation), do: "DIn"
  def mnemonic(:domain_model), do: "DMo"
  def mnemonic(:finite_interpretation), do: "FIn"
  def mnemonic(:finite_model), do: "FMo"
  def mnemonic(:infinite_interpretation), do: "IIn"
  def mnemonic(:infinite_model), do: "IMo"
  def mnemonic(:herbrand_interpretation), do: "HIn"
  def mnemonic(:herbrand_model), do: "HMo"
  def mnemonic(:formula_herbrand_interpretation), do: "FHi"
  def mnemonic(:formula_herbrand_model), do: "FHm"
  def mnemonic(:saturation), do: "Sat"
  def mnemonic(:not_a_solution), do: "NSo"
  def mnemonic(:assurance), do: "Ass"
  def mnemonic(:incomplete_proof), do: "IPr"
  def mnemonic(:incomplete_interpretation), do: "IIn"
  def mnemonic(:non_logical_data), do: "NLd"
  def mnemonic(:comment), do: "Com"
  def mnemonic(:free_text), do: "FTx"
  def mnemonic(:verification), do: "Ver"
  def mnemonic(:none), do: "Non"

  @doc """
  What the page says a status value means, in its own words.

      iex> Tptp.Szs.Page.describe(:theorem)
      "All models of Ax are models of C."
  """
  @spec describe(Ontology.t()) :: binary()
  def describe(:success), do: "The logical data has been processed successfully."
  def describe(:semantic_success), do: "The logical data has been reasoned about successfully."

  def describe(:unsatisfiability_preserving),
    do:
      "If there does not exist a model of Ax then there does not exist a model of C, i.e., if Ax is unsatisfiable then C is unsatisfiable."

  def describe(:satisfiability_preserving),
    do:
      "If there exists a model of Ax then there exists a model of C, i.e., if Ax is satisfiable then C is satisfiable."

  def describe(:tautology_preserving),
    do:
      "If every interpretation is a model of Ax then every interpretation is a model of C, i.e., if Ax is a tautology then C is a tautology."

  def describe(:equi_satisfiable),
    do:
      "There exists a model of Ax iff there exists a model of C, i.e., Ax is (un)satisfiable iff C is (un)satisfiable."

  def describe(:equi_tautologous),
    do:
      "Every interpretation is a model of Ax iff every interpretation is a model of C, i.e., Ax is a tautology iff C is a tautology."

  def describe(:model_extending),
    do:
      "Some interpretations are models of Ax, and some interpretations are models of C, and all models of C are conservative extensions of models of Ax (which also means that all models of C are models of Ax)."

  def describe(:satisfiable),
    do: "Some interpretations are models of Ax, and some models of Ax are models of C."

  def describe(:finitely_satisfiable),
    do:
      "Some finite interpretations are finite models of Ax, and some finite models of Ax are finite models of C."

  def describe(:finite_theorem), do: "All finite models of Ax are finite models of C."
  def describe(:theorem), do: "All models of Ax are models of C."

  def describe(:satisfiable_axioms_theorem),
    do: "Some interpretations are models of Ax, and all models of Ax are models of C."

  def describe(:equivalent),
    do: "All models of Ax are models of C, and all models of C are models of Ax."

  def describe(:tautologous_conclusion),
    do: "Some interpretations are models of Ax, and all interpretations are models of C."

  def describe(:weaker_conclusion),
    do:
      "Some interpretations are models of Ax, all models of Ax are models of C, and some models of C are not models of Ax."

  def describe(:equivalent_theorem),
    do:
      "Some, but not all, interpretations are models of Ax, all models of Ax are models of C, and all models of C are models of Ax."

  def describe(:tautology),
    do: "All interpretations are models of Ax, and all interpretations are models of C."

  def describe(:weaker_tautologous_conclusion),
    do:
      "Some, but not all, interpretations are models of Ax, and all interpretations are models of C."

  def describe(:weaker_theorem),
    do:
      "Some interpretations are models of Ax, all models of Ax are models of C, some models of C are not models of Ax, and some interpretations are not models of C."

  def describe(:finite_tautology),
    do:
      "All finite interpretations are models of Ax, and all finite interpretations are models of C."

  def describe(:counter_unsatisfiability_preserving),
    do:
      "If there does not exist a model of Ax then there does not exist a model of ~C, i.e., if Ax is unsatisfiable then ~C is unsatisfiable."

  def describe(:counter_satisfiability_preserving),
    do:
      "If there exists a model of Ax then there exists a model of ~C, i.e., if Ax is satisfiable then ~C is satisfiable."

  def describe(:counter_tautology_preserving),
    do:
      "If every interpretation is a model of Ax then every interpretations is a model of ~C, i.e., if Ax is a tautology then ~C is a tautology."

  def describe(:equi_counter_satisfiable),
    do:
      "There exists a model of Ax iff there exists a model of ~C, i.e., Ax is (un)satisfiable iff ~C is (un)satisfiable."

  def describe(:equi_counter_tautologous),
    do:
      "Every interpretation is a model of Ax iff every interpretation is a model of ~C, i.e., Ax a tautology iff ~C is a tautology."

  def describe(:counter_model_extending),
    do:
      "Some interpretations are models of Ax, and some interpretations are models of ~C, and all models of ~C are conservative extensions of models of Ax (which also means that all models of ~C are models of Ax)."

  def describe(:counter_satisfiable),
    do: "Some interpretations are models of Ax, and some models of Ax are models of ~C."

  def describe(:finitely_counter_satisfiable),
    do:
      "Some finite interpretations are finite models of Ax, and some finite models of Ax are finite models of ~C."

  def describe(:finite_counter_theorem), do: "All finite models of Ax are finite models of ~C."
  def describe(:counter_theorem), do: "All models of Ax are models of ~C."

  def describe(:satisfiable_axioms_counter_theorem),
    do: "Some interpretations are models of Ax, and all models of Ax are models of ~C."

  def describe(:counter_equivalent),
    do:
      "Some interpretations are models of Ax, all models of Ax are models of ~C, and all models of ~C are models of Ax, i.e., all interpretations are models of Ax xor of C."

  def describe(:unsatisfiable_conclusion),
    do:
      "Some interpretations are models of Ax, and all interpretations are models of ~C, i.e., no interpretations are models of C."

  def describe(:weaker_counter_conclusion),
    do:
      "Some interpretations are models of Ax, and all models of Ax are models of ~C, and some models of ~C are not models of Ax."

  def describe(:equivalent_counter_theorem),
    do:
      "Some, but not all, interpretations are models of Ax, all models of Ax are models of ~C, and all models of ~C are models of Ax."

  def describe(:unsatisfiable),
    do:
      "All interpretations are models of Ax, and all interpretations are models of ~C, i.e., no interpretations are models of C."

  def describe(:weaker_unsatisfiable_conclusion),
    do:
      "Some, but not all, interpretations are models of Ax, and all interpretations are models of ~C."

  def describe(:weaker_counter_theorem),
    do:
      "Some interpretations are models of Ax, all models of Ax are models of ~C, some models of ~C are not models of Ax, and some interpretations are not models of ~C."

  def describe(:finitely_unsatisfiable),
    do:
      "Some finite interpretations are finite models of Ax, and all finite models of Ax are finite models of ~C, i.e., no finite models of Ax are finite models of C."

  def describe(:contradictory_axioms), do: "No interpretations are models of Ax."

  def describe(:satisfiable_conclusion_contradictory_axioms),
    do: "No interpretations are models of Ax, and some interpretations are models of C."

  def describe(:satisfiable_counter_conclusion_contradictory_axioms),
    do: "No interpretations are models of Ax, and some interpretations are models of ~C."

  def describe(:tautologous_conclusion_contradictory_axioms),
    do: "No interpretations are models of Ax, and all interpretations are models of C."

  def describe(:weaker_conclusion_contradictory_axioms),
    do:
      "No interpretations are models of Ax, and some, but not all, interpretations are models of C."

  def describe(:unsatisfiable_conclusion_contradictory_axioms),
    do:
      "No interpretations are models of Ax, and all interpretations are models of ~C, i.e., no interpretations are models of C."

  def describe(:no_consequence),
    do:
      "Some interpretations are models of Ax, some models of Ax are models of C, and some models of Ax are models of ~C."

  def describe(:type_check_success), do: "The logical data has been typed checked successfully."

  def describe(:type_check_partial),
    do:
      "Everything passed type checking, but some of the checking was partial, i.e., some things that passed might not be type correct."

  def describe(:type_checked_complete), do: "Everything passed type checking."
  def describe(:verify_success), do: "The logical solution has been verified successfully."
  def describe(:verified_good), do: "The solution has been verified as good."
  def describe(:verified_bad), do: "The solution has been verified as bad."
  def describe(:no_success), do: "The logical data has not been processed successfully (yet)."
  def describe(:unknown), do: "A success value for the ATP problem has never been established."

  def describe(:stopped),
    do: "Software attempted to process the data, and stopped without a success status."

  def describe(:in_progress), do: "Software is still running."
  def describe(:not_tried), do: "Software has not tried to process the data."

  def describe(:not_tried_yet),
    do: "Software has not tried to process the data yet, but might in the future."

  def describe(:error), do: "Software stopped due to an error."
  def describe(:forced), do: "Software was forced to stop by an external force."
  def describe(:gave_up), do: "Software gave up of its own accord."
  def describe(:os_error), do: "Software stopped due to an operating system error."
  def describe(:input_error), do: "Software stopped due to an input error."
  def describe(:syntax_error), do: "Software stopped due to an input syntax error."
  def describe(:semantic_error), do: "Software stopped due to an input semantic error."

  def describe(:type_error),
    do: "Software stopped due to an input type error (for typed logical data)."

  def describe(:unsemantic), do: "The semantics makes no sense (for semantics specifications)."
  def describe(:usage_error), do: "Software stopped due to an ATP system usage error."
  def describe(:user), do: "Software was forced to stop by the user."
  def describe(:resource_out), do: "Software stopped because some resource ran out."
  def describe(:timeout), do: "Software stopped because a time limit ran out."
  def describe(:cpu_timeout), do: "Software stopped because the CPU time limit ran out."
  def describe(:wc_timeout), do: "Software stopped because the wall clock time limit ran out."
  def describe(:memory_out), do: "Software stopped because the memory limit ran out."
  def describe(:incomplete), do: "Software gave up because it's incomplete."

  def describe(:inappropriate),
    do: "Software gave up because it cannot process this type of data."

  def describe(:incorrect), do: "Software gave an incorrect answer."

  def describe(:assumed),
    do:
      "The success ontology value S has been assumed because the actual value is unknown for the no-success ontology reason U. U is taken from the subontology starting at Unknown in the no-success ontology."

  def describe(:open), do: "A success value for the abstract problem has never been established."
  def describe(:not_verified), do: "The solution output has not been verified."
  def describe(:failed_verified), do: "The solution output failed verification."
  def describe(:data), do: "Data output."
  def describe(:logical_data), do: "Logical data."
  def describe(:solution), do: "A solution."
  def describe(:proof), do: "A proof."
  def describe(:interpretation), do: "An interpretation."
  def describe(:list_of_formulae), do: "A list of formulae."
  def describe(:derivation), do: "A derivation (inference steps, possibly ending in the theorem)."
  def describe(:refutation), do: "A refutation (starting with Ax U ~C and ending in FALSE)."

  def describe(:cnf_refutation),
    do:
      "A refutation in clause normal form, including, for FOF Ax or C, the translation from FOF to CNF (without the FOF to CNF translation it's an IncompleteProof)."

  def describe(:model), do: "A model."

  def describe(:domain_interpretation),
    do: "An interpretation whose domain is not the Herbrand universe."

  def describe(:domain_model), do: "A model whose domain is not the Herbrand universe."
  def describe(:finite_interpretation), do: "A DomainInterpretation with a finite domain."
  def describe(:finite_model), do: "A DomainModel with a finite domain."
  def describe(:infinite_interpretation), do: "A DomainInterpretation with an infinite domain."
  def describe(:infinite_model), do: "A DomainInterpretation with an infinite domain."
  def describe(:herbrand_interpretation), do: "A Herbrand interpretation."
  def describe(:herbrand_model), do: "A Herbrand model."

  def describe(:formula_herbrand_interpretation),
    do: "A Herbrand interpretation defined by a set of formulae."

  def describe(:formula_herbrand_model), do: "A Herbrand model defined by a set of formulae."
  def describe(:saturation), do: "A Herbrand model expressed as a saturated set of formulae."
  def describe(:not_a_solution), do: "Something that is not a well formed solution."
  def describe(:assurance), do: "Only an assurance of the success ontology value."
  def describe(:incomplete_proof), do: "A proof with some part missing."
  def describe(:incomplete_interpretation), do: "An interpretation with some part missing."
  def describe(:non_logical_data), do: "Non-logical output."
  def describe(:comment), do: "TPTP format comments (starting with %)."
  def describe(:free_text), do: "Anything you want."
  def describe(:verification), do: "Free format output from a solution verifier."
  def describe(:none), do: "Nothing."
end
