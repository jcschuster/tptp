# tptp

A span-preserving parser, linter and printer for the [TPTP][tptp] language,
generated from the published BNF.

No runtime dependencies. `yecc` and `:crypto` are supplied by OTP and the lexer is
hand-written, so the package is straightforward to vendor.

```elixir
def deps do
  [{:tptp, "~> 0.1"}]
end
```

## Function

1. **Scan** TPTP source into tokens with byte-accurate spans.
2. **Split** the token stream into statements, bounding the effect of malformed
   input to a single statement.
3. **Parse** each statement into a concrete syntax tree whose node kinds are BNF
   nonterminals.
4. **Resolve** `include` directives against a pluggable resolver — the local
   filesystem under `$TPTP_ROOT`, or tptp.org over HTTPS — with cycle detection.
5. **Check** the `:==` well-formedness conditions and the cross-statement
   conditions.
6. **Print** a tree back to TPTP: canonical, pretty, or format-preserving.
7. **Read** the SZS status lines emitted by ATP systems, over an ontology of the
   112 published values.

## Scope

The library performs no type checking, no normalisation and no elaboration, and
attaches no semantics to the operators it recognises.

THF requires a declaration for every symbol and a type on every bound variable, and
the first-order typed dialects fix a default for whatever they leave out — `$i` for
an untyped variable, `($i * ... * $i) > $i` or `> $o` for an undeclared function or
predicate — so no type inference is required to read any of them, and none is
performed. Explicit type arguments are recorded verbatim, in source
order and with spans: in `f @ $i @ a` the `$i` is retained as an argument of the
application.

It follows that the tree does not distinguish a THF type from a THF term. The
grammar does not either: `<thf_unitary_type> ::= <thf_unitary_formula>` identifies
the two nonterminals, and the `:==` conditions are what restrict a formula to those
admissible as types. Elaboration against a signature belongs to the consumer.

## Analysis

An editor integration requires the file, its diagnostics, the symbol table and the
dialect on each edit. `Tptp.analyze/2` produces all four as a `Tptp.Analysis` from
a single traversal, `Tptp.Lint.scan/2`, of which `Tptp.Lint.run/2`, `run_unit/2`
and `table/1` are projections.

Conversion of byte offsets to line and column is excluded from that traversal, since
an analysis that is never rendered should not incur a scan of the source and one
rendering many positions should incur it once. `with_line_index/1` performs it.

Input that does not parse still yields an analysis carrying the diagnostics that
record the failure, since an editor must render markers for a buffer it cannot
parse.

`Tptp.Analyzer` is the underlying behaviour: a named producer of diagnostics over
an analysis, declaring the dialects it applies to. `Tptp.Lint` implements it as
`:tptp_lint`; a prover-backend probe or a project naming convention would be other
implementations. `Tptp.Analyzer.run_all/3` dispatches by dialect and distinguishes
two outcomes that are easily conflated: an analyzer excluded by dialect reports
`:skipped` rather than an empty list. An analyzer that raises is contained as a
`TPTP0800` diagnostic naming it.

## Coverage

Every problem and axiom file of a complete TPTP v9.3.1, across all dialects,
through the parser alone: no `include` resolved and no lint rule applied.

| Set | Files | Parsed | Failed | Timed out |
|---|---:|---:|---:|---:|
| Problems | 26925 | 26921 | 4 | 0 |
| Axioms | 2433 | 2433 | 0 | 0 |
| Total | 29358 | 29354 | 4 | 0 |

5.4 GB in 887 seconds on eight workers, under a 60-second per-file budget that
no file reached. The preceding toolchain recorded 628 timeouts and 221 parse
failures over the TH0/TH1 subset alone.

The four failures are `SYN000-2.p`, `SYN000+2.p`, `SYN000_2.p` and `SYN000^2.p`,
the annotated-formula demonstration written once per dialect, and they are defects
in the files rather than in the parser. Three use `theory(equality)` as an inference
parent, which `<source>` has not derived since v9.3.1.2 replaced
`<source> ::= <general_term>` with a list of alternatives; that was
[fixed upstream][bugged] on 10/09/26 and the three parse once the edit reaches the
distributed tarball. `SYN000_2.p` carries a second, independent one — it writes
`introduced(assumption,[from,the,world,[]])` where both the BNF and the language
page state `introduced(<intro_type>,<useful_info>,<parents>)`, the other three
dialects' copies writing `introduced(assumption,[from,the,world],[])`.
[CORPUS.md](reports/CORPUS.md) carries the citation for each.

