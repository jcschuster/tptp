# Handoff — TPTP library work, resuming elsewhere

Scratch file. Delete it before committing; it exists to carry state between machines.

Two sessions on the previous machine took down the WSL2 subsystem — almost
certainly the full-library sweeps: 29,358 files at 16 workers, plus a run that
parsed the 65 `HWV` problems over 20 MB (one of them 265 MB) and reached ~5 GB
RSS. **Do not re-run those two things concurrently, and do not parse the >20 MB
problems eagerly at all.** See *Rules for the next machine* at the bottom.

## Where things stand

Everything below is **done and verified** unless a checkbox says otherwise. All
work is uncommitted in the working tree.

### Working tree

Modified: `.gitignore` `CHANGELOG.md` `README.md` `mix.exs`
`lib/tptp/bnf/generator.ex` `lib/tptp/bnf/vocabulary.ex` `lib/tptp/include.ex`
`lib/tptp/lint.ex` `lib/tptp/lint/collect.ex` `lib/tptp/lint/context.ex`
`lib/tptp/lint/rule.ex` `lib/tptp/lint/rules/atom_typing.ex`
`lib/tptp/lint/table.ex` `lib/tptp/node.ex` `lib/tptp/query.ex`
`lib/tptp/statement/include.ex` `lib/tptp/szs/extract.ex`
`lib/tptp/szs/generator.ex` `lib/tptp/szs/ontology.ex` `test/support/corpus.ex`
`test/tptp/bnf/generator_test.exs` `test/tptp/lint_corpus_test.exs`
`test/tptp/lint_test.exs` `test/tptp/parser_test.exs` `test/tptp/szs_test.exs`
`test/tptp/unit_test.exs` `test/tptp_corpus_test.exs`

New: `.github/workflows/corpus.yml` `CORPUS.md` `lib/mix/tasks/tptp.corpus.ex`
`lib/tptp/lint/rules/conjecture.ex`

### Green as of the last run

- `mix test --exclude corpus` — **611 passed** (85 doctests, 24 properties, 502 tests)
- `mix format --check-formatted` — clean
- `mix credo --strict` — 2047 mods/funs, no issues
- `mix dialyzer` — 0 errors
- `mix tptp.gen --check` — current
- `mix tptp.corpus --check` — "CORPUS.md is current"

## The eight items from the first request — all done

1. **`<atomic_word>` canonical value.** `Tptp.Node.value/1` added: strips the
   quotes of a `single_quoted` and unescapes `\'` and `\\`. `text` stays the
   spelling. `Tptp.Lint.Collect` keys every symbol, statement name and inference
   parent on `value/1`; `Tptp.Lint.Table` and `Tptp.Query.symbols/1` inherit it.
   `Tptp.Include.selected/1` and `names_under/2` too. Verified: the reported
   repro now gives keys `["p"]` and reports TPTP0505 on the arity clash.
2. **`@source_url`.** `mix.exs:5` now `https://github.com/jcschuster/tptp`.
3. **The headline number.** `mix tptp.corpus` added; `CORPUS.md` committed;
   `.github/workflows/corpus.yml` added (nightly + PR).
4. **`every: 5`.** Full sweep is the nightly default (`TPTP_CORPUS_FULL=1`),
   `every: 5` the PR default.
5. **SZS ordering.** `Tptp.Szs.Generator.moduledoc/2` gained "What to do when
   there is no ordering" — prefer `Success` over `NoSuccess` via `success?/1`,
   use `subontology/1` within `Success`, prefer an explicit `% SZS status` line
   over a prover-specific pattern.
6. **The Alt index.** `Tptp.Node` moduledoc gained "The alternative index is not
   kept", naming the single `cnf_literal` collision (`~p` vs `~(p)`).
7. **Builder API.** `Tptp.Node.new/3` (offsets default to 0) plus a moduledoc
   section documenting print → reparse → `shape/1` as the validity check.
8. **Conjecture rule.** `Tptp.Lint.Rules.Conjecture`, TPTP0506, `:info`. Zero
   conjectures only reports under `run_unit/2` — that is what
   `Tptp.Lint.Context.whole` was added for.

## The headline result, now over the complete library

`/opt/TPTP` on the old machine was a full TPTP v9.3.1 (26,990 problems, 2,438
axiom sets, 10 GB on disk).

| Set | Files | Parsed | Failed | Timed out |
|---|---:|---:|---:|---:|
| Problems | 26925 | 26921 | 4 | 0 |
| Axioms | 2433 | 2433 | 0 | 0 |
| Total | 29358 | 29354 | 4 | 0 |

