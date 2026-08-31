defmodule Mix.Tasks.Tptp.Gen do
  @shortdoc "Regenerate src/tptp_parser.yrl from the vendored TPTP BNF"

  @moduledoc """
  Regenerates the committed sources from the two vendored files: the TPTP BNF at
  `priv/bnf/SyntaxBNF-v*` and the SZS ontology page at `priv/szs/SZSOntology-*`.

  This is a maintainer action, taken when a new TPTP release changes the BNF. The
  generated `.yrl` is committed, so an installing user needs nothing but OTP —
  `yecc` ships with it and Mix compiles `src/*.yrl` automatically.

      mix tptp.gen
      mix tptp.gen --check

  `--check` regenerates into memory and fails if the result differs from what is
  on disk, which is what keeps "generated but committed" from quietly becoming
  "hand-edited".

  The task prints the departures it made from a mechanical translation. Those
  three lines are the review surface for a BNF bump: if a release adds a fourth,
  it should be a conscious decision rather than a silent one.

  ## Recovering from a broken `.yrl`

  Mix runs the `:yecc` compiler before `:elixir`, so a `src/tptp_parser.yrl` that
  does not compile stops the very task that would rewrite it — a hand-edit or a
  half-finished merge leaves the generator unreachable through its own output.
  **Delete the file and run the task again.** With no `.yrl` present there is
  nothing for yecc to choke on, `Tptp.Parser`'s calls into `:tptp_parser` are only
  an undefined-module warning at that point, and the task regenerates all five
  outputs from the vendored sources. It is worth knowing rather than worth
  engineering around: the generated grammar is a pure function of the BNF, so
  throwing it away costs nothing.
  """

  use Mix.Task

  alias Tptp.Bnf
  alias Tptp.Bnf.Generator
  alias Tptp.Szs

  @requirements ["app.config"]

  @grammar_path "src/tptp_parser.yrl"
  @vocabulary_path "lib/tptp/bnf/vocabulary.ex"
  @shapes_path "lib/tptp/printer/shapes.ex"
  @ontology_path "lib/tptp/szs/ontology.ex"
  @oracle_path "test/support/bnf_oracle.ex"

  @impl Mix.Task
  def run(argv) do
    {options, _rest} = OptionParser.parse!(argv, strict: [check: :boolean])

    bnf_path = Bnf.vendored_path!()
    {grammar, report} = Generator.generate(bnf_path)
    {vocabulary, entries} = Generator.vocabularies(bnf_path)
    {shapes, shape_count} = Generator.shapes(bnf_path)

    {oracle, pattern_count} = Tptp.Bnf.Oracle.table(bnf_path)
    szs_path = Szs.vendored_path!()
    {ontology, value_count} = Szs.Generator.ontology(szs_path)

    action = if options[:check], do: &check/2, else: &write/2
    action.(@grammar_path, grammar)
    action.(@vocabulary_path, format(vocabulary))
    action.(@shapes_path, format(shapes))
    action.(@ontology_path, format(ontology))
    action.(@oracle_path, format(oracle))
    Mix.shell().info("#{shape_count} printer shapes")
    Mix.shell().info("#{pattern_count} token oracle patterns")
    Mix.shell().info("#{value_count} SZS status values")

    describe(bnf_path, szs_path, report, entries)
  end

  defp format(source), do: Code.format_string!(source) |> IO.iodata_to_binary() |> Kernel.<>("\n")

  defp write(path, source) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
    Mix.shell().info("wrote #{path}")
  end

  defp check(path, source) do
    case File.read(path) do
      {:ok, ^source} ->
        Mix.shell().info("#{path} is up to date")

      {:ok, _other} ->
        Mix.raise("#{path} is stale; run `mix tptp.gen` and commit the result")

      {:error, reason} ->
        Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp describe(bnf_path, szs_path, report, entries) do
    shell = Mix.shell()
    shell.info("")
    shell.info("BNF          #{Path.basename(bnf_path)} (v#{Bnf.version!(bnf_path)})")
    shell.info("SZS          #{Path.basename(szs_path)}")
    shell.info("rules        #{report.rules} reachable from <TPTP_input>")
    shell.info("productions  #{report.productions}")
    shell.info("nonterminals #{report.nonterminals}")
    shell.info("terminals    #{report.terminals}")
    shell.info("inlined      #{length(report.inlined)} single-terminal rules")
    shell.info("transparent  #{length(report.transparent)} spliced away")
    shell.info("significant  #{length(report.significant)} collapsed onto their leaf")
    shell.info("")
    shell.info("closed :== vocabularies:")

    Enum.each(entries, fn {name, words} ->
      shell.info("  <#{name}> #{length(words)}")
    end)

    shell.info("")
    shell.info("departures from a mechanical translation:")
    shell.info("  dropped alternative  <source> ::= unknown")
    shell.info("  injected #{report.injected} productions admitting keywords as <atomic_word>")
    shell.info("  reserved the six $-keywords")
    shell.info("  kept the five $-language markers as children of <formula_data>")

    if report.pruned != [] do
      shell.info("")
      shell.info("unreachable from <TPTP_input>, pruned:")
      Enum.each(report.pruned, &shell.info("  <#{&1}>"))
    end
  end
end
