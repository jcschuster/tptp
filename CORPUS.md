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

**`SYN000+2.p`, `SYN000-2.p`, `SYN000^2.p`, `SYN000_2.p`** use `theory(equality)` as an inference parent. v9.3.1.2 expanded `<source> ::= <general_term>` into a list of alternatives and `theory(...)` is not among them, so the shipped grammar does not admit it. A gap between the BNF release and the library, not a parser one. These are the same demonstration of the annotated-formula syntax written once per dialect, and all four carry the same two statements.
<!-- end results -->

## This run

| | |
|---|---|
| TPTP | v9.3.1, at `/opt/TPTP` |
| Elixir | 1.20.3 |
| OTP | 28 |
| Schedulers | 16 |
| Workers | 16 |
| Per-file budget | 60.0 s |
| Size cap | 19.1 MB |
| Thinning | none — every file |
| Wall clock | 531.6 s |
| Read | 5428.1 MB |
| Throughput | 10.2 MB/s |

### Slowest files

| File | Bytes | ms |
|---|---:|---:|
| `SYN842-1.p` | 16140604 | 43535.5 |
| `SYN852-1.p` | 16425608 | 39880.3 |
| `SYN839-1.p` | 14596647 | 39492.3 |
| `SYN841-1.p` | 14703297 | 39452.2 |
| `SYN840-1.p` | 14533552 | 37961.6 |
| `SYN854-1.p` | 16214076 | 37928.4 |
| `SYN853-1.p` | 16223754 | 37210.5 |
| `SYN855-1.p` | 15651631 | 37120.5 |
| `SWV535-1.010.p` | 8504216 | 37048.2 |
| `SWV546-1.010.p` | 8504178 | 36621.1 |
