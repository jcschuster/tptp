# Corpus report

Every problem and axiom file of a local TPTP library, read with
`Tptp.from_string/2` and nothing else — no `include` resolved, no lint rule run.
A file counts as parsed when the result carries no error-severity diagnostic;
warnings do not count against it.

A file that did not parse is listed below with the diagnostic code that refused
it, because "did not parse" and "is not TPTP" are different claims and only the
code says which one this is. Where the answer is known it is written out below
the table, once per explanation rather than once per file, and it disappears
from the report along with the failures it explains.

Regenerate with `mix tptp.corpus`; `mix tptp.corpus --check` fails if the
results below have gone stale against the library on this machine. The nightly
workflow sweeps a freshly downloaded release and keeps its own report as an
artifact, because a count taken from one snapshot of the library says nothing
about another.

## Against the previous toolchain

The measurement this replaces ran the TH0/TH1 problem set — 5109 problems as it
counted them — through the toolchain that preceded this library, and recorded
**628** files that exceeded its parse budget and **221** it could not parse.
Those are the two numbers the `Timed out` and `Failed` columns below are to be
read against. The comparison is of coverage, not of speed: the budget, the
machine and the TPTP release are not the same.

<!-- results -->

## Results

| Set | Files | Parsed | Failed | Timed out |
|---|---:|---:|---:|---:|
| Problems | 26925 | 26921 | 4 | 0 |
| Axioms | 2433 | 2433 | 0 | 0 |
| Total | 29358 | 29354 | 4 | 0 |

The TPTP names a problem's form in its file name, and `^` marks a THF problem:
5279 of the 26925 problems swept are named that way. That is
a fact about the names rather than about the contents — only
`Tptp.Query.dialect/1` answers that — and it is here because the TH0/TH1 set is
what the comparison above is over.

### What did not parse

| File | Why |
|---|---|
| `SYN000+2.p` | TPTP0301 |
| `SYN000-2.p` | TPTP0301 |
| `SYN000^2.p` | TPTP0301 |
| `SYN000_2.p` | TPTP0301 |

**`SYN000+2.p`, `SYN000-2.p`, `SYN000^2.p`** use `theory(equality)` as an inference parent, which `<source>` has not derived since v9.3.1.2 replaced `<source> ::= <general_term>` with a list of alternatives. Fixed upstream on 10/09/26 — see <https://tptp.org/TPTP/Distribution/BuggedProblems-v9.3.1.txt> — and the three parse once that edit reaches the distributed tarball. They are the same demonstration of the annotated-formula syntax written once per dialect, and all three carry the same two statements.

**`SYN000_2.p`** writes `introduced(assumption,[from,the,world,[]])`, which is `introduced(<intro_type>,<useful_info>)` where both the BNF and the TPTP language page state `introduced(<intro_type>,<useful_info>,<parents>)`. The bracket belongs one place to the left: the other three dialects' copies of this file write `introduced(assumption,[from,the,world],[])`. Distinct from, and not covered by, the `theory(equality)` fix of 10/09/26 — this file carries both, and the second was reachable only once the first was resolved. Reported upstream on 2026-09-11.
<!-- end results -->

## This run

| | |
|---|---|
| TPTP | v9.3.1, at `/opt/TPTP` |
| Elixir | 1.20.4 |
| OTP | 28 |
| Schedulers | 8 |
| Workers | 8 on 28125, 4 on 913, 2 on 320 |
| Heap ceiling | 6.0 GB |
| Per-file budget | 60.0 s |
| Size cap | 19.1 MB |
| Thinning | none — every file |
| Wall clock | 886.5 s |
| Read | 5428.1 MB |
| Throughput | 6.1 MB/s |

### Slowest files

| File | Bytes | ms |
|---|---:|---:|
| `SWV536-1.010.p` | 8504170 | 13420.2 |
| `SYN854-1.p` | 16214076 | 13409.3 |
| `SYN852-1.p` | 16425608 | 13076.6 |
| `SYN853-1.p` | 16223754 | 12997.9 |
| `SYN839-1.p` | 14596647 | 12226.2 |
| `SWV545-1.010.p` | 8504445 | 12185.7 |
| `SWV535-1.010.p` | 8504216 | 12024.3 |
| `SWV546-1.010.p` | 8504178 | 12022.8 |
| `SYN841-1.p` | 14703297 | 11822.9 |
| `SYN855-1.p` | 15651631 | 11616.7 |
