# tptp 0.2.0 — progress and resume notes

Status 2026-10-13, implementation complete and unreleased. Companion to
`tptp-0.2-plan.md`, which is the specification; this file records what is done,
what the implementation found that the plan did not say, and what is left. Both
files are untracked on purpose.

## Where the work stands

Plan section 9's order of work, steps 1–7 of 8 are done, each with `mix check`
green (`format --check-formatted`, `compile --warnings-as-errors`,
`credo --strict`, `test`, `dialyzer`) and committed on `main`. **Only step 8 is
left: the `v0.2.0` tag, which is the user's to make**, with the release and the
publish that follow it.

| Step | Commit | What |
|---|---|---|
| 1 — R5 sub-roles | `1cfd373` | `Annotated.role_word/1`, `subrole/1`; Role/Collect/Query/Context/Inspect routed through them; printer closes a sub-role up on its `-` |
| 2 — R1 bare SZS lines | `54c2e4e` | the three regexes accept `SZS status` / `output start|end` with no comment character |
| 3 — R2 per-line prefixes | `8a636f7` | `Szs.blocks/2` with `prefix:`, `Szs.prefix/1`, `block` gains `prefix: [Regex.t()]` |
| 4 — fixtures | `53c5d1d` | `test/fixtures/tstp/` + two SZS fixtures, with `test/fixtures/tstp/README.md` recording provenance |
| — | `c49e4ed` | unplanned: the SZS atom test measured the global atom count from an async test and failed once when a new module was loaded beside it |
| 5 — R4 `Tptp.Tstp` | `101925b` | `Tptp.Tstp`, `Tptp.Tstp.Solution`, `test/tptp/tstp_test.exs` (23 tests, 7 doctests) |
| 6 — R3 `Tptp.Derivation` | `3272889`, `632efb6` | `Tptp.Derivation`, `.Node`, `.Step`, `TPTP0507`, the `TPTP05xx` tier line, `test/tptp/derivation_test.exs` (36 tests, 18 doctests) |
| — | `061299e`, `0b2a059` | the lint false positive of deviation 9, fixed, and the StarExec fixture's provenance re-checked |
| 7 — R6 housekeeping | `b2aee03` | `@version "0.2.0"`, the `TSTP` docs group, the README section and Function entry, the `[0.2.0] - 2026-10-13` CHANGELOG section, `CITATION.cff` and `.zenodo.json` |

The suite is 885 tests (140 doctests, 24 properties), dialyzer 0 errors, credo
clean over 107 files, `mix docs` warning-free. `Tptp.bnf_version/0` did not move.

## What is left

1. **The tag.** `git tag -a v0.2.0`, then whatever publishing follows (Hex,
   Zenodo). Left undone deliberately: the previous release was tagged and
   published by the user, and `.zenodo.json` carries a DOI that a tag will mint
   against.
2. **Tell AtpClient.** Plan 1.2 and section 11 list what that side must be told;
   the deviations below are the rest of it.
3. Optional: a corpus run is not needed — nothing in R3 or R6 touches the lexer,
   the parser or the printer, and the printer change of R5 was already measured
   over the whole library (below).

Still to do: **step 6 — R3 `Tptp.Derivation`** (plan 5.1–5.6), **step 7 — R6
housekeeping**, **step 8 — tag `v0.2.0`**. R6 is `@version "0.2.0"`, a TSTP group
in `groups_for_modules`, the `TPTP05xx` line in `Tptp.Diagnostic`'s tier table, a
README section, the CHANGELOG release block (plan section 10 — the `[Unreleased]`
block has been kept current as each step landed, so this is mostly moving it),
`CITATION.cff` / `.zenodo.json`, and one `mix docs` run.

The corpus printer test was run against the whole library for the R5 printer
change and passed: 1,494,651 statements round-tripped, 4 tests, 31 minutes
(`mix test --include corpus test/tptp/printer_corpus_test.exs`, in a separate
`MIX_BUILD_ROOT` so it does not hold the build lock).

## CST facts for R3, verified against the parser