The TPTP is this library's ground truth: where the two disagree, the parser is
incorrect, being generated from the published BNF, and correcting it by hand would
make it a parser for something else. Where the published sources disagree with each
other — the grammar rejecting a file the TPTP distributes, or one page contradicting
another — the disagreement is reported upstream rather than worked around. Six such
disagreements were carried here through 0.1.0; BNF v9.3.1.3 and the SZS ontology's
move to [szs.tptp.org][szs] resolve all of them, and the register that held them is
gone with them.

The 65 problems above 20 MB — 64 `HWV` and `LCL680+1.020.p`, 3.7 GB between them —
are read by `stream_file!/2` rather than by this sweep. The size limit is a property
of the report rather than of the parser.

[FINDINGS.md](reports/FINDINGS.md) records what the four failures were hiding from
the stages after the parser, and what a sweep of the library turned up once they
were patched out of a copy: two further defects in those files, and three rules of
this library's that were wrong.

`mix tptp.corpus` writes [CORPUS.md](reports/CORPUS.md), from which these figures are taken
and which the nightly workflow regenerates. `mix tptp.census` writes
[CENSUS.md](reports/CENSUS.md), recording where the library applies a type constructor and
in which dialects — a question about the corpus rather than the parser, and one an
elaborator built on this library must answer.

## Generated sources

Four files are generated from the vendored BNF and committed, so installation
requires neither Python, nor awk, nor the BNF, nor network access:

| Generated | From |
|---|---|
| `src/tptp_parser.yrl` | `priv/bnf/SyntaxBNF-v9.3.1.3` |
| `lib/tptp/bnf/vocabulary.ex` | the same, `:==` rules |
| `lib/tptp/printer/shapes.ex` | the same, `::=` rules |
| `test/support/bnf_oracle.ex` | the same BNF, `::-` and `:::` rules |

Regeneration is a maintainer action performed on a TPTP release, and the resulting
diff constitutes the review of that release.

```
mix tptp.gen           # regenerate all four
mix tptp.gen --check   # fail if any committed output is stale
```

The generator reports its four departures from a mechanical translation, each of
which would otherwise constitute an LALR(1) conflict. The list is produced by
`Tptp.Bnf.Generator.departures/0` from the constants causing it, so a release
requiring a fifth is reported rather than absorbed silently.

`lib/tptp/szs/ontology.ex` is **not** generated. The SZS ontology is a prose page
of 112 entries that changes rarely, so it is transcribed by hand and edited when
the page changes; the module records why, and `NOTICE` attributes the descriptions
quoted from the page. The cross-check the generator used to perform is a test:
every `<status_value>` the BNF admits within a `status(...)` annotation must be a
success-ontology mnemonic. All 34 are.

The SZS `isa` hierarchy is not modelled. It is published only as three diagrams, so
`Tptp.Szs.Ontology` provides the partition the text states and no `parent/1`. Its
documentation sets out why transcribing a diagram would introduce unverifiable
relations, and what a consumer comparing two prover results should use instead.

`Tptp.bnf_version/0` reports the TPTP BNF release the shipped parser was generated
from. It is distinct from the package version, which is semantic versioning over the
Elixir API.

## Command line

Two of the library's functions are available without writing Elixir.

```
mix tptp.lint Problems/PUZ/PUZ001+1.p        # diagnostics as path:line:column
mix tptp.lint --include --severity warning "Problems/SYN/*.p"
mix tptp.lint --format json --only TPTP0501 problem.p
mix tptp.format --check "Axioms/**/*.ax"     # layout only; the tokens are unchanged
```

`mix tptp.lint` prints `path:line:column: severity: message [CODE]` and exits
non-zero where any diagnostic at or above `--severity` was reported. `--include`
resolves the include graph first, under which the undeclared-symbol rule and the
conjecture count can be correct for a problem whose signature is supplied by an
axiom set.

## Example

`examples/demo.livemd` is a Livebook covering parsing, diagnostics, the three
printers, includes, lint, SZS and the statement stream in approximately twenty
cells. Open it in Livebook, or read it as Markdown.

## Development

```
mix test               # unit and property tests
mix test --include corpus
mix test --include network   # re-checks the vendored files against their pages
mix check              # format, compile --warnings-as-errors, credo, test, dialyzer
mix run bench/parse.exs
mix tptp.corpus        # sweep a local TPTP library, rewrite reports/CORPUS.md
mix tptp.census        # the same library's type applications, rewrite reports/CENSUS.md
```

