# Corpus report

Every problem and axiom file of a local TPTP library, read with
`Tptp.from_string/2` and nothing else — no `include` resolved, no lint rule run.
A file counts as parsed when the result carries no error-severity diagnostic;
warnings do not count against it.

A file that did not parse is listed below with the diagnostic code that refused
it, because "did not parse" and "is not TPTP" are different claims and only the
code says which one this is.

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
| Problems | 26988 | 26988 | 0 | 0 |
| Axioms | 2409 | 2409 | 0 | 0 |
| Total | 29397 | 29397 | 0 | 0 |

The TPTP names a problem's form in its file name, and `^` marks a THF problem:
5279 of the 26988 problems swept are named that way. That is
a fact about the names rather than about the contents — only
`Tptp.Query.dialect/1` answers that — and it is here because the TH0/TH1 set is
what the comparison above is over.

Every file parsed.
<!-- end results -->

## This run

| | |
|---|---|
| TPTP | v10.0.0, at `/home/johannes/Documents/TPTP-v10.0.0` |
| Elixir | 1.20.5 |
| OTP | 29 |
| Schedulers | 16 |
| Workers | 16 on 28164, 8 on 913, 4 on 320 |
| Heap ceiling | 6.0 GB |
| Per-file budget | 60.0 s |
| Size cap | 19.1 MB |
| Thinning | none — every file |
| Wall clock | 699.9 s |
| Read | 5428.5 MB |
| Throughput | 7.8 MB/s |

### Slowest files

| File | Bytes | ms |
|---|---:|---:|
| `SWV546-1.010.p` | 8504179 | 9170.7 |
| `SWV536-1.010.p` | 8504185 | 9052.8 |
| `SWV535-1.010.p` | 8504231 | 8719.0 |
| `SWV545-1.010.p` | 8504460 | 8550.9 |
| `HWV090-1.p` | 17987772 | 8250.8 |
| `SYN852-1.p` | 16425609 | 8176.3 |
| `SYN812-1.p` | 9894072 | 8052.7 |
| `HWV108-1.p` | 16639967 | 7905.6 |
| `SYN853-1.p` | 16223769 | 7830.5 |
| `SYN854-1.p` | 16214077 | 7825.5 |
