# tptp

A faithful, span-carrying parser, linter and printer for the [TPTP][tptp] language,
generated from the official BNF.

Zero runtime dependencies. `yecc` and `:crypto` ship with OTP and the lexer is
hand-written, so this package is trivially vendorable by anyone who wants it.

```elixir
def deps do
  [{:tptp, "~> 0.1"}]
end
```

## What it does

1. **Scan** TPTP bytes into tokens with byte-accurate spans.
2. **Split** the token stream into statements, so one bad statement does not poison
   the file.
3. **Parse** each statement into a CST whose node tags are BNF nonterminals.
4. **Resolve** `include` directives against a pluggable resolver — the local
   filesystem under `$TPTP_ROOT`, or tptp.org over HTTP — with cycle detection.
5. **Validate** the `:==` semantic layer and the cross-statement conditions.
6. **Print** a CST back to TPTP: canonical, pretty, or format-preserving.
7. **Read** the SZS status lines a prover prints, over a generated ontology of the
   112 published status values.

## What it does not do

It does not type-check, does not normalise, does not know what `&` means, and has
no notion of a logic.

TPTP's typed dialects declare every symbol and annotate every bound variable, so
there is no inference problem at this layer and none is attempted. Explicit type
arguments are recorded verbatim, in source order, with spans — `f @ $i @ a` keeps
its `$i` as an ordinary argument — so a consumer never has to reconstruct them.

It follows that the CST **cannot distinguish a THF type from a THF term**, and does
not try. `<thf_unitary_type> ::= <thf_unitary_formula>` makes them the same
nonterminal; only the `:==` layer says which formulae are legal types. That
distinction belongs to elaboration, with a signature in hand.

## What it reads

Every problem and axiom file of a complete TPTP v9.3.1 — all four dialects, not a
subset — through the parser alone, no `include` resolved and no lint rule run:

| Set | Files | Parsed | Failed | Timed out |
|---|---:|---:|---:|---:|
| Problems | 26925 | 26921 | 4 | 0 |
| Axioms | 2433 | 2433 | 0 | 0 |
| Total | 29358 | 29354 | 4 | 0 |

5.4 GB in about eleven minutes on sixteen workers, with a 60-second per-file budget
that nothing reached. The toolchain this replaces recorded **628 timeouts and 221
parse failures** over the TH0/TH1 subset alone; this one has none of the first and
four of the second over five times as many files.

Those four are `SYN000-2.p`, `SYN000+2.p`, `SYN000_2.p` and `SYN000^2.p` — the
annotated-formula demonstration written once per dialect — and they fail for one
reason. Each uses `theory(equality)` as an inference parent. v9.3.1.2 expanded
`<source> ::= <general_term>` into a list of alternatives and `theory(...)` is not
among them, so the shipped grammar does not admit it — a gap between the BNF release
and the library rather than a parser gap, and this parser is generated from the BNF.
The same kind of gap as the `logic` role and the `$modal_system_KB` modality that
the lint gate reports on the modal problems.

The 65 problems over 20 MB, all `HWV`, are read by `stream_file!/2` rather than by
this sweep; the size cap is a property of the report, not of the parser.

`mix tptp.corpus` writes [CORPUS.md](CORPUS.md), which is where those numbers come
from and what the nightly workflow rewrites.

## The grammar is generated

Four files are generated from two vendored sources and **committed**, so installing
needs no Python, no awk, no BNF and no network:

| Generated | From |
|---|---|
| `src/tptp_parser.yrl` | `priv/bnf/SyntaxBNF-v9.3.1.2` |
| `lib/tptp/bnf/vocabulary.ex` | the same, `:==` rules |
| `lib/tptp/printer/shapes.ex` | the same, `::=` rules |
| `lib/tptp/szs/ontology.ex` | `priv/szs/SZSOntology-2026-08-31.html` |

Regeneration is a maintainer action taken on a TPTP release, and the diff *is* the
review of that release.

```
mix tptp.gen           # regenerate all four
mix tptp.gen --check   # fail if any committed output is stale
```

The generator reports its three departures from a mechanical translation, each of
which would otherwise be an LALR(1) conflict. See `Tptp.Bnf.Generator` for why. It
also cross-checks the two vendored files against each other: every `<status_value>`
the BNF admits inside a `status(...)` annotation must be a success-ontology
mnemonic, and all 34 are.

The SZS `isa` hierarchy is **not** modelled. It is published only as three diagrams,
so `Tptp.Szs.Ontology` offers the partition the text states and no `parent/1` — see
its documentation for why a transcription would be the wrong kind of guess, and for
what a consumer that has to rank two prover answers should use instead of inventing
a precedence.