5,428.1 MB in 662 s on 16 workers. Nothing timed out; the slowest file
(`SYN842-1.p`, 16 MB) took 59.9 s of a 60 s budget under contention. Against the
prior toolchain's **628 timeouts / 221 parse failures** over the TH0/TH1 subset
alone.

The four failures are `SYN000-2.p`, `SYN000+2.p`, `SYN000_2.p`, `SYN000^2.p` —
the annotated-formula demonstration, one per dialect — all refused for
`theory(equality)` in source position. Recorded in
`Mix.Tasks.Tptp.Corpus.known_failures/0`.

Excluded by `--max-bytes`: the 70 files over 20 MB (65 `HWV` problems, 5 axiom
sets, 3.4 GB). The streaming gate in `test/tptp_corpus_test.exs` covers the
largest of them.

## Bugs found in *our* library while gathering evidence — all fixed

1. **`Generator.reserved_words/1` missed `$`-words inside literal runs.** A rule
   writes `$ite(` as one literal, so an anchored whole-run match never saw
   `$ite`. Now regex-scans runs. `<reserved_word>` 91 → 98. Test added.
2. **`Tptp.Lint.Rules.AtomTyping`'s nested-typing clause could only ever be
   wrong.** The grammar reaches `<thf_atom_typing>` from exactly three places —
   statement top, a `$let` binding, `(<atom_typing>)` — all legitimate. It fired
   11× on `SYN000^2.p`. Clause deleted, moduledoc explains why there is no rule.
3. **`<ntf_index>` labels counted as signature symbols.** `{$necessary(#agent)}`
   made `agent` a TPTP0501. Fixed with `Tptp.Lint.Table.ignore/2` over the index
   subtree.
4. **`Tptp.Szs.Extract` silently dropped one published ontology value.**
   `Assumed` is written `(<TT>ASS(</TT><EM>U</EM><TT>,</TT><EM>S</EM><TT>)</TT>)`
   — the only parameterised mnemonic on the page — and the three-letter pattern
   skipped it. The table was right about 111 values and short by one, with no
   error. Fixed: the mnemonic pattern now takes whatever is between the
   parentheses and keeps the leading three letters (`ASS`), and `complete!/3`
   raises if any `<LI> <TT>Name</TT>` in a section fails to come back as a value.
   Ontology is now **112 values** (success 53, no_success 29, data 30). `ASS`
   (Assumed, no_success) and `Ass` (Assurance, data) are case-distinct — tests
   added for both, plus the completeness guard.

## The document for Geoff

Published artifact — **https://claude.ai/code/artifact/c120de20-072c-45be-befc-f1bd9a58bf27**
("SyntaxBNF v9.3.1.2 Findings", favicon 📐).

**The live artifact is still the OLD 15-finding version scoped to 7,712 files.**
A rewritten 19-finding version scoped to all 29,358 files was drafted and
verified but **not yet published** — the scratchpad was wiped twice by session
restarts. Partial draft survives at
`/workspace/.claude-config/projects/-workspaces-ShotTx/40d79b05-924d-436d-a2b3-5bfadd94fdd1/work/`
(`head.html` = title + the whole `<style>` block, `body1.html` = masthead
through F4, `tail.html` = the `<script>` that colours BNF excerpts). That path is
machine-local, so the one piece worth carrying — masthead, scope, index and
F1–F4, with the right class names — has been copied next to this file as
`.artifact-draft-body1.html`. On the new machine, re-derive the page shell by
reading the published artifact (`Artifact action:"read"` with the URL above):
everything up to and including `</style>` is the head, and the trailing
`<script>` block that colours BNF excerpts is the tail. Write F5–F19 and the
closing sections from the finding text below.

### The 19 findings, with the evidence each rests on

Defects:

- **F1 — the v9.3.1 release ships a v9.3.0.4 `SyntaxBNF`.** `Documents/SyntaxBNF`
  in the tarball ends at header entry v9.3.0.4; tptp.org serves v9.3.1.2. Not
  cosmetic: the shipped copy's `<thf_fof_function>` lacks the
  `<functor>(<thf_arguments>)` alternative v9.3.1.1 added "to make ITV work".
  Everything else in the diff is comment text — including the two regressions at
  F13 and F14.
- **F2 — `<source>` no longer admits `theory(...)`.** 4 files, 8 statements, the
  only files in 29,358 the grammar refuses. BNF lines 506–514.
