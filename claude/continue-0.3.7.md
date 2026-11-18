# Continue: 0.3.7 (temporary — delete before committing)

State on 2026-11-18. HEAD is `60db9f7` (release 0.3.6). Uncommitted, not in the
CHANGELOG, version still 0.3.6.

## Done, uncommitted

- `Tptp.Resolver.Http.preformatted/1` finds `<pre>` and `</pre>` with two short
  matches instead of `~r{<pre>\r?\n?(.*?)</pre>}is`. The lazy `.*?` raised
  `SystemLimitError` (PCRE `:match_limit`) on blocks over ~10 M characters: the
  six files just under SeeTPTP's 10 MiB display limit.
- Test `a block of more than ten million characters is unwrapped` in
  `test/tptp/resolver_test.exs`: fails on 0.3.6 with that error, passes now.
- 940 tests pass; format, `credo --strict`, dialyzer clean.

## Live comparison against TPTP v10.0.0, byte for byte

| Sample | Result |
| --- | --- |
| 400 random files < 8 MB | 400/400 identical |
| 100 files containing `"` | 100/100 identical |
| all 124 files 8 MB – 200 MB, including the six | 124/124 identical, 3.8 GB |
| 150 nested axiom files by bare name | 110 identical, 40 × 404 (bug 1) |
| 4 files > 200 MB | not run |

The four not run: `Axioms/CSR002+5.ax` (477 MB), `Problems/HWV/HWV132-1.p`,
`HWV133-1.p`, `HWV134-1.p` (~278 MB each).

## Open

1. **Bare names in `Axioms/ITP001/` mostly 404.** The bare-name fallback tries
   `Axioms/<first six chars>/`, right for `SET007/` but `ITP001/` holds 147
   prefixes (`ITP009^7.ax`, `ITP090+5.ax`, …). Full paths
   (`Axioms/ITP001/ITP009^7.ax`, the form TPTP's own includes use) work. The only
   two nested directories in v10.0.0 are `SET007/` and `ITP001/`. Decide: also
   try `Axioms/ITP001/` for an `ITP` name, or another rule.
2. **seetptp.tptp.org rate-limits.** About five quick requests, then
   `429 Too Many Requests` for ~30 s, no `Retry-After`. Requests 5 s apart all
   succeeded. The resolver reports 429 as an error and does not retry (its
   moduledoc says it never retries). A parallel index run will hit this. Decide:
   leave it to the caller, or wait and retry on 429 only.
3. Run the four files > 200 MB (memory: the archive and the file are both held).
4. CHANGELOG entry for the `SystemLimitError` fix, then release 0.3.7 as before
   (version in `mix.exs`, `CITATION.cff`, `.zenodo.json`,
   `.github/ISSUE_TEMPLATE/bug.yml`; `## [0.3.7]` section and compare links).

## Rerunning the comparison

Scratchpad (may be gone after a reboot):
`/tmp/claude-1000/-workspace/f0396d4e-82f4-400e-bb98-2d52794745af/scratchpad`

- `dist/TPTP-v10.0.0.tgz` and unpacked `dist/x/TPTP-v10.0.0/`
  (from <https://tptp.org/TPTP/Distribution/TPTP-v10.0.0.tgz>, 934 MB)
- `dist/sizes.txt`: `<bytes> <path>` for all 29,467 files
- `set_*.txt`: the samples above; `set_huge.txt` is the four > 200 MB
- `cache-a/v2/`: 713 cached files from the run, so a rerun skips them

Run one set with one worker (more trips the 429s):

```sh
S=/tmp/claude-1000/-workspace/f0396d4e-82f4-400e-bb98-2d52794745af/scratchpad
MIX_ENV=prod mix run $S/scripts/compare.exs $S/dist/x/TPTP-v10.0.0 \
  $S/set_huge.txt $S/cache-a path 1
```

`path` passes the library path as the name, `bare` only its basename. Delete
`cache-a` to fetch afresh. If the scratchpad is gone, the script:

```elixir
[root, list, cache, mode, workers] = System.argv()

names = list |> File.read!() |> String.split("\n", trim: true)

# Waits out SeeTPTP's 429s: 15 s between tries, 40 tries.
resolve = fn resolve, name, tries ->
  case Tptp.Resolver.Http.resolve(name, nil, cache_dir: cache, timeout: 600_000) do
    {:error, reason} when tries > 0 ->
      if reason =~ "returned 429",
        do: (Process.sleep(15_000); resolve.(resolve, name, tries - 1)),
        else: {:error, reason}

    other ->
      other
  end
end

check = fn path ->
  name = if mode == "bare", do: Path.basename(path), else: path
  expected = File.read!(Path.join(root, path))

  {micros, result} =
    :timer.tc(fn ->
      try do
        resolve.(resolve, name, 40)
      rescue
        e -> {:raised, Exception.format(:error, e, __STACKTRACE__) |> String.slice(0, 300)}
      end
    end)

  verdict =
    case result do
      {:ok, _url, ^expected} -> :equal
      {:ok, _url, got} -> {:differs, byte_size(got), byte_size(expected)}
      other -> other
    end

  {path, byte_size(expected), div(micros, 1000), verdict}
end

results =
  names
  |> Task.async_stream(check,
    max_concurrency: String.to_integer(workers),
    timeout: :infinity,
    ordered: false
  )
  |> Enum.map(fn {:ok, r} -> r end)

{equal, bad} = Enum.split_with(results, &match?({_, _, _, :equal}, &1))
IO.puts("#{Path.basename(list)} (#{mode}): #{length(equal)}/#{length(results)} identical")

for {path, size, ms, verdict} <- bad,
    do: IO.puts("  FAIL #{path} (#{size} bytes, #{ms} ms): #{inspect(verdict)}")
```

The summary line comes before the FAIL lines, so don't pipe through `tail`: last
run's `tail -40` cut the nested set's summary.
