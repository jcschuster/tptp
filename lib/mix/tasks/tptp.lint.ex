defmodule Mix.Tasks.Tptp.Lint do
  @shortdoc "Report what this library has to say about TPTP files"

  @moduledoc """
  Read TPTP files and print their diagnostics.

      mix tptp.lint Problems/PUZ/PUZ001+1.p
      mix tptp.lint "Problems/SYN/*.p"
      mix tptp.lint --include Problems/CSR/CSR001+1.p
      mix tptp.lint --severity error --format json "Axioms/*.ax"

  `Tptp.analyze/2` produces the same information from Elixir in one traversal. This
  task exposes it from a shell.

  ## What it reports

  Both tiers in one pass: the lexical and grammatical diagnostics arising from
  reading the input, and the `:==` well-formedness findings from `Tptp.Lint`. Each
  is printed as `path:line:column: severity: message [CODE]`.

      Problems/SYN/SYN000+2.p:86:44: error: unexpected `(` [TPTP0301]

  ## Includes are not followed unless you say so

  Without `--include`, each file is read alone, so a problem declaring its symbols
  in an included axiom set reports every one of them as undeclared. The finding is
  correct — the file does not itself declare them — but is rarely useful.
  `--include` resolves the graph against `$TPTP_ROOT` and analyses the whole unit,
  under which `TPTP0501` and the conjecture count can be correct.

  ## Exit status

  Non-zero where any diagnostic at or above `--severity` was reported.
  `--severity none` reports everything and always succeeds.

  ## Options

    * `--include` — resolve `include` directives and lint the whole unit. Uses
      `Tptp.Resolver.Fs`, which searches the including file's directory, `$TPTP_ROOT`,
      `$TPTP` and the working directory.
    * `--root PATH` — a library root to resolve against, instead of `$TPTP_ROOT`.
      Implies `--include`.
    * `--severity LEVEL` — the lowest severity that fails the run: `error`,
      `warning`, `info`, `hint`, or `none`. Defaults to `error`.
    * `--only CODE` — report only this diagnostic code. Repeatable.
    * `--suppress CODE` — report everything but this code. Repeatable.
    * `--format FORMAT` — `pretty` (the default) or `json`, one object per line, for
      a tool that would rather not parse text.
    * `--quiet` — print nothing; use the exit status.
  """

  use Mix.Task

  @severities [:error, :warning, :info, :hint]
  @order Enum.with_index(@severities) |> Map.new()

  @impl Mix.Task
  def run(argv) do
    {options, patterns} =
      OptionParser.parse!(argv,
        strict: [
          include: :boolean,
          root: :string,
          severity: :string,
          only: :keep,
          suppress: :keep,
          format: :string,
          quiet: :boolean
        ]
      )

    Mix.Task.run("app.start")

    paths = expand(patterns)
    if paths == [], do: Mix.raise("no files matched; give a path or a wildcard")

    threshold = threshold(options)
    format = format(options)

    reported =
      paths
      |> Enum.flat_map(&diagnose(&1, options))
      |> Enum.filter(&keep?(&1, options))
      |> Enum.sort_by(fn {path, line, column, d} -> {path, line, column, d.code} end)

    unless options[:quiet], do: report(reported, format)

    failing = Enum.count(reported, fn {_p, _l, _c, d} -> at_least?(d.severity, threshold) end)

    if failing > 0 do
      Mix.raise("#{failing} #{noun(failing)} at #{threshold} or above in #{length(paths)} files")
    end

    unless options[:quiet] do
      Mix.shell().info("#{length(paths)} #{files(paths)}, #{length(reported)} reported")
    end
  end

  defp expand(patterns),
    do: patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq() |> Enum.sort()

  defp diagnose(path, options) do
    case read(path, options) do
      {:ok, subject} ->
        analysis = subject |> Tptp.analyze() |> Tptp.Analysis.with_line_index()

        Enum.map(analysis.diagnostics, fn diagnostic ->
          {line, column} = Tptp.Analysis.line_column(analysis, diagnostic.span.offset)
          {path, line, column, diagnostic}
        end)

      {:error, diagnostics} ->
        Enum.map(diagnostics, &{path, 1, 1, &1})
    end
  end

  # Codes arrive as strings and stay strings. A diagnostic code is data from a command
  # line, and turning one into an atom to match on it is how a library that reads
  # untrusted input grows an atom-table leak — the same reason `Tptp.Lint` keys its own
  # `:severity` and `:suppress` options on binaries.
  defp keep?({_path, _line, _column, diagnostic}, options) do
    only = Keyword.get_values(options, :only)
    suppress = Keyword.get_values(options, :suppress)

    (only == [] or diagnostic.code in only) and diagnostic.code not in suppress
  end

  defp read(path, options) do
    if options[:include] == true or options[:root] != nil do
      Tptp.Unit.from_file(path, resolver: resolver(options), max_concurrency: 1)
      |> case do
        {:ok, unit, _diagnostics} -> {:ok, unit}
        {:error, diagnostics} -> {:error, diagnostics}
      end
    else
      case Tptp.from_file(path) do
        {:ok, file, _diagnostics} -> {:ok, file}
        {:error, diagnostics} -> {:error, diagnostics}
      end
    end
  end

  defp resolver(options) do
    case options[:root] do
      nil -> Tptp.Resolver.Fs
      root -> {Tptp.Resolver.Fs, root: root}
    end
  end

  defp report(reported, :json) do
    Enum.each(reported, fn {path, line, column, diagnostic} ->
      Mix.shell().info(
        json(%{
          "file" => path,
          "line" => line,
          "column" => column,
          "severity" => Atom.to_string(diagnostic.severity),
          "code" => diagnostic.code,
          "message" => diagnostic.message,
          "hint" => diagnostic.hint
        })
      )
    end)
  end

  defp report(reported, :pretty) do
    Enum.each(reported, fn {path, line, column, diagnostic} ->
      Mix.shell().info(
        "#{path}:#{line}:#{column}: #{diagnostic.severity}: " <>
          "#{diagnostic.message} [#{diagnostic.code}]"
      )

      if diagnostic.hint, do: Mix.shell().info("    hint: #{diagnostic.hint}")
    end)
  end

  # Small enough not to be worth a dependency, and this library has none at runtime.
  defp json(fields) do
    body =
      fields
      |> Enum.reject(fn {_key, value} -> value == nil end)
      |> Enum.map_join(",", fn {key, value} -> ~s("#{key}":#{encode(value)}) end)

    "{" <> body <> "}"
  end

  defp encode(value) when is_integer(value), do: Integer.to_string(value)
  defp encode(value) when is_binary(value), do: inspect(value, printable_limit: :infinity)

  defp threshold(options) do
    case options[:severity] do
      nil ->
        :error

      "none" ->
        :none

      name when name in ~w(error warning info hint) ->
        String.to_existing_atom(name)

      other ->
        Mix.raise(
          "unknown severity #{inspect(other)}; expected error, warning, info, hint or none"
        )
    end
  end

  defp format(options) do
    case options[:format] do
      nil -> :pretty
      "pretty" -> :pretty
      "json" -> :json
      other -> Mix.raise("unknown format #{inspect(other)}; expected pretty or json")
    end
  end

  defp at_least?(_severity, :none), do: false
  defp at_least?(severity, threshold), do: @order[severity] <= @order[threshold]

  defp noun(1), do: "diagnostic"
  defp noun(_many), do: "diagnostics"

  defp files([_one]), do: "file"
  defp files(_many), do: "files"
end
