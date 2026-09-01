defmodule Tptp.Szs.Ontology do
  @moduledoc """
  The SZS status values, generated from the vendored ontology page.

  Do not edit: `mix tptp.gen` writes this from `priv/szs/SZSOntology-2026-08-31.html`,
  fetched from <https://tptp.org/UserDocs/SZSOntology>. 112 values in three ontologies:

    * `:success` — 53 values
    * `:no_success` — 29 values
    * `:data` — 30 values

  Every atom here is created at compile time, so `from_string/1` and its siblings
  can turn untrusted prover output into an atom without `String.to_atom/1` being
  reachable from input. That is a security property of this library, not a style
  preference; see `Tptp.Token` for the same discipline and the Credo check that
  enforces it.

  ## The `isa` hierarchy is deliberately absent

  There is no `parent/1` or `descendant?/2`. The SZS ontologies are hierarchies —
  an `EquivalentTheorem` isa `Equivalent` isa `Satisfiable` — but that hierarchy is
  published only as three diagrams (`Success.png`, `NoSuccess.png`, `Data.png` at
  the URL above) and appears nowhere in the page's text. Copying a dense diagram
  out by eye would put unverifiable relations into a library whose contract is
  faithfulness to what the sources actually say, so what is here is the partition
  the text does state: which ontology a value belongs to, and which subontology of
  `Success`. If a machine-readable ontology is published, this module gains the
  hierarchy in one regeneration.

  ## What to do when there is no ordering

  There is no `compare/2` and no precedence table, for the same reason there is
  no `parent/1`: the page publishes none. A consumer reading prover output still
  has to choose between two answers, though, and a consumer that invents its own
  ranking is how a precedence inversion gets written — a `Timeout` from the
  system that ran longest quietly outranking a `Theorem`. Two things published
  here are enough for that choice, and are what a consumer should use instead:

    * **`success?/1`.** A `Success` value is an answer; a `NoSuccess` value is
      the absence of one. Prefer `Success`. That is the whole of the ordering the
      text supports, and it is the one that matters — nothing in `NoSuccess` is
      ever a better answer than anything in `Success`.
    * **`subontology/1`.** Within `Success`, this says which group of the page a
      value sits in, so two answers can be told apart as the same kind of claim
      or different kinds without any guess about which is stronger.

  One further rule is about provenance rather than about the ontology, and it
  belongs in the same decision: an explicit `% SZS status` line is the system
  saying what it concluded, while a prover-specific output pattern is a reader
  inferring it. Prefer the line. `Tptp.Szs.status/1` returns `:none` when a run
  printed none, which is the signal to fall back to a pattern — and the only
  time to.

  ## Case is meaningful

  `SAT` is `Satisfiable`; `Sat` is `Saturation`. `from_mnemonic/1` is case
  sensitive for that reason. The lower-case three-letter form that appears inside
  a TPTP `status(...)` annotation has its own entry point, `from_status_value/1`,
  which searches only the success ontology — the only place `<status_value>` draws
  from, as the generator checks on every run.

  `Ass` and `ASS` are a second pair, and a sharper one: `Ass` is `Assurance` in
  the data ontology, `ASS` is `Assumed` in the no-success ontology.

  ## `Assumed` carries arguments this module does not model

  The page writes every mnemonic as three letters except one. `Assumed` is
  `ASS(U,S)`: the success value `S` was assumed because the real answer is
  unknown for the no-success reason `U`, with `U` drawn from the subontology
  under `Unknown`. `mnemonic(:assumed)` is `"ASS"` and `from_mnemonic/1` answers
  to `"ASS"` alone, because a pair of arguments is not a member of a closed set of
  atoms and pretending otherwise would put a parser in a lookup table.

  A consumer reading a status line has to do the splitting itself: take the text
  up to the first `(`, look that up here, and read the arguments — themselves two
  mnemonics — with a second and third call. Nothing on the page says how the form
  is written in a `% SZS status` line, and the TPTP BNF cannot express it at all:
  `<status_value>` is a list of plain words, so `status(ass(...))` has no
  derivation. Treat `ASS(...)` as a form to recognise rather than one to emit.
  """

  @typedoc "One SZS status value. A closed set of 112 compile-time atoms."
  @type t ::
          :success
          | :semantic_success
          | :unsatisfiability_preserving
          | :satisfiability_preserving
          | :tautology_preserving
          | :equi_satisfiable
          | :equi_tautologous
          | :model_extending
          | :satisfiable
          | :finitely_satisfiable
          | :finite_theorem
          | :theorem
          | :satisfiable_axioms_theorem
          | :equivalent
          | :tautologous_conclusion
          | :weaker_conclusion
          | :equivalent_theorem
          | :tautology
          | :weaker_tautologous_conclusion
          | :weaker_theorem
          | :finite_tautology
          | :counter_unsatisfiability_preserving
          | :counter_satisfiability_preserving
          | :counter_tautologyy_preserving
          | :equi_counter_satisfiable
          | :equi_counter_tautologous
          | :counter_model_extending
          | :counter_satisfiable
          | :finitely_counter_satisfiable
          | :finite_counter_theorem
          | :counter_theorem
          | :satisfiable_axioms_counter_theorem
          | :counter_equivalent
          | :unsatisfiable_conclusion
          | :weaker_counter_conclusion
          | :equivalent_counter_theorem
          | :unsatisfiable
          | :weaker_unsatisfiable_conclusion
          | :weaker_counter_theorem
          | :finitely_unsatisfiable
          | :contradictory_axioms
          | :satisfiable_conclusion_contradictory_axioms
          | :satisfiable_counter_conclusion_contradictory_axioms
          | :tautologous_conclusion_contradictory_axioms
          | :weaker_conclusion_contradictory_axioms
          | :unsatisfiable_conclusion_contradictory_axioms
          | :no_consequence
          | :type_check_success
          | :type_check_partial
          | :type_checked_complete
          | :verify_success
          | :verified_good
          | :verified_bad
          | :no_success
          | :unknown
          | :stopped
          | :in_progress
          | :not_tried
          | :not_tried_yet
          | :error
          | :forced
          | :gave_up
          | :os_error
          | :input_error
          | :syntax_error
          | :semantic_error
          | :type_error
          | :unsemantic
          | :usage_error
          | :user
          | :resource_out
          | :timeout
          | :cpu_timeout
          | :wc_timeout
          | :memory_out
          | :incomplete
          | :inappropriate
          | :incorrect
          | :assumed
          | :open
          | :not_verified
          | :failed_verified
          | :data
          | :logical_data
          | :solution
          | :proof
          | :interpretation
          | :list_of_formulae
          | :derivation
          | :refutation
          | :cnf_refutation
          | :model
          | :domain_interpretation
          | :domain_model
          | :finite_interpretation
          | :finite_model
          | :infinite_interpretation
          | :infinite_model
          | :herbrand_interpretation
          | :herbrand_model
          | :formula_herbrand_interpretation
          | :formula_herbrand_model
          | :saturation
          | :not_a_solution
          | :assurance
          | :incomplete_proof
          | :incomplete_interpretation
          | :non_logical_data
          | :comment
          | :free_text
          | :verification
          | :none

  @typedoc "Which of the three SZS ontologies a value belongs to."
  @type ontology :: :success | :no_success | :data

  @typedoc """
  The top-level grouping a value sits under.

  Only `Success` has subontologies; the other two sections of the page are flat,
  so their values report the section itself.
  """
  @type subontology ::
          :success
          | :semantic_success
          | :type_check_success
          | :verify_success
          | :no_success
          | :data

  @doc "Every status value, in the order the page lists them."
  @spec values() :: [t()]
  def values,
    do: [
      :success,
      :semantic_success,
      :unsatisfiability_preserving,
      :satisfiability_preserving,
      :tautology_preserving,
      :equi_satisfiable,
      :equi_tautologous,
      :model_extending,
      :satisfiable,
      :finitely_satisfiable,
      :finite_theorem,
      :theorem,
      :satisfiable_axioms_theorem,
      :equivalent,
      :tautologous_conclusion,
      :weaker_conclusion,
      :equivalent_theorem,
      :tautology,
      :weaker_tautologous_conclusion,
      :weaker_theorem,
      :finite_tautology,
      :counter_unsatisfiability_preserving,
      :counter_satisfiability_preserving,
      :counter_tautologyy_preserving,
      :equi_counter_satisfiable,
      :equi_counter_tautologous,
      :counter_model_extending,
      :counter_satisfiable,
      :finitely_counter_satisfiable,
      :finite_counter_theorem,
      :counter_theorem,
      :satisfiable_axioms_counter_theorem,
      :counter_equivalent,
      :unsatisfiable_conclusion,
      :weaker_counter_conclusion,
      :equivalent_counter_theorem,
      :unsatisfiable,
      :weaker_unsatisfiable_conclusion,
      :weaker_counter_theorem,
      :finitely_unsatisfiable,
      :contradictory_axioms,
      :satisfiable_conclusion_contradictory_axioms,
      :satisfiable_counter_conclusion_contradictory_axioms,
      :tautologous_conclusion_contradictory_axioms,
      :weaker_conclusion_contradictory_axioms,
      :unsatisfiable_conclusion_contradictory_axioms,
      :no_consequence,
      :type_check_success,
      :type_check_partial,
      :type_checked_complete,
      :verify_success,
      :verified_good,
      :verified_bad,
      :no_success,
      :unknown,
      :stopped,
      :in_progress,
      :not_tried,
      :not_tried_yet,
      :error,
      :forced,
      :gave_up,
      :os_error,
      :input_error,
      :syntax_error,
      :semantic_error,
      :type_error,
      :unsemantic,
      :usage_error,
      :user,
      :resource_out,
      :timeout,
      :cpu_timeout,
      :wc_timeout,
      :memory_out,
      :incomplete,
      :inappropriate,
      :incorrect,
      :assumed,
      :open,
      :not_verified,
      :failed_verified,
      :data,
      :logical_data,
      :solution,
      :proof,
      :interpretation,
      :list_of_formulae,
      :derivation,
      :refutation,
      :cnf_refutation,
      :model,
      :domain_interpretation,
      :domain_model,
      :finite_interpretation,
      :finite_model,
      :infinite_interpretation,
      :infinite_model,
      :herbrand_interpretation,
      :herbrand_model,
      :formula_herbrand_interpretation,
      :formula_herbrand_model,
      :saturation,
      :not_a_solution,
      :assurance,
      :incomplete_proof,
      :incomplete_interpretation,
      :non_logical_data,
      :comment,
      :free_text,
      :verification,
      :none
    ]

  @doc "How many status values there are."
  @spec count() :: pos_integer()
  def count, do: 112

  @doc "Where the ontology was fetched from."
  @spec source() :: binary()
  def source, do: "https://tptp.org/UserDocs/SZSOntology"

  @doc "The vendored copy this module was generated from."
  @spec vendored() :: binary()
  def vendored, do: "SZSOntology-2026-08-31.html"

  @doc """
  A SHA-256 of the vendored page, for consumers that cache across regenerations.

  The page carries no version number, so this stands in for one.
  """
  @spec digest() :: binary()
  def digest, do: "22b1f4f9294331e062a630fc589bef8fd43422f3d3b9c6ac4ce11b3fe949f359"

  @doc """
  Turn a `OneWord` status value into an atom, without creating one.

      iex> Tptp.Szs.Ontology.from_string("Theorem")
      {:ok, :theorem}
      iex> Tptp.Szs.Ontology.from_string("NotAStatus")
      :error
  """
  @spec from_string(binary()) :: {:ok, t()} | :error
  def from_string("Success"), do: {:ok, :success}
  def from_string("SemanticSuccess"), do: {:ok, :semantic_success}
  def from_string("UnsatisfiabilityPreserving"), do: {:ok, :unsatisfiability_preserving}
  def from_string("SatisfiabilityPreserving"), do: {:ok, :satisfiability_preserving}
  def from_string("TautologyPreserving"), do: {:ok, :tautology_preserving}
  def from_string("EquiSatisfiable"), do: {:ok, :equi_satisfiable}
  def from_string("EquiTautologous"), do: {:ok, :equi_tautologous}
  def from_string("ModelExtending"), do: {:ok, :model_extending}
  def from_string("Satisfiable"), do: {:ok, :satisfiable}
  def from_string("FinitelySatisfiable"), do: {:ok, :finitely_satisfiable}
  def from_string("FiniteTheorem"), do: {:ok, :finite_theorem}
  def from_string("Theorem"), do: {:ok, :theorem}
  def from_string("SatisfiableAxiomsTheorem"), do: {:ok, :satisfiable_axioms_theorem}
  def from_string("Equivalent"), do: {:ok, :equivalent}
  def from_string("TautologousConclusion"), do: {:ok, :tautologous_conclusion}
  def from_string("WeakerConclusion"), do: {:ok, :weaker_conclusion}
  def from_string("EquivalentTheorem"), do: {:ok, :equivalent_theorem}
  def from_string("Tautology"), do: {:ok, :tautology}
  def from_string("WeakerTautologousConclusion"), do: {:ok, :weaker_tautologous_conclusion}
  def from_string("WeakerTheorem"), do: {:ok, :weaker_theorem}
  def from_string("FiniteTautology"), do: {:ok, :finite_tautology}

  def from_string("CounterUnsatisfiabilityPreserving"),
    do: {:ok, :counter_unsatisfiability_preserving}

  def from_string("CounterSatisfiabilityPreserving"),
    do: {:ok, :counter_satisfiability_preserving}

  def from_string("CounterTautologyyPreserving"), do: {:ok, :counter_tautologyy_preserving}
  def from_string("EquiCounterSatisfiable"), do: {:ok, :equi_counter_satisfiable}
  def from_string("EquiCounterTautologous"), do: {:ok, :equi_counter_tautologous}
  def from_string("CounterModelExtending"), do: {:ok, :counter_model_extending}
  def from_string("CounterSatisfiable"), do: {:ok, :counter_satisfiable}
  def from_string("FinitelyCounterSatisfiable"), do: {:ok, :finitely_counter_satisfiable}
  def from_string("FiniteCounterTheorem"), do: {:ok, :finite_counter_theorem}
  def from_string("CounterTheorem"), do: {:ok, :counter_theorem}

  def from_string("SatisfiableAxiomsCounterTheorem"),
    do: {:ok, :satisfiable_axioms_counter_theorem}

  def from_string("CounterEquivalent"), do: {:ok, :counter_equivalent}
  def from_string("UnsatisfiableConclusion"), do: {:ok, :unsatisfiable_conclusion}
  def from_string("WeakerCounterConclusion"), do: {:ok, :weaker_counter_conclusion}
  def from_string("EquivalentCounterTheorem"), do: {:ok, :equivalent_counter_theorem}
  def from_string("Unsatisfiable"), do: {:ok, :unsatisfiable}
  def from_string("WeakerUnsatisfiableConclusion"), do: {:ok, :weaker_unsatisfiable_conclusion}
  def from_string("WeakerCounterTheorem"), do: {:ok, :weaker_counter_theorem}
  def from_string("FinitelyUnsatisfiable"), do: {:ok, :finitely_unsatisfiable}
  def from_string("ContradictoryAxioms"), do: {:ok, :contradictory_axioms}

  def from_string("SatisfiableConclusionContradictoryAxioms"),
    do: {:ok, :satisfiable_conclusion_contradictory_axioms}

  def from_string("SatisfiableCounterConclusionContradictoryAxioms"),
    do: {:ok, :satisfiable_counter_conclusion_contradictory_axioms}

  def from_string("TautologousConclusionContradictoryAxioms"),
    do: {:ok, :tautologous_conclusion_contradictory_axioms}

  def from_string("WeakerConclusionContradictoryAxioms"),
    do: {:ok, :weaker_conclusion_contradictory_axioms}

  def from_string("UnsatisfiableConclusionContradictoryAxioms"),
    do: {:ok, :unsatisfiable_conclusion_contradictory_axioms}

  def from_string("NoConsequence"), do: {:ok, :no_consequence}
  def from_string("TypeCheckSuccess"), do: {:ok, :type_check_success}
  def from_string("TypeCheckPartial"), do: {:ok, :type_check_partial}
  def from_string("TypeCheckedComplete"), do: {:ok, :type_checked_complete}
  def from_string("VerifySuccess"), do: {:ok, :verify_success}
  def from_string("VerifiedGood"), do: {:ok, :verified_good}
  def from_string("VerifiedBad"), do: {:ok, :verified_bad}
  def from_string("NoSuccess"), do: {:ok, :no_success}
  def from_string("Unknown"), do: {:ok, :unknown}
  def from_string("Stopped"), do: {:ok, :stopped}
  def from_string("InProgress"), do: {:ok, :in_progress}
  def from_string("NotTried"), do: {:ok, :not_tried}
  def from_string("NotTriedYet"), do: {:ok, :not_tried_yet}
  def from_string("Error"), do: {:ok, :error}
  def from_string("Forced"), do: {:ok, :forced}
  def from_string("GaveUp"), do: {:ok, :gave_up}
  def from_string("OSError"), do: {:ok, :os_error}
  def from_string("InputError"), do: {:ok, :input_error}
  def from_string("SyntaxError"), do: {:ok, :syntax_error}
  def from_string("SemanticError"), do: {:ok, :semantic_error}
  def from_string("TypeError"), do: {:ok, :type_error}
  def from_string("Unsemantic"), do: {:ok, :unsemantic}
  def from_string("UsageError"), do: {:ok, :usage_error}
  def from_string("User"), do: {:ok, :user}
  def from_string("ResourceOut"), do: {:ok, :resource_out}
  def from_string("Timeout"), do: {:ok, :timeout}
  def from_string("CPUTimeout"), do: {:ok, :cpu_timeout}
  def from_string("WCTimeout"), do: {:ok, :wc_timeout}
  def from_string("MemoryOut"), do: {:ok, :memory_out}
  def from_string("Incomplete"), do: {:ok, :incomplete}
  def from_string("Inappropriate"), do: {:ok, :inappropriate}
  def from_string("Incorrect"), do: {:ok, :incorrect}
  def from_string("Assumed"), do: {:ok, :assumed}
  def from_string("Open"), do: {:ok, :open}
  def from_string("NotVerified"), do: {:ok, :not_verified}
  def from_string("FailedVerified"), do: {:ok, :failed_verified}
  def from_string("Data"), do: {:ok, :data}
  def from_string("LogicalData"), do: {:ok, :logical_data}
  def from_string("Solution"), do: {:ok, :solution}
  def from_string("Proof"), do: {:ok, :proof}
  def from_string("Interpretation"), do: {:ok, :interpretation}
  def from_string("ListOfFormulae"), do: {:ok, :list_of_formulae}
  def from_string("Derivation"), do: {:ok, :derivation}
  def from_string("Refutation"), do: {:ok, :refutation}
  def from_string("CNFRefutation"), do: {:ok, :cnf_refutation}
  def from_string("Model"), do: {:ok, :model}
  def from_string("DomainInterpretation"), do: {:ok, :domain_interpretation}
  def from_string("DomainModel"), do: {:ok, :domain_model}
  def from_string("FiniteInterpretation"), do: {:ok, :finite_interpretation}
  def from_string("FiniteModel"), do: {:ok, :finite_model}
  def from_string("InfiniteInterpretation"), do: {:ok, :infinite_interpretation}
  def from_string("InfiniteModel"), do: {:ok, :infinite_model}
  def from_string("HerbrandInterpretation"), do: {:ok, :herbrand_interpretation}
  def from_string("HerbrandModel"), do: {:ok, :herbrand_model}
  def from_string("FormulaHerbrandInterpretation"), do: {:ok, :formula_herbrand_interpretation}
  def from_string("FormulaHerbrandModel"), do: {:ok, :formula_herbrand_model}
  def from_string("Saturation"), do: {:ok, :saturation}
  def from_string("NotASolution"), do: {:ok, :not_a_solution}
  def from_string("Assurance"), do: {:ok, :assurance}
  def from_string("IncompleteProof"), do: {:ok, :incomplete_proof}
  def from_string("IncompleteInterpretation"), do: {:ok, :incomplete_interpretation}
  def from_string("NonLogicalData"), do: {:ok, :non_logical_data}
  def from_string("Comment"), do: {:ok, :comment}
  def from_string("FreeText"), do: {:ok, :free_text}
  def from_string("Verification"), do: {:ok, :verification}
  def from_string("None"), do: {:ok, :none}
  def from_string(word) when is_binary(word), do: :error

  @doc """
  The `OneWord` spelling of a status value.

      iex> Tptp.Szs.Ontology.name(:counter_satisfiable)
      "CounterSatisfiable"
  """
  @spec name(t()) :: binary()
  def name(:success), do: "Success"
  def name(:semantic_success), do: "SemanticSuccess"
  def name(:unsatisfiability_preserving), do: "UnsatisfiabilityPreserving"
  def name(:satisfiability_preserving), do: "SatisfiabilityPreserving"
  def name(:tautology_preserving), do: "TautologyPreserving"
  def name(:equi_satisfiable), do: "EquiSatisfiable"
  def name(:equi_tautologous), do: "EquiTautologous"
  def name(:model_extending), do: "ModelExtending"
  def name(:satisfiable), do: "Satisfiable"
  def name(:finitely_satisfiable), do: "FinitelySatisfiable"
  def name(:finite_theorem), do: "FiniteTheorem"
  def name(:theorem), do: "Theorem"
  def name(:satisfiable_axioms_theorem), do: "SatisfiableAxiomsTheorem"
  def name(:equivalent), do: "Equivalent"
  def name(:tautologous_conclusion), do: "TautologousConclusion"
  def name(:weaker_conclusion), do: "WeakerConclusion"
  def name(:equivalent_theorem), do: "EquivalentTheorem"
  def name(:tautology), do: "Tautology"
  def name(:weaker_tautologous_conclusion), do: "WeakerTautologousConclusion"
  def name(:weaker_theorem), do: "WeakerTheorem"
  def name(:finite_tautology), do: "FiniteTautology"
  def name(:counter_unsatisfiability_preserving), do: "CounterUnsatisfiabilityPreserving"
  def name(:counter_satisfiability_preserving), do: "CounterSatisfiabilityPreserving"
  def name(:counter_tautologyy_preserving), do: "CounterTautologyyPreserving"
  def name(:equi_counter_satisfiable), do: "EquiCounterSatisfiable"
  def name(:equi_counter_tautologous), do: "EquiCounterTautologous"
  def name(:counter_model_extending), do: "CounterModelExtending"
  def name(:counter_satisfiable), do: "CounterSatisfiable"
  def name(:finitely_counter_satisfiable), do: "FinitelyCounterSatisfiable"
  def name(:finite_counter_theorem), do: "FiniteCounterTheorem"
  def name(:counter_theorem), do: "CounterTheorem"
  def name(:satisfiable_axioms_counter_theorem), do: "SatisfiableAxiomsCounterTheorem"
  def name(:counter_equivalent), do: "CounterEquivalent"
  def name(:unsatisfiable_conclusion), do: "UnsatisfiableConclusion"
  def name(:weaker_counter_conclusion), do: "WeakerCounterConclusion"
  def name(:equivalent_counter_theorem), do: "EquivalentCounterTheorem"
  def name(:unsatisfiable), do: "Unsatisfiable"
  def name(:weaker_unsatisfiable_conclusion), do: "WeakerUnsatisfiableConclusion"
  def name(:weaker_counter_theorem), do: "WeakerCounterTheorem"
  def name(:finitely_unsatisfiable), do: "FinitelyUnsatisfiable"
  def name(:contradictory_axioms), do: "ContradictoryAxioms"

  def name(:satisfiable_conclusion_contradictory_axioms),
    do: "SatisfiableConclusionContradictoryAxioms"

  def name(:satisfiable_counter_conclusion_contradictory_axioms),
    do: "SatisfiableCounterConclusionContradictoryAxioms"

  def name(:tautologous_conclusion_contradictory_axioms),
    do: "TautologousConclusionContradictoryAxioms"

  def name(:weaker_conclusion_contradictory_axioms), do: "WeakerConclusionContradictoryAxioms"

  def name(:unsatisfiable_conclusion_contradictory_axioms),
    do: "UnsatisfiableConclusionContradictoryAxioms"

  def name(:no_consequence), do: "NoConsequence"
  def name(:type_check_success), do: "TypeCheckSuccess"
  def name(:type_check_partial), do: "TypeCheckPartial"
  def name(:type_checked_complete), do: "TypeCheckedComplete"
  def name(:verify_success), do: "VerifySuccess"
  def name(:verified_good), do: "VerifiedGood"
  def name(:verified_bad), do: "VerifiedBad"
  def name(:no_success), do: "NoSuccess"
  def name(:unknown), do: "Unknown"
  def name(:stopped), do: "Stopped"
  def name(:in_progress), do: "InProgress"
  def name(:not_tried), do: "NotTried"
  def name(:not_tried_yet), do: "NotTriedYet"
  def name(:error), do: "Error"
  def name(:forced), do: "Forced"
  def name(:gave_up), do: "GaveUp"
  def name(:os_error), do: "OSError"
  def name(:input_error), do: "InputError"
  def name(:syntax_error), do: "SyntaxError"
  def name(:semantic_error), do: "SemanticError"
  def name(:type_error), do: "TypeError"
  def name(:unsemantic), do: "Unsemantic"
  def name(:usage_error), do: "UsageError"
  def name(:user), do: "User"
  def name(:resource_out), do: "ResourceOut"
  def name(:timeout), do: "Timeout"
  def name(:cpu_timeout), do: "CPUTimeout"
  def name(:wc_timeout), do: "WCTimeout"
  def name(:memory_out), do: "MemoryOut"
  def name(:incomplete), do: "Incomplete"
  def name(:inappropriate), do: "Inappropriate"
  def name(:incorrect), do: "Incorrect"
  def name(:assumed), do: "Assumed"
  def name(:open), do: "Open"
  def name(:not_verified), do: "NotVerified"
  def name(:failed_verified), do: "FailedVerified"
  def name(:data), do: "Data"
  def name(:logical_data), do: "LogicalData"
  def name(:solution), do: "Solution"
  def name(:proof), do: "Proof"
  def name(:interpretation), do: "Interpretation"
  def name(:list_of_formulae), do: "ListOfFormulae"
  def name(:derivation), do: "Derivation"
  def name(:refutation), do: "Refutation"
  def name(:cnf_refutation), do: "CNFRefutation"
  def name(:model), do: "Model"
  def name(:domain_interpretation), do: "DomainInterpretation"
  def name(:domain_model), do: "DomainModel"
  def name(:finite_interpretation), do: "FiniteInterpretation"
  def name(:finite_model), do: "FiniteModel"
  def name(:infinite_interpretation), do: "InfiniteInterpretation"
  def name(:infinite_model), do: "InfiniteModel"
  def name(:herbrand_interpretation), do: "HerbrandInterpretation"
  def name(:herbrand_model), do: "HerbrandModel"
  def name(:formula_herbrand_interpretation), do: "FormulaHerbrandInterpretation"
  def name(:formula_herbrand_model), do: "FormulaHerbrandModel"
  def name(:saturation), do: "Saturation"
  def name(:not_a_solution), do: "NotASolution"
  def name(:assurance), do: "Assurance"
  def name(:incomplete_proof), do: "IncompleteProof"
  def name(:incomplete_interpretation), do: "IncompleteInterpretation"
  def name(:non_logical_data), do: "NonLogicalData"
  def name(:comment), do: "Comment"
  def name(:free_text), do: "FreeText"
  def name(:verification), do: "Verification"
  def name(:none), do: "None"

  @doc """
  Turn a three-letter mnemonic into an atom. Case sensitive, because case is
  meaningful: `SAT` is `Satisfiable` and `Sat` is `Saturation`.

  A mnemonic the page reuses answers `{:ambiguous, values}` rather than picking
  one — `IIn` is both `InfiniteInterpretation` and `IncompleteInterpretation`.

      iex> Tptp.Szs.Ontology.from_mnemonic("THM")
      {:ok, :theorem}
      iex> Tptp.Szs.Ontology.from_mnemonic("IIn")
      {:ambiguous, [:infinite_interpretation, :incomplete_interpretation]}
      iex> Tptp.Szs.Ontology.from_mnemonic("thm")
      :error
  """
  @spec from_mnemonic(binary()) :: {:ok, t()} | {:ambiguous, [t()]} | :error
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
  def from_mnemonic("CTP"), do: {:ok, :counter_tautologyy_preserving}
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

  `<status_value>` in the BNF is the success ontology's mnemonic, lower-cased, and
  `mix tptp.gen` checks on every run that all 34 of them are present here.

      iex> Tptp.Szs.Ontology.from_status_value("thm")
      {:ok, :theorem}
      iex> Tptp.Szs.Ontology.from_status_value("prf")
      :error
  """
  @spec from_status_value(binary()) :: {:ok, t()} | :error
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
  def from_status_value("ctp"), do: {:ok, :counter_tautologyy_preserving}
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

      iex> Tptp.Szs.Ontology.mnemonic(:theorem)
      "THM"
  """
  @spec mnemonic(t()) :: binary()
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
  def mnemonic(:counter_tautologyy_preserving), do: "CTP"
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

      iex> Tptp.Szs.Ontology.describe(:theorem)
      "All models of Ax are models of C."
  """
  @spec describe(t()) :: binary()
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

  def describe(:counter_tautologyy_preserving),
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

  @doc """
  Which of the three ontologies a value belongs to.

      iex> Tptp.Szs.Ontology.ontology(:theorem)
      :success
      iex> Tptp.Szs.Ontology.ontology(:timeout)
      :no_success
  """
  @spec ontology(t()) :: ontology()
  def ontology(:success), do: :success
  def ontology(:semantic_success), do: :success
  def ontology(:unsatisfiability_preserving), do: :success
  def ontology(:satisfiability_preserving), do: :success
  def ontology(:tautology_preserving), do: :success
  def ontology(:equi_satisfiable), do: :success
  def ontology(:equi_tautologous), do: :success
  def ontology(:model_extending), do: :success
  def ontology(:satisfiable), do: :success
  def ontology(:finitely_satisfiable), do: :success
  def ontology(:finite_theorem), do: :success
  def ontology(:theorem), do: :success
  def ontology(:satisfiable_axioms_theorem), do: :success
  def ontology(:equivalent), do: :success
  def ontology(:tautologous_conclusion), do: :success
  def ontology(:weaker_conclusion), do: :success
  def ontology(:equivalent_theorem), do: :success
  def ontology(:tautology), do: :success
  def ontology(:weaker_tautologous_conclusion), do: :success
  def ontology(:weaker_theorem), do: :success
  def ontology(:finite_tautology), do: :success
  def ontology(:counter_unsatisfiability_preserving), do: :success
  def ontology(:counter_satisfiability_preserving), do: :success
  def ontology(:counter_tautologyy_preserving), do: :success
  def ontology(:equi_counter_satisfiable), do: :success
  def ontology(:equi_counter_tautologous), do: :success
  def ontology(:counter_model_extending), do: :success
  def ontology(:counter_satisfiable), do: :success
  def ontology(:finitely_counter_satisfiable), do: :success
  def ontology(:finite_counter_theorem), do: :success
  def ontology(:counter_theorem), do: :success
  def ontology(:satisfiable_axioms_counter_theorem), do: :success
  def ontology(:counter_equivalent), do: :success
  def ontology(:unsatisfiable_conclusion), do: :success
  def ontology(:weaker_counter_conclusion), do: :success
  def ontology(:equivalent_counter_theorem), do: :success
  def ontology(:unsatisfiable), do: :success
  def ontology(:weaker_unsatisfiable_conclusion), do: :success
  def ontology(:weaker_counter_theorem), do: :success
  def ontology(:finitely_unsatisfiable), do: :success
  def ontology(:contradictory_axioms), do: :success
  def ontology(:satisfiable_conclusion_contradictory_axioms), do: :success
  def ontology(:satisfiable_counter_conclusion_contradictory_axioms), do: :success
  def ontology(:tautologous_conclusion_contradictory_axioms), do: :success
  def ontology(:weaker_conclusion_contradictory_axioms), do: :success
  def ontology(:unsatisfiable_conclusion_contradictory_axioms), do: :success
  def ontology(:no_consequence), do: :success
  def ontology(:type_check_success), do: :success
  def ontology(:type_check_partial), do: :success
  def ontology(:type_checked_complete), do: :success
  def ontology(:verify_success), do: :success
  def ontology(:verified_good), do: :success
  def ontology(:verified_bad), do: :success
  def ontology(:no_success), do: :no_success
  def ontology(:unknown), do: :no_success
  def ontology(:stopped), do: :no_success
  def ontology(:in_progress), do: :no_success
  def ontology(:not_tried), do: :no_success
  def ontology(:not_tried_yet), do: :no_success
  def ontology(:error), do: :no_success
  def ontology(:forced), do: :no_success
  def ontology(:gave_up), do: :no_success
  def ontology(:os_error), do: :no_success
  def ontology(:input_error), do: :no_success
  def ontology(:syntax_error), do: :no_success
  def ontology(:semantic_error), do: :no_success
  def ontology(:type_error), do: :no_success
  def ontology(:unsemantic), do: :no_success
  def ontology(:usage_error), do: :no_success
  def ontology(:user), do: :no_success
  def ontology(:resource_out), do: :no_success
  def ontology(:timeout), do: :no_success
  def ontology(:cpu_timeout), do: :no_success
  def ontology(:wc_timeout), do: :no_success
  def ontology(:memory_out), do: :no_success
  def ontology(:incomplete), do: :no_success
  def ontology(:inappropriate), do: :no_success
  def ontology(:incorrect), do: :no_success
  def ontology(:assumed), do: :no_success
  def ontology(:open), do: :no_success
  def ontology(:not_verified), do: :no_success
  def ontology(:failed_verified), do: :no_success
  def ontology(:data), do: :data
  def ontology(:logical_data), do: :data
  def ontology(:solution), do: :data
  def ontology(:proof), do: :data
  def ontology(:interpretation), do: :data
  def ontology(:list_of_formulae), do: :data
  def ontology(:derivation), do: :data
  def ontology(:refutation), do: :data
  def ontology(:cnf_refutation), do: :data
  def ontology(:model), do: :data
  def ontology(:domain_interpretation), do: :data
  def ontology(:domain_model), do: :data
  def ontology(:finite_interpretation), do: :data
  def ontology(:finite_model), do: :data
  def ontology(:infinite_interpretation), do: :data
  def ontology(:infinite_model), do: :data
  def ontology(:herbrand_interpretation), do: :data
  def ontology(:herbrand_model), do: :data
  def ontology(:formula_herbrand_interpretation), do: :data
  def ontology(:formula_herbrand_model), do: :data
  def ontology(:saturation), do: :data
  def ontology(:not_a_solution), do: :data
  def ontology(:assurance), do: :data
  def ontology(:incomplete_proof), do: :data
  def ontology(:incomplete_interpretation), do: :data
  def ontology(:non_logical_data), do: :data
  def ontology(:comment), do: :data
  def ontology(:free_text), do: :data
  def ontology(:verification), do: :data
  def ontology(:none), do: :data

  @doc """
  The top-level grouping a value sits under.

      iex> Tptp.Szs.Ontology.subontology(:theorem)
      :semantic_success
      iex> Tptp.Szs.Ontology.subontology(:verified_good)
      :verify_success
  """
  @spec subontology(t()) :: subontology()
  def subontology(:success), do: :success
  def subontology(:semantic_success), do: :semantic_success
  def subontology(:unsatisfiability_preserving), do: :semantic_success
  def subontology(:satisfiability_preserving), do: :semantic_success
  def subontology(:tautology_preserving), do: :semantic_success
  def subontology(:equi_satisfiable), do: :semantic_success
  def subontology(:equi_tautologous), do: :semantic_success
  def subontology(:model_extending), do: :semantic_success
  def subontology(:satisfiable), do: :semantic_success
  def subontology(:finitely_satisfiable), do: :semantic_success
  def subontology(:finite_theorem), do: :semantic_success
  def subontology(:theorem), do: :semantic_success
  def subontology(:satisfiable_axioms_theorem), do: :semantic_success
  def subontology(:equivalent), do: :semantic_success
  def subontology(:tautologous_conclusion), do: :semantic_success
  def subontology(:weaker_conclusion), do: :semantic_success
  def subontology(:equivalent_theorem), do: :semantic_success
  def subontology(:tautology), do: :semantic_success
  def subontology(:weaker_tautologous_conclusion), do: :semantic_success
  def subontology(:weaker_theorem), do: :semantic_success
  def subontology(:finite_tautology), do: :semantic_success
  def subontology(:counter_unsatisfiability_preserving), do: :semantic_success
  def subontology(:counter_satisfiability_preserving), do: :semantic_success
  def subontology(:counter_tautologyy_preserving), do: :semantic_success
  def subontology(:equi_counter_satisfiable), do: :semantic_success
  def subontology(:equi_counter_tautologous), do: :semantic_success
  def subontology(:counter_model_extending), do: :semantic_success
  def subontology(:counter_satisfiable), do: :semantic_success
  def subontology(:finitely_counter_satisfiable), do: :semantic_success
  def subontology(:finite_counter_theorem), do: :semantic_success
  def subontology(:counter_theorem), do: :semantic_success
  def subontology(:satisfiable_axioms_counter_theorem), do: :semantic_success
  def subontology(:counter_equivalent), do: :semantic_success
  def subontology(:unsatisfiable_conclusion), do: :semantic_success
  def subontology(:weaker_counter_conclusion), do: :semantic_success
  def subontology(:equivalent_counter_theorem), do: :semantic_success
  def subontology(:unsatisfiable), do: :semantic_success
  def subontology(:weaker_unsatisfiable_conclusion), do: :semantic_success
  def subontology(:weaker_counter_theorem), do: :semantic_success
  def subontology(:finitely_unsatisfiable), do: :semantic_success
  def subontology(:contradictory_axioms), do: :semantic_success
  def subontology(:satisfiable_conclusion_contradictory_axioms), do: :semantic_success
  def subontology(:satisfiable_counter_conclusion_contradictory_axioms), do: :semantic_success
  def subontology(:tautologous_conclusion_contradictory_axioms), do: :semantic_success
  def subontology(:weaker_conclusion_contradictory_axioms), do: :semantic_success
  def subontology(:unsatisfiable_conclusion_contradictory_axioms), do: :semantic_success
  def subontology(:no_consequence), do: :semantic_success
  def subontology(:type_check_success), do: :type_check_success
  def subontology(:type_check_partial), do: :type_check_success
  def subontology(:type_checked_complete), do: :type_check_success
  def subontology(:verify_success), do: :verify_success
  def subontology(:verified_good), do: :verify_success
  def subontology(:verified_bad), do: :verify_success
  def subontology(:no_success), do: :no_success
  def subontology(:unknown), do: :no_success
  def subontology(:stopped), do: :no_success
  def subontology(:in_progress), do: :no_success
  def subontology(:not_tried), do: :no_success
  def subontology(:not_tried_yet), do: :no_success
  def subontology(:error), do: :no_success
  def subontology(:forced), do: :no_success
  def subontology(:gave_up), do: :no_success
  def subontology(:os_error), do: :no_success
  def subontology(:input_error), do: :no_success
  def subontology(:syntax_error), do: :no_success
  def subontology(:semantic_error), do: :no_success
  def subontology(:type_error), do: :no_success
  def subontology(:unsemantic), do: :no_success
  def subontology(:usage_error), do: :no_success
  def subontology(:user), do: :no_success
  def subontology(:resource_out), do: :no_success
  def subontology(:timeout), do: :no_success
  def subontology(:cpu_timeout), do: :no_success
  def subontology(:wc_timeout), do: :no_success
  def subontology(:memory_out), do: :no_success
  def subontology(:incomplete), do: :no_success
  def subontology(:inappropriate), do: :no_success
  def subontology(:incorrect), do: :no_success
  def subontology(:assumed), do: :no_success
  def subontology(:open), do: :no_success
  def subontology(:not_verified), do: :no_success
  def subontology(:failed_verified), do: :no_success
  def subontology(:data), do: :data
  def subontology(:logical_data), do: :data
  def subontology(:solution), do: :data
  def subontology(:proof), do: :data
  def subontology(:interpretation), do: :data
  def subontology(:list_of_formulae), do: :data
  def subontology(:derivation), do: :data
  def subontology(:refutation), do: :data
  def subontology(:cnf_refutation), do: :data
  def subontology(:model), do: :data
  def subontology(:domain_interpretation), do: :data
  def subontology(:domain_model), do: :data
  def subontology(:finite_interpretation), do: :data
  def subontology(:finite_model), do: :data
  def subontology(:infinite_interpretation), do: :data
  def subontology(:infinite_model), do: :data
  def subontology(:herbrand_interpretation), do: :data
  def subontology(:herbrand_model), do: :data
  def subontology(:formula_herbrand_interpretation), do: :data
  def subontology(:formula_herbrand_model), do: :data
  def subontology(:saturation), do: :data
  def subontology(:not_a_solution), do: :data
  def subontology(:assurance), do: :data
  def subontology(:incomplete_proof), do: :data
  def subontology(:incomplete_interpretation), do: :data
  def subontology(:non_logical_data), do: :data
  def subontology(:comment), do: :data
  def subontology(:free_text), do: :data
  def subontology(:verification), do: :data
  def subontology(:none), do: :data

  @doc """
  Whether a term is a status value at all.

      iex> Tptp.Szs.Ontology.value?(:theorem)
      true
      iex> Tptp.Szs.Ontology.value?(:banana)
      false
  """
  @spec value?(term()) :: boolean()
  def value?(:success), do: true
  def value?(:semantic_success), do: true
  def value?(:unsatisfiability_preserving), do: true
  def value?(:satisfiability_preserving), do: true
  def value?(:tautology_preserving), do: true
  def value?(:equi_satisfiable), do: true
  def value?(:equi_tautologous), do: true
  def value?(:model_extending), do: true
  def value?(:satisfiable), do: true
  def value?(:finitely_satisfiable), do: true
  def value?(:finite_theorem), do: true
  def value?(:theorem), do: true
  def value?(:satisfiable_axioms_theorem), do: true
  def value?(:equivalent), do: true
  def value?(:tautologous_conclusion), do: true
  def value?(:weaker_conclusion), do: true
  def value?(:equivalent_theorem), do: true
  def value?(:tautology), do: true
  def value?(:weaker_tautologous_conclusion), do: true
  def value?(:weaker_theorem), do: true
  def value?(:finite_tautology), do: true
  def value?(:counter_unsatisfiability_preserving), do: true
  def value?(:counter_satisfiability_preserving), do: true
  def value?(:counter_tautologyy_preserving), do: true
  def value?(:equi_counter_satisfiable), do: true
  def value?(:equi_counter_tautologous), do: true
  def value?(:counter_model_extending), do: true
  def value?(:counter_satisfiable), do: true
  def value?(:finitely_counter_satisfiable), do: true
  def value?(:finite_counter_theorem), do: true
  def value?(:counter_theorem), do: true
  def value?(:satisfiable_axioms_counter_theorem), do: true
  def value?(:counter_equivalent), do: true
  def value?(:unsatisfiable_conclusion), do: true
  def value?(:weaker_counter_conclusion), do: true
  def value?(:equivalent_counter_theorem), do: true
  def value?(:unsatisfiable), do: true
  def value?(:weaker_unsatisfiable_conclusion), do: true
  def value?(:weaker_counter_theorem), do: true
  def value?(:finitely_unsatisfiable), do: true
  def value?(:contradictory_axioms), do: true
  def value?(:satisfiable_conclusion_contradictory_axioms), do: true
  def value?(:satisfiable_counter_conclusion_contradictory_axioms), do: true
  def value?(:tautologous_conclusion_contradictory_axioms), do: true
  def value?(:weaker_conclusion_contradictory_axioms), do: true
  def value?(:unsatisfiable_conclusion_contradictory_axioms), do: true
  def value?(:no_consequence), do: true
  def value?(:type_check_success), do: true
  def value?(:type_check_partial), do: true
  def value?(:type_checked_complete), do: true
  def value?(:verify_success), do: true
  def value?(:verified_good), do: true
  def value?(:verified_bad), do: true
  def value?(:no_success), do: true
  def value?(:unknown), do: true
  def value?(:stopped), do: true
  def value?(:in_progress), do: true
  def value?(:not_tried), do: true
  def value?(:not_tried_yet), do: true
  def value?(:error), do: true
  def value?(:forced), do: true
  def value?(:gave_up), do: true
  def value?(:os_error), do: true
  def value?(:input_error), do: true
  def value?(:syntax_error), do: true
  def value?(:semantic_error), do: true
  def value?(:type_error), do: true
  def value?(:unsemantic), do: true
  def value?(:usage_error), do: true
  def value?(:user), do: true
  def value?(:resource_out), do: true
  def value?(:timeout), do: true
  def value?(:cpu_timeout), do: true
  def value?(:wc_timeout), do: true
  def value?(:memory_out), do: true
  def value?(:incomplete), do: true
  def value?(:inappropriate), do: true
  def value?(:incorrect), do: true
  def value?(:assumed), do: true
  def value?(:open), do: true
  def value?(:not_verified), do: true
  def value?(:failed_verified), do: true
  def value?(:data), do: true
  def value?(:logical_data), do: true
  def value?(:solution), do: true
  def value?(:proof), do: true
  def value?(:interpretation), do: true
  def value?(:list_of_formulae), do: true
  def value?(:derivation), do: true
  def value?(:refutation), do: true
  def value?(:cnf_refutation), do: true
  def value?(:model), do: true
  def value?(:domain_interpretation), do: true
  def value?(:domain_model), do: true
  def value?(:finite_interpretation), do: true
  def value?(:finite_model), do: true
  def value?(:infinite_interpretation), do: true
  def value?(:infinite_model), do: true
  def value?(:herbrand_interpretation), do: true
  def value?(:herbrand_model), do: true
  def value?(:formula_herbrand_interpretation), do: true
  def value?(:formula_herbrand_model), do: true
  def value?(:saturation), do: true
  def value?(:not_a_solution), do: true
  def value?(:assurance), do: true
  def value?(:incomplete_proof), do: true
  def value?(:incomplete_interpretation), do: true
  def value?(:non_logical_data), do: true
  def value?(:comment), do: true
  def value?(:free_text), do: true
  def value?(:verification), do: true
  def value?(:none), do: true
  def value?(_other), do: false

  @doc """
  Whether a value says something was established.

      iex> Tptp.Szs.Ontology.success?(:theorem)
      true
      iex> Tptp.Szs.Ontology.success?(:gave_up)
      false
  """
  @spec success?(t()) :: boolean()
  def success?(value), do: ontology(value) == :success

  @doc """
  Whether a value says why nothing was established.

      iex> Tptp.Szs.Ontology.no_success?(:timeout)
      true
  """
  @spec no_success?(t()) :: boolean()
  def no_success?(value), do: ontology(value) == :no_success

  @doc """
  Whether a value describes a form of data rather than a result.

      iex> Tptp.Szs.Ontology.data?(:cnf_refutation)
      true
  """
  @spec data?(t()) :: boolean()
  def data?(value), do: ontology(value) == :data
end
