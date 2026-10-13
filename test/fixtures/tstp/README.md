# TSTP and SZS fixtures

Prover output cannot be invented. Every shape the readers in `Tptp.Szs` and
`Tptp.Tstp` tolerate is a shape some system actually prints, so the fixtures here
are captures rather than examples, and this file records where each one came from.
It covers the two fixtures under `../szs/` added at the same time as well.

All captures were made on **2026-10-13** against TPTP v9.3.1 on `tptp.org`.
Nothing in a file was edited by hand except where "synthetic" says otherwise.

## How the captures were taken

Two endpoints, neither of which serves plain text:

* **SystemOnTPTP** — a `POST` to `https://tptp.org/cgi-bin/SystemOnTPTPFormReply`
  with the fields the form at `https://tptp.org/cgi-bin/SystemOnTPTP` carries:
  `ProblemSource=TPTP`, `TPTPProblem=<problem>`, `QuietFlag=-q01`,
  `SubmitButton=RunSelectedSystems`, `System___<system>=<system>`, and that
  system's own `TimeLimit___`, `Transform___`, `Format___` and `Command___`
  defaults. `X2TPTP=-S` is added where the table below says so.
* **SeeTPTP** — a `GET` with `Category=Solutions&Domain=…&File=…&System=…`.

Both reply with an HTML page wrapping the text in a single `<pre>`, and SeeTPTP
has no raw mode: `&Quiet=1`, `&Format=raw`, `&NoHTML=1` and `&Raw=1` all return
the same page. So each capture went through the same three steps, and nothing
else:

1. take the contents of the one `<pre>` element,
2. undo HTML entity escaping (`&lt;` back to `<`, and so on),
3. drop the `<A …>` and `</A>` tags SeeTPTP injects — it names every statement
   with `<A NAME="c_0_7"></A>` and turns every parent name in an `inference`
   record into `<A HREF="#c_0_7">c_0_7</A>`. The tags are dropped and their text
   kept; no TPTP token spells `<A` or `</A`.

What is left is the file as the system wrote it, including the SystemOnTPTP
wrapper lines (`% START OF SYSTEM OUTPUT`, `% RESULT:`, `% OUTPUT:`) that a
client receives with it, and including trailing white space.

## The fixtures

| File | Live? | Source |
|---|---|---|
| `E---3.5.1.THM-CRf.s` | live | SeeTPTP, `Category=Solutions&Domain=PUZ&File=PUZ001+1&System=E---3.5.1.THM-CRf.s`. The TSTP library's archived solution: a `% Key : value` header, E's CNF refutation of `PUZ001+1`, then `%----ORIGINAL SYSTEM OUTPUT` with E's own output behind a `% ` and StarExec's `0.12/0.45` stamps. Its header states 54 formulae and 11 leaves, which the tests assert. Run on StarExec for CASC, 2026-09-24. |
| `e_cnfrefutation_x2tptp.txt` | live | SystemOnTPTP, `E---3.5.1` on `PUZ001+1`, `X2TPTP=-S`; `TimeLimit=60`, `Transform=none`, `Format=tptp:raw`, `Command=run_E %s %d THM`. A TSTP solution file built on the spot, same shape as the archived one but with `% ` as the only prefix. |
| `e_cnfrefutation_raw.txt` | live | The same submission without `X2TPTP`: E's own output, with the nested `inference(sr,[…],[inference(spm,…)])` records that the `X2TPTP` form flattens. |
| `vampire_proof_raw.txt` | live | SystemOnTPTP, `Vampire---5.0.1` on `PUZ001+1`, no `X2TPTP`; `Command=run_vampire %s %d THM`. An AVATAR proof: `sat_conversion`, `avatar_sat_refutation`, and clauses over splitting literals. |
| `e_saturation_raw.txt` | live | SystemOnTPTP, `E-SAT---3.5.1` on `KRS018+1` (status `Satisfiable`), no `X2TPTP`; `Command=run_E %s %d SAT`. A `Saturation` block: every statement carries `['final']`, none derives `$false`, and the parents named are clauses the block does not contain. |
| `../szs/paradox_finite_model.txt` | live | SystemOnTPTP, `Paradox---4.0` on `KRS018+1`, no `X2TPTP`; `Format=tptp:short`, `Command=paradox --no-progress --time %d --tstp --model %s`. Paradox writes its `SZS status` and `SZS output start|end FiniteModel` lines with no comment character at all, which is the only place the library sees that form. |
| `../szs/starexec_e_proof_synthetic.txt` | **synthetic prefix** | The lines are `e_cnfrefutation_raw.txt` verbatim, from `% Proof found!` to just past the block's end. The StarExec stamp (`0.08/0.13\t`, rising down the file) was added by this repository. No live capture can supply one: tptp.org serves StarExec-stamped output only inside an archived solution's `%----ORIGINAL SYSTEM OUTPUT`, and the TSTP's tooling lifts the solution out of it, leaving `% SZS output start …` followed by `% See solution above` and no end marker — checked on 2026-10-13 against `E---3.5.1.THM-CRf.s` and the `Paradox---4.0`, `Mace4---2026-6A` and `DarwinFM---1.4.5` model solutions of `KRS018+1`, all four of which have one start marker and no end marker. `../szs/starexec_e_theorem.txt` is a genuine StarExec capture and holds no block either. Only the prefix is invented, and both forms it takes are covered: a tab after the stamp, as in that capture, and `% ` before it, as in an archived solution. |

## If a capture has to be repeated

Use `https://tptp.org/…`, not `www.tptp.org/…`: the `www` host answers every
`/cgi-bin/` path with a Google Sites 404 page. The system names carry versions
(`E---3.5.1`), so a later TPTP release may need the names the form then lists,
and a solution file's `System=` name may differ from the one above; the problem's
Solutions page is what lists the current ones.
