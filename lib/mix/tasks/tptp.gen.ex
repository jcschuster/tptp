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
  undefined-module warning, and the task regenerates all five outputs from the
  vendored sources. The generated grammar is a function of the BNF alone, so
  discarding it loses nothing.
  """

  use Mix.Task

  alias Tptp.Bnf
  alias Tptp.Bnf.Generator
  alias Tptp.Bnf.Oracle
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

    {oracle, pattern_count} = Oracle.table(bnf_path)
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

    Enum.each(entries, fn
      {"reserved_word", words} ->
        shell.info("  $-words collected from the whole BNF: #{length(words)} (not a :== rule)")

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
end
