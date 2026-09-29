defmodule Mix.Tasks.Tptp.Gen do
  @shortdoc "Regenerate the committed sources from the vendored TPTP World BNFs"

  @moduledoc """
  Regenerates the committed sources from the two vendored TPTP World BNFs,
  `priv/bnf/SyntaxBNF-v*` and `priv/bnf/SZSOntology.bnf`.

  This is a maintainer action, taken when a new TPTP release changes the BNF. The
  generated `.yrl` is committed, so an installing user needs nothing but OTP —
  `yecc` ships with it and Mix compiles `src/*.yrl` automatically.

  Five files are generated. From the `SyntaxBNF`: `src/tptp_parser.yrl`,
  `lib/tptp/printer/shapes.ex` and `test/support/bnf_oracle.ex`. From
  `SZSOntology.bnf`: `lib/tptp/szs/ontology.ex`. From both:
  `lib/tptp/bnf/vocabulary.ex`, whose `<status_value>` list the `SyntaxBNF`
  references and the SZS BNF defines.

      mix tptp.gen
      mix tptp.gen --check

  `--check` regenerates into memory and fails if the result differs from the
  committed output, which is what prevents a generated file from being hand-edited.

  The task prints the departures made from a mechanical translation. That list comes
  from `Tptp.Bnf.Generator.departures/0`, which renders it from the constants
  producing it, so a release requiring a further departure is reported rather than
  absorbed into the grammar.

  ## Recovering from an uncompilable grammar

  Mix runs the `:yecc` compiler before `:elixir`, so a `src/tptp_parser.yrl` that
  does not compile prevents the task that would rewrite it from running. A manual
  edit or an incomplete merge therefore renders the generator unreachable through
  its own output.

  Delete the file and run the task again. With no `.yrl` present there is nothing
  for yecc to compile, `Tptp.Parser`'s calls into `:tptp_parser` produce only an
  undefined-module warning, and the task regenerates all four outputs from the
  vendored BNF. The generated grammar is a function of the BNF alone, so
  discarding it loses nothing.
  """

  use Mix.Task

  alias Tptp.Bnf
  alias Tptp.Bnf.Generator
  alias Tptp.Bnf.Oracle
  alias Tptp.Bnf.Szs

  @requirements ["app.config"]

  @grammar_path "src/tptp_parser.yrl"
  @vocabulary_path "lib/tptp/bnf/vocabulary.ex"
  @shapes_path "lib/tptp/printer/shapes.ex"
  @oracle_path "test/support/bnf_oracle.ex"
  @ontology_path "lib/tptp/szs/ontology.ex"

  @impl Mix.Task
  def run(argv) do
    {options, _rest} = OptionParser.parse!(argv, strict: [check: :boolean])

    bnf_path = Bnf.vendored_path!()
    szs_path = Bnf.szs_path!()
    {grammar, report} = Generator.generate(bnf_path)
    {vocabulary, entries} = Generator.vocabularies(bnf_path, szs_path)
    {shapes, shape_count} = Generator.shapes(bnf_path)
    {ontology, szs_report} = Szs.generate(szs_path)

    {oracle, pattern_count} = Oracle.table(bnf_path)

    action = if options[:check], do: &check/2, else: &write/2
    action.(@grammar_path, grammar)
    action.(@vocabulary_path, format(vocabulary))
    action.(@shapes_path, format(shapes))
    action.(@oracle_path, format(oracle))
    action.(@ontology_path, format(ontology))
    Mix.shell().info("#{shape_count} printer shapes")
    Mix.shell().info("#{pattern_count} token oracle patterns")

    describe(bnf_path, report, entries)
    describe_szs(szs_path, szs_report)
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

  defp describe(bnf_path, report, entries) do
    shell = Mix.shell()
    shell.info("")
    shell.info("BNF          #{Path.basename(bnf_path)} (v#{Bnf.version!(bnf_path)})")
    shell.info("rules        #{report.rules} reachable from <TPTP_input>")
    shell.info("productions  #{report.productions}")
    shell.info("nonterminals #{report.nonterminals}")
    shell.info("terminals    #{report.terminals}")
    shell.info("inlined      #{length(report.inlined)} single-terminal rules")
    shell.info("transparent  #{length(report.transparent)} spliced away")
    shell.info("significant  #{length(report.significant)} collapsed onto their leaf")
    shell.info("")
    shell.info("closed :== vocabularies:")

    Enum.each(entries, fn
      {"reserved_word", words} ->
        shell.info("  $-words TPTP defines: #{length(words)} (not a :== rule)")

      {"status_value", words} ->
        shell.info(
          "  <status_value> #{length(words)} (from <inference_status_value> in the SZS BNF)"
        )

      {name, words} ->
        shell.info("  <#{name}> #{length(words)}")
    end)

    shell.info("")
    shell.info("departures from a mechanical translation (#{length(report.departures)}):")
    Enum.each(report.departures, &shell.info("  #{&1}"))

    if report.pruned != [] do
      shell.info("")
      shell.info("unreachable from <TPTP_input>, pruned:")
      Enum.each(report.pruned, &shell.info("  <#{&1}>"))
    end
  end

  defp describe_szs(szs_path, report) do
    shell = Mix.shell()
    shell.info("")
    shell.info("SZS BNF      #{Path.basename(szs_path)}")
    shell.info("values       #{report.values}")
    shell.info("isa edges    #{report.edges}")
    shell.info("ontologies   #{Enum.map_join(report.roots, ", ", &"<#{&1}>")}")
    shell.info("mnemonics    #{report.mnemonics} in <inference_status_value>")
  end
end