Probed with `Tptp.from_string/2` on one-statement inputs and on the fixtures, so
the classifier in plan 5.2 can be written without guessing. `:general_list` is
`useful_info` throughout (chain rule).

```
a_name, 'quoted name', unknown     :name "a_name"                       (one leaf; `value/1` unquotes)
file('x.p')                        :file_source [:file_name]
file('x.p', ax1)                   :file_source [:file_name, :file_info [:name]]
introduced(definition,[…],[n])     :internal_source [:intro_type, :general_list, :parents]
inference(r,[status(thm)],[])      :inference_record [:inference_rule, :general_list, :parents]   (`:parents` has no child when `[]`)
inference(r,[],[a:[…], b])         :parents [:parent_list [:parent_info [:name, :parent_details [:general_list]], :parent_info [:name]]]
[a, b]                             :source [:sources [:name, :name]]
[a, b, c]                          :source [:sources [:name, :sources [:name, :name]]]           (right-nested from three on)
inference(r,[],[[a, b]])           :parent_info [:source [:sources […]]]                         (a bracketed source in parent position)
status(thm)                        :general_function [:lower_word "status", :general_terms [:lower_word "thm"]]
```

Not accepted by the v9.3.1.3 grammar, and correctly so — the vendored BNF
(`priv/bnf/SyntaxBNF-v9.3.1.3`, lines 528–546) has no such production, so these
are `TPTP0301` and never reach a `source` slot: `introduced(tautology)` and
`introduced(tautology,[])` (the BNF requires all three arguments),
`theory(equality)`, `creator(system,[])` (`<external_source> ::= <file_source>`
alone), and an empty `[]` source. `{:unknown, node}` therefore covers shapes the
grammar can build, not these.

Fixture facts for the R3 tests, measured:

- `e_cnfrefutation_raw.txt` — `Szs.blocks(output, prefix: Szs.prefix(:line_comment))` gives one `:cnf_refutation` block, 54 statements, no diagnostics. `c_0_53` is the plan's nested `sr(rw(c_0_19, c_0_51), c_0_52)` record, confirmed node for node.
- `vampire_proof_raw.txt` — one `:proof` block, 66 statements. Three `introduced(definition,[new_symbols(definition,[spl2_N])],[avatar_definition])` statements, and `avatar_definition` names no statement in the block, so **those nodes are not leaves** and each raises `Parent.code()` (`TPTP0504`). Plan 5.6 expects "`introduced(…)` nodes are leaves"; C5 and 5.2 say otherwise and win. There is no `file_source` with a `file_info` name *and* an `introduced` leaf in one fixture — the `file('…', name)` origin is covered by the same Vampire block's axioms.
- `e_saturation_raw.txt` — one `:saturation` block, 4 statements, every one `['final']` in `info`, parents `c_0_8`–`c_0_11` which the block does not contain (so: several roots, four `TPTP0504`s, `status(thm)` still resolves).
- `E---3.5.1.THM-CRf.s` through `Tptp.Tstp` — 54 statements, header states 54 formulae and 11 leaves.

## Deviations from the plan, to report at the end

For the final report and for what AtpClient must be told (plan 1.2, 11):