- **F3 — `logic` missing from `<formula_role>`.** 350 problem files across ten
  domains (SYO 170, SYP 108, PHI 15, PUZ 13, LCL 12, GRA 12, PLA 10, SYN 4,
  DAT 4, MSC 2) plus four `PHI00x_1.rm`. Library-wide role histogram: axiom
  40,516,753 · type 4,947,954 · negated_conjecture 187,888 · hypothesis 77,086 ·
  definition 71,175 · lemma 41,129 · conjecture 17,241 · logic 350 · four each of
  unknown, theorem, assumption. Ten of eleven are in the `:==` list.
- **F4 — `<ntf_modal_system>` short by five.** Live (non-comment) file counts:
  K 112, S5 44, M 41, S4 38, D 37, **KB 26, K4 22, K5 18, D4 6, K45 4**, B 1.
  76 uses of an undeclared system, one per file, across SYP 54, PHI 8, GRA 4,
  LCL 4, PLA 3, SYO 3. Comment-only: S5U 26, T 17.
- **F5 — 26 rules unreachable from `<TPTP_file>`.** 336 nonterminals defined, 300
  reachable through productions, 10 of the other 36 are lexical macros, the
  remaining 26 are the whole `ntf` logic-specification block (lines 309–347).
  Sharpest evidence: six nonterminals are defined and never referenced —
  `<TPTP_file>` (root), `<alpha>` `<comment>` `<slosh>` `<viewable_char>`
  (lexical), and `<ntf_semantics_spec>`, the head of the block. The block is
  *correct*: `$domains`/`$designation`/`$terms` 294 live uses each, `$modalities`
  350, and every value they take is in the BNF.
- **F6 — `$let(...)` ambiguous in THF and TFF.** Lines 110–130, 145; 226, 242.
  The BNF already resolves the same ambiguity for `$ite` by commenting
  `<thf_conditional>` out (lines 117–129).
- **F7 — `unknown` has two derivations in `<source>`.** Lines 507, 514. No
  statement in the library writes `unknown` in source position; every live
  occurrence is a constant in a formula, apart from four uses as a role.
- **F8 — two `:==` rules each for `<defined_proposition>`/`<defined_predicate>`.**
  Lines 476–480, and the two disagree.

Points to clarify:

- **F9 — does `<single_quoted>` include its quotes?** Production says yes
  (lines 638), comment says no (line 640).
- **F10 — `<back_quoted>` has no stated meaning.** Three occurrences in the file,
  none a comment (609, 642, 717). **Zero `<back_quoted>` tokens in the whole
  library** — a specification question with no installed base.
- **F11 — `''` illegal where `""` is legal.** Line 638 `<sq_char><sq_char>*`
  against line 644 `<do_char>*`. Library: 5,109,293 quoted atoms and 12,597
  distinct objects, **none empty**. The 798 files whose text contains `''` have
  it in a comment or as `'A \'quoted \\ escape\''` (`SYN000^1.p`).
- **F12 — `$ite` in no defined-word vocabulary.** 98 `$`-words appear in the BNF,
  63 are in an enumerated `:==` list; for most of the other 35 that is right
  (`ntf` spec literals), but `$ite` is an applied functor.

Typographical — **two of these are regressions introduced by the v9.3.1.2 "Fixed
typos in comments" pass**, which is the interesting part:

- **F13 — line 78, `codatatype"` lost its opening quote.** v9.3.0.4 line 81 has
  it right. The same edit correctly fixed `unknown"s` → `"unknown"s` two lines up.
