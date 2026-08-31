defmodule Mix.Tasks.Tptp.Format do
  @shortdoc "Reformat TPTP files without changing a token"

  @moduledoc """
  Reformat TPTP files in place.

      mix tptp.format Problems/PUZ/PUZ001+1.p
      mix tptp.format "Axioms/**/*.ax"
      mix tptp.format --check Problems/**/*.p

  Only white space moves. The token sequence is unchanged, which `Tptp.Printer.Format`
  explains and a test asserts over the corpus, so this cannot silently rewrite a
  formula into a different one.

  A file whose tokens do not lex cleanly is left alone and reported, because a
  formatter is reached for exactly when a file is in a bad state and rewriting one
  it cannot read is how it loses someone's work.

  ## Options

    * `--check` — change nothing; exit non-zero if any file would change. For CI.
  """

  use Mix.Task

  alias Tptp.Printer.Format

  @impl Mix.Task
  def run(argv) do
    {options, patterns} = OptionParser.parse!(argv, strict: [check: :boolean])

    case expand(patterns) do
      [] ->
        Mix.raise(
          "no files matched; give a path or a wildcard, e.g. mix tptp.format 'problems/*.p'"
        )

      paths ->
        check = options[:check] == true
        paths |> Enum.map(&handle(&1, check)) |> report(check)
    end
  end

  defp expand(patterns),
    do: patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq() |> Enum.sort()

  defp handle(path, true) do
    case File.read(path) do
      {:ok, source} ->
        {path, if(Format.to_string(source) == source, do: :unchanged, else: :changed)}

      {:error, reason} ->
        {path, {:error, reason}}
    end
  end

  defp handle(path, _check) do
    case Format.format_file(path) do
      {:ok, outcome} -> {path, outcome}
      {:error, reason} -> {path, {:error, reason}}
    end
  end

  defp report(results, check) do
    changed = for {path, :changed} <- results, do: path
    failed = for {path, {:error, reason}} <- results, do: {path, reason}

    Enum.each(failed, fn {path, reason} ->
      Mix.shell().error("#{path}: #{:file.format_error(reason)}")
    end)

    cond do
      failed != [] ->
        Mix.raise("#{length(failed)} file#{plural(failed)} could not be read")

      check and changed != [] ->
        Enum.each(changed, &Mix.shell().info(&1))
        Mix.raise("#{length(changed)} file#{plural(changed)} would be reformatted")

      check ->
        Mix.shell().info("#{length(results)} file#{plural(results)} already formatted")

      true ->
        Mix.shell().info("reformatted #{length(changed)} of #{length(results)} files")
    end
  end

  defp plural([_one]), do: ""
  defp plural(_many), do: "s"
end