1. **C2 undercount** — six readers of `role.text`, not five: `Lint.Rules.Role`, `Lint.Context.role/1`, `Lint.Collect.typing?/1`, `Query.roles/1`, `Annotated`'s `Inspect`, and `Lint.Rules.AtomTyping`, whose false `TPTP0405` on a sub-role typing was a second bug fixed with it.
2. **Plan 7.1's example does not parse** — `interpretation-mappings(f,$i)` is not a `<general_term>` in that position; the doctests use `interpretation-domains` and `type-datatype`.
3. **Printer spacing** — a sub-role is written closed up (`interpretation-domains`), except before a number-like token, where `- 1` would lex as one integer. Verified over the corpus (above).
4. **Paradox fixture** — no library problem forces a two-element model, so `test/fixtures/szs/paradox_finite_model.txt` is `% domain size is 1`, not the plan's 2.
5. **`Regex` structs never compare equal on OTP 28** — a compiled pattern holds a `#Reference<>` in `re_pattern`, so `~r/x/ == ~r/x/` is false. `block.prefix` can only be compared by `.source`, or against the same bound value; pinned in the `block` typedoc and in `szs_test.exs`.
6. **StarExec fixture prefix is synthetic, and must stay so** — `starexec_e_proof_synthetic.txt` is live E output with the `0.NN/0.NN` stamp added. Re-checked on 2026-10-13: tptp.org serves StarExec-stamped output only inside an archived solution's ORIGINAL SYSTEM OUTPUT, and the TSTP's tooling lifts the solution out of it, so every such file has a start marker, `% See solution above` and no end marker — the E proof of `PUZ001+1` and the `Paradox---4.0`, `Mace4---2026-6A` and `DarwinFM---1.4.5` model solutions of `KRS018+1` all four. So this is not a release blocker; it is the only form the fixture can take short of a CASC job's own stdout. Recorded in `test/fixtures/tstp/README.md` (`0b2a059`).
7. **R3 5.6 vs C5** — the Vampire `introduced` nodes are not leaves (above).
8. **Atom counting is not an async-safe assertion** — `c49e4ed`; the pattern plan 5.6 asks R3 to copy ("Atom count unchanged across reading a fixture…") must use the fresh-word form instead, which is what `derivation_test.exs` does.
9. **`Tptp.Lint` reported a `<file_info>` name as a missing parent — fixed in
   `061299e`.** `Tptp.Lint.Collect.note_parent/3` collected every `:name` under the
   `:source` slot, so `file('x.p', ax1)` contributed `ax1`, which names the formula
   in `x.p` and no parent here (`SyntaxBNF-v9.3.1.3:544-545`; the language page says
   the name may differ from the one the formula now carries). Measured before the
   change: `vampire_proof_raw.txt` drew 14 `TPTP0504`, of which 11 were false, one
   per axiom; `e_cnfrefutation_raw.txt` drew 0, because E reuses the problem's own
   names, which is why the defect never showed. The names now come from
   `Tptp.Derivation.Node.parent_nodes/1`, so the two readers of a `<source>` share
   one walk, and a test asserts they report the same findings for the same file.
   Corpus: no verdict changes — the lint corpus gate reports the same 1089
   `TPTP0503` and 80 `TPTP0506` over 1485 units and no `TPTP0504` at all, and the
   four `SYN000*2.p` files that write `file('SYN000-1.p', source_unknown)` contain a
   statement of that name, so the rule was already silent there.
10. **Plan 5.6's expectations about E's proof are wrong in two places.** Not every
   `status` in `e_cnfrefutation_raw.txt` is `thm`: of 61 statuses, one is `cth`
   (the negated conjecture) and two are `esa` (skolemisation). And the saturation
   fixture's `['final']` is the *statement's* `info`, not the step's, so the step
   status is `:theorem`, not `nil`. The tests assert the measured values.
11. **`topological/1`'s tie-break reads oddly at first.** "Ties broken by `order`"
   means lexicographic-by-position Kahn, so for `c` (position 0, derived from `a`),
   `a` (1), `b` (2) the answer is `["a", "c", "b"]`: once `a` is out, `c` precedes
   `b` because the file writes it first. Documented at the function.

## Still open

Nothing from the list above is outstanding except what belongs to other documents:
the AtpClient hand-off (plan 1.2 and 11) and [[tptp-open-work]]'s duplicate-type
check, which this release did not touch.

## If the release is revisited

`Tptp.Derivation`'s CST facts and the fixture measurements above were probed, not
guessed, and the tests pin them; the probe scripts were session-local and are
gone, but nothing in them is unrecorded here.

The two readers' public surface is what AtpClient was promised plus three
additions the plan did not list: `Tptp.Derivation.Node.from_statement/1`,
`parent_nodes/1` and `alternatives/1`, and `Tptp.Derivation.Step.from_record/1`
and `named_parents/1`. They are public because the classification is testable on
its own and a caller holding one statement should not have to build a graph to
read its source.