Both sweeps parse each file in a separate process under a `max_heap_size` ceiling,
since a file's size does not predict the cost of parsing it: across the library the
source ranges from 2.5 to 111 bytes per tree node, so `SWV535-1.010.p` peaks at
3.2 GB from 8 MB while a file twice its size peaks at a ninth of that. `--heap` is
the total across all workers, and a parse exceeding its share is retried alone.

CI runs the stages of `mix check` as one job and Dialyzer as another, so the PLT is
cached under its own key and a lock-file change does not rebuild it. A third
workflow regenerates the generated files and fails if the working tree is not
clean, which is what prevents a generated file from being hand-edited.

A fourth workflow reads the library. On a pull request it sweeps one file in five;
nightly it sweeps every file, since a check skipping four files in five examines
four fifths of nothing. Set `$TPTP_CORPUS_FULL=1` to run the corpus tests that way
locally.

### Benchmarks

`bench/parse.exs` runs each stage over 1 KB, 100 KB, 1 MB and 4.5 MB inputs and
reports allocation alongside throughput. The design of this library is largely a
set of allocation decisions, and a timing alone would report a regression in any of
them as acceptable until memory ran out.

The final rung is a bound rather than a measurement. `Axioms/CSR002+5.ax` is
455 MB, approximately 75 million tokens, which as three-tuples would occupy roughly
2.4 GB. It is streamed with the baseline taken after the source binary is read, so
the figure reported is not the cost of the file, which is unavoidable, but whether
the token stream was materialised alongside it.

On a Ryzen 7 3700X under OTP 28 and Elixir 1.20.3:

```
statements  3341977
elapsed     19.0 s
peak heap above the loaded file    238.1 KB
```

3.3 million statements from a 455 MB file, with a quarter of a megabyte of live
heap above the source. The remaining rungs scale linearly: end to end,
`from_string` runs at approximately 4 MB/s and allocates roughly 75 times the size
of the source, that being the tree, which is why `stream_string!/1` exists for
larger input.

### Lexer verification

The lexer is the only stage not derived from the BNF, so `mix tptp.gen` also writes
`test/support/bnf_oracle.ex`: the 56 `::-` and `:::` rules transcribed into
anchored regular expressions. The property asserted is not that the lexer matches
the BNF but that every token the lexer emits without a diagnostic satisfies its BNF
pattern, so a departure is admissible only where the lexer reports it. There are
two, both warnings: an empty quoted token, which `<single_quoted>` and — since
v9.3.1.3 — `<distinct_object>` both forbid, and a redundant leading zero, as in
`00`, `-007` and `1/02`.

### Documentation and static analysis

Every module carries a `@moduledoc`, every public function a `@doc` and every type
a `@typedoc`. `test/tptp/documentation_test.exs` enforces this from the compiled
docs chunk rather than by review. Rationale a consumer requires belongs in the
published documentation; the library is accordingly close to free of code comments,
the exceptions being the sweep scheduler and the generators, where what requires
explanation is the shape of an implementation rather than the behaviour of an API.

`mix credo --strict` includes a custom check prohibiting `String.to_atom/1` and its
equivalents. Atoms are never collected and the table is bounded at approximately one
million, so a library reading tens of thousands of untrusted files must not create
them from input. This is a security property and is enforced mechanically.

## Licence

This library is MIT licensed. See [LICENSE](LICENSE).

Redistributed TPTP material is not. `priv/bnf/SyntaxBNF-v9.3.1.3` is the text of
[the TPTP syntax page][bnf], carried unmodified so that installation requires no
network access, and `lib/tptp/szs/ontology.ex` quotes the value descriptions from
[the SZS ontology page][szs]. The TPTP's terms permit this:

> The TPTP is copyrighted 1993-onwards, by Geoff Sutcliffe & Christian Suttner.
> Verbatim redistribution of the TPTP and parts of the TPTP is permitted provided
> that the redistribution is clearly attributed to the TPTP. Distribution of any
> modified version or modified part of the TPTP requires permission.

Neither is modified. See [NOTICE](NOTICE) for the attribution and the digest, and
[tptp.org][tptp] for the TPTP itself.

[bnf]: https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html
[szs]: https://szs.tptp.org
[bugged]: https://tptp.org/TPTP/Distribution/BuggedProblems-v9.3.1.txt

[tptp]: https://www.tptp.org