Two version numbers, and they are not the same: `Tptp.bnf_version/0` is the TPTP
BNF the shipped parser was generated from; the package version is semver over the
Elixir API.

## A tour

`examples/demo.livemd` is a Livebook covering the whole surface — parsing,
diagnostics, the three printers, includes, lint, SZS and the statement stream — in
about twenty cells. Open it in Livebook, or read it as markdown.

## Development

```
mix test               # unit and property tests
mix test --include corpus
mix test --include network   # re-checks the vendored files against tptp.org
mix check              # format, compile --warnings-as-errors, credo, test, dialyzer
mix run bench/parse.exs
mix tptp.corpus        # sweep a local TPTP library, rewrite CORPUS.md
```

CI runs `mix check`'s stages as one job and Dialyzer as another, so the PLT is
cached on its own key and a lock-file change does not rebuild it. A third workflow
regenerates the four generated files and fails if the working tree is not clean,
which is what keeps "generated but committed" from quietly becoming "hand-edited".

A fourth reads the library. On a pull request it sweeps one file in five, which is
what fits; nightly it sweeps every one of them, because a check that skips four
files in five is a check that never looks at four fifths of the library. Set
`$TPTP_CORPUS_FULL=1` to run the corpus tests that way locally.

### The benchmark ladder

`bench/parse.exs` runs each stage over 1 KB, 100 KB, 1 MB and 4.5 MB inputs and
reports **allocation beside throughput**, because this library's design is mostly a
set of allocation decisions and a time-only number would report every one of them as
fine right up until it regressed.

The last rung is a gate rather than a measurement: `Axioms/CSR002+5.ax` is 455 MB,
about 75 million tokens, which as 3-tuples would be roughly 2.4 GB. It is streamed
with the baseline taken *after* the source binary is read, so what the last line
reports is not the cost of the file — that is unavoidable — but whether the token
stream was materialised alongside it.

On a Ryzen 7 3700X, OTP 28 / Elixir 1.20.3, the gate reads:

```
statements  3341977
elapsed     19.0 s
peak heap above the loaded file    238.1 KB
```

3.3 million statements out of a 455 MB file, with a quarter of a megabyte of live
heap above the source. Everything below it scales linearly: end to end, `from_string`
is about 4 MB/s and allocates roughly 75× the source, which is the CST — spans,
sub-binaries and all — and is why `stream_string!/1` exists for anything large.

### The lexer has a second opinion

The lexer is the only stage not derived from the BNF, so `mix tptp.gen` also writes
`test/support/bnf_oracle.ex`: all 56 `::-` and `:::` rules transcribed into anchored
regular expressions. The property it supports is not "the lexer matches the BNF" but
the sharper one — **every token the lexer emits without complaint satisfies its BNF
pattern**, so a departure is allowed only when the lexer reports it. There are
exactly two, both warnings: an empty quoted atom (`''`, which `<single_quoted>`
forbids where `<distinct_object>` allows `""`) and a redundant leading zero (`00`,
`-007`, `1/02`).

Every module carries a `@moduledoc`, every public function a `@doc` and every type
a `@typedoc`; `test/tptp/documentation_test.exs` enforces that from the docs chunk
rather than trusting review. There are no code comments — the rationale is in the
published documentation, where consumers see it.

`mix credo --strict` includes a custom check forbidding `String.to_atom/1` and
friends. Atoms are never garbage collected and the table holds about a million; a
library that reads tens of thousands of untrusted files must not create them from
input. That is a security property, so it is enforced mechanically rather than
remembered.

## Licence

This library is MIT licensed. See [LICENSE](LICENSE).

Two files it redistributes are not. `priv/bnf/SyntaxBNF-v9.3.1.2` is the text of
[the TPTP syntax page][bnf] and `priv/szs/SZSOntology-2026-08-31.html` is [the SZS
ontology page][szs], both carried unmodified so that installing needs no network
access. The TPTP's own terms permit that:

> The TPTP is copyrighted 1993-onwards, by Geoff Sutcliffe & Christian Suttner.
> Verbatim redistribution of the TPTP and parts of the TPTP is permitted provided
> that the redistribution is clearly attributed to the TPTP. Distribution of any
> modified version or modified part of the TPTP requires permission.

Nothing here edits either file. See [NOTICE](NOTICE) for the attribution and the
digests, and [tptp.org][tptp] for the TPTP itself.

[bnf]: https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html
[szs]: https://tptp.org/UserDocs/SZSOntology

[tptp]: https://www.tptp.org