- **F14 — line 614, `lower_word>` lost its opening bracket.** v9.3.0.4 line 615
  has it right. The same sentence's `123'` → `'123'` fix landed correctly.
- **F15 — line 645:** `%---` (three dashes), `distinct_object>` missing its
  bracket, two sentences run together, "upto".
- **F16 — line 718:** `%---` and "upto". The file has exactly three `%---`
  comments (225, 645, 718) against 269 `%----`, and exactly two "upto"s.

SZS ontology (page as published 2026-08-31):

- **F17 — `CounterTautologyyPreserving`, and `NoSuccesss`.** The value has a
  doubled `y`; the section heading `<H3> The <TT>NoSuccesss</TT> Ontology </H3>`
  has three `s`.
- **F18 — `Assumed` is the one value whose mnemonic takes arguments.**
  `ASS(U,S)`. The page never shows it in a `% SZS status` line; `<status_value>`
  is 34 plain words so `status(ass(...))` has no derivation; and it is easy to
  lose — we lost it (see bug 4 above).
- **F19 — the `isa` hierarchy is published only as three PNGs.** The text list is
  flat (one `<LI>` per value, no nesting) and the v9.3.1 distribution ships no
  ontology file of any kind. The user's hand transcription of `Success.png` and
  `NoSuccess.png` (81 nodes, 91 distinct edges) let us cross-check: **78 of 81
  node labels agree with the text exactly**; three do not —
  `TypeCheckedComplete`/`TSC` drawn as `TypeChecked`/`TCC`;
  `MemoryOut`/`MMO` drawn as `Memory`/**`TMO`**, colliding with `Timeout`'s own
  code so the diagram holds two nodes abbreviated `TMO` and `MMO` appears
  nowhere; and `Assumed` drawn without its `(U,S)`. Two softer observations
  offered as questions: the graph is a **DAG** (12 values have two parents —
  THM SAT ESA ECS EQV CSA CTH CEQ CAX NOC SCA SCC), so no consumer API can have
  `parent/1`; and `SAT isa THM` / `FSA isa THM` came out of the transcription
  but do not follow from the text's definitions — far more likely a misread of a
  dense drawing, which is exactly the point of the finding.

Also verified clean, and stated in the document for contrast: no undefined
nonterminals (all 330 referenced names are defined); all 34 `<status_value>`s
are Success mnemonics; `<sq_char>`/`<do_char>` octal ranges are exactly right;
only two vocabularies in the whole library have outgrown their `:==` list.

## TODO on the next machine

- [ ] **Publish the rewritten artifact.** Read the existing artifact at the URL
      above, rebuild the page from the finding text in this file, publish with
      `url:` set to that same URL so the link is preserved. Do **not** publish to
      a new path. Keep the title `SyntaxBNF v9.3.1.2 Findings` and the 📐 favicon
      (omit `favicon` on redeploy).
- [ ] **Run the corpus test suite over the full library** — never started
      successfully; both attempts died with the sessions.
      `TPTP_CORPUS_FULL=1 mix test --only corpus`, **`--max-cases 4`**, nothing
      else running. Expect a long run. What it gates: no error-severity
      diagnostic on any library file; unit lint reports only TPTP0401, TPTP0402,
      TPTP0503, TPTP0506; the arity rule finds nothing; every file gets a
      dialect; and each `known_failures/0` entry still fails.
- [ ] **Re-verify the four green checks** on the new machine (`mix test
      --exclude corpus`, `format`, `credo --strict`, `dialyzer`,
      `mix tptp.gen --check`, `mix tptp.corpus --check`).
- [ ] **Delete `HANDOFF.md` and `.artifact-draft-body1.html`** before committing.

### Optional, only if wanted

- [ ] Parse the 70 files over 20 MB to retire the size-cap caveat. **This is what
      probably killed the machine** — 265 MB of source became ~5 GB of CST. If
      attempted: one file at a time, largest last, `ERL_MAX_MEM` capped, nothing
      else running, and stop at the first file that exceeds a few GB. The
      streaming gate already covers the case, so the marginal value is low.

## Rules for the next machine

- **One heavy job at a time.** Never run `mix tptp.corpus` and
  `mix test --only corpus` together; that combination is what wedged WSL2.
- **Cap concurrency.** `mix tptp.corpus --concurrency 4` and
  `mix test --max-cases 4` rather than one worker per scheduler.
- **Do not eagerly parse anything over 20 MB.** Use `Tptp.stream_file!/2`.
- **Write scratch files here, not to `/tmp` or the session scratchpad.** Both
  were wiped by session restarts on the old machine, twice, losing the drafted
  artifact body each time.

## Environment notes

- `$TPTP_ROOT` was `/opt/TPTP`; `Mix.Tasks.Tptp.Corpus.root/0` falls back to
  `$TPTP_ROOT`, `$TPTP`, then `/opt/TPTP`.
- The sandbox egress proxy blocked `https://www.tptp.org/TPTP/Distribution/TPTP-v9.3.1.tgz`
  (404 with a Google error body). The nightly workflow downloads it directly;
  that path is untested from here.
- `corpus.yml` was rewritten for the full library: `timeout-minutes: 330`, no
  library cache (10 GB unpacked is beyond what the cache is for), extracts only
  `Problems` and `Axioms`, and deletes files over 20 MB right after extraction so
  the runner holds ~6 GB.
