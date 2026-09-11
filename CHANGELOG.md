# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/spec/v2.0.0.html) over its Elixir API.

Note that the package version and `Tptp.bnf_version/0` are two different numbers: the
latter is the TPTP release whose BNF the shipped parser was generated from, and it
moves when TPTP moves, not when this library does.

## [Unreleased]

## [0.1.1] - 2026-09-10

Two things at once. `Tptp.analyze/2` and the `Tptp.Analyzer` behaviour give an
editor integration everything it needs from one traversal, `mix tptp.lint` puts the
diagnostics in a shell, and `Tptp.Query` learned the dependently typed dialects.
Separately, the library is adapted to TPTP BNF v9.3.1.3 and to the SZS ontology's
move to szs.tptp.org, which between them resolve every disagreement found between
the TPTP's published sources while 0.1.0 was in use.

One breaking change to note in each half: `Tptp.Query.within?/2` is a partial order
and no longer a sort comparator, and one SZS value's published name lost a
misspelling.

### Added

- `reports/FINDINGS.md`: what the four unparseable `SYN000*2.p` files were hiding.
  With the announced fix applied to copies, two further defects in those files
  surfaced, and a sweep of the library for anything else a skipped file could
  conceal showed three rules of this library's to be wrong. Each finding carries its
  citation and a command reproducing it, and the checks that found nothing are
  recorded with them.
- `Tptp.analyze/2` and `Tptp.Analysis`: the file, its diagnostics, the symbol
  table and the dialect from a single traversal, with an opt-in line index for
  turning span offsets into line and column once rather than once per diagnostic.
- `Tptp.Analyzer`, a behaviour for a named diagnostic producer over a
  `Tptp.Analysis`, with `run_all/3` dispatching by dialect and containing a
  raising analyzer as a `TPTP0800` diagnostic. `Tptp.Lint` implements it as
  `:tptp_lint`.
- `Tptp.Lint.scan/2`, the one traversal `run/2`, `run_unit/2` and `table/1` are
  now projections of — the symbol table is no longer rebuilt by a second walk.
- `mix tptp.census` and `reports/CENSUS.md`: where the library uses applied type
  constructors, and in which dialects. The report divides the THF heuristic's files
  by dialect, an all-TH1 distribution indicating that the heuristic is identifying
  types; heads the
  constructor table `Constructors (TFF)`, since the THF pass sets a boolean and
  contributes no names; and counts the files applying a constructor at arity ≥ 2
  over a type variable — directly and nested — which is the one shape an elaborator
  cannot monomorphise into a fresh sort.
- Both library sweeps parse each file in its own process under a `max_heap_size`
  ceiling, with `--heap` as the total across workers and a serial retry for a file
  that exceeds its share. A file's size does not predict its parse: the corpus runs
  from 2.5 to 111 bytes per CST node, so bounding a sweep by bytes of source bounds
  the wrong quantity.

- `Tptp.Query` recognises **DH0 and DH1**, the dependently typed higher-order
  dialects. They use the `thf` keyword, so they parsed all along — all 131 in TPTP
  v9.3.1 do, cleanly — but every one classified as `:th1`, because a `!>` set
  `:polymorphic` whatever it bound. What it binds is the whole difference:
  `!>[A: $tType]` abstracts over a type and is polymorphism, `!>[A: nat]` abstracts
  over a term and is a dependent type, and the same distinction separates
  `list: $tType > $tType` from `fin: nat > $tType`. There is now a `:dependent`
  feature beside `:polymorphic`, and `within?/2` places DH0 above TH0 and DH1 above
  TH1, which is what the TPTP language page states.

  Checked against the TPTP's own `SPC` header over the 26,021 problems of v9.3.1 that
  carry one: 85 DH0 and 46 DH1 identified exactly, with no TH0 or TH1 problem misread
  as either, and no change to any other dialect's classification.
- `mix tptp.lint`, a command line over `Tptp.analyze/2`. Everything the library can
  say about a file was reachable only from Elixir; this is the same thing from a
  shell, printing `path:line:column: severity: message [CODE]` and exiting non-zero
  when anything at or above `--severity` was found. `--include` resolves the graph
  and lints the unit, `--only`/`--suppress` filter by code, and `--format json`
  emits one object per line.
- `Inspect` implementations for `Tptp.File`, `Tptp.Unit`, `Tptp.Node`,
  `Tptp.Analysis`, `Tptp.Lint.Table` and both statement structs. The derived ones
  printed the whole source binary and every node that points into it — into an IEx
  prompt, a `Logger` line or an exception report. Each now prints a summary in
  constant time, and `inspect(term, structs: false)` still shows the map.
- `Tptp.Query.rank/1` and `Tptp.Query.dialects/0`, the total listing order that
  `within?/2` used to be mistaken for.
- `Tptp.Bnf.Generator.departures/0`, so `mix tptp.gen` prints the departures from
  the constants that cause them rather than from a second copy that can fall behind.
- `{:exactly, dialects}` as an `Tptp.Analyzer` gate, for an analyzer that means the
  dialects it named and does not want `within?/2`'s judgement applied to them.

### Removed

- `reports/TPTP-DEFECTS.md`, the register of places where the published TPTP
  sources disagreed with each other. It never shipped: it was written during this
  cycle, all six entries were reported upstream, and BNF v9.3.1.3 together with the
  SZS ontology's move resolved every one of them. The mechanisms it documented —
  `@documented_values` and `@name_atom_overrides` — are gone with it, and the
  vendored files are transcribed rather than corrected again.
- `Tptp.Lint.Rules.Arity` and `TPTP0505`, which reported a symbol applied at two
  arities. The premise was false. The TPTP language page, in the section on logical
  formulae that governs every dialect, says: "Symbols may be overloaded with different
  arity signatures, and are treated as different symbols."

  Swept over all 29,358 library files the rule fired on eleven, and it was wrong about
  every one. Ten — `SWX075_1.p`, `SWX076_1.p` and `SWX091_1.p`–`SWX098_1.p` — declare
  `color` or `sqrt` at arity 1 and again at arity 2 and use both, which is two symbols
  doing nothing wrong. The eleventh, `SYN000_4.p`, was our own bug (below). The
  exclusion list that hid them from the corpus gate is gone with the rule, and
  `TPTP0505` is unassigned.

  The real rule the TPTP states — "If a symbol's type is declared more than once, and
  the types are not the same, that's an error" — is about one symbol, so it compares two
  declarations at the *same* arity. `Tptp.Lint.Table` keys on the name alone and cannot
  express it yet. It is not implemented, and it is worth implementing.

### Changed

- **The vendored BNF is TPTP v9.3.1.3**, which resolves every disagreement this
  library had recorded between the TPTP's own published sources. `<formula_role>`
  gains `logic`, `<ntf_modal_system>` the ten systems it omitted, `<ntf_modal_axiom>`
  the four axioms it omitted, and `<defined_functor>` gains `$abs`. Each had been
  defined by the prose of the TPTP language page and absent from the `:==` rule
  quoted further down that same page; the library carried them as cited corrections
  under `Tptp.Bnf.Generator`'s `@documented_values`, and that mechanism is gone
  because there is nothing left for it to correct. `TPTP0401` fired on 354 library
  problems and `TPTP0402` on 80 occurrences before those corrections; both now fire
  on nothing in the library, and now do so by transcription rather than by
  correction.

  `Tptp.bnf_version/0` answers `"9.3.1.3"`. The grammar, the vocabularies, the
  printer shapes and the lexer oracle are regenerated from it; the node kinds are
  unchanged, so a tree cached under `"9.3.1.2"` is still readable.
- **`<distinct_object>` now requires at least one `<do_char>`**, matching
  `<single_quoted>`, so `""` is no longer admitted by the BNF. The lexer emits the
  token as before and `TPTP0107` — until now "empty quoted atom", now reported for
  either quoting — fires on it as it already did on `''`. The asymmetry between the
  two rules was an open question in the register and this is its answer.
- **The SZS ontology moved to <https://szs.tptp.org>.** The former address serves a
  notice pointing there. The page is re-vendored as
  `priv/szs/SZSOntology-2026-09-10.html`, `Tptp.Szs.Extract` reads its new markup,
  and `Tptp.Szs.Ontology.source/0`, `vendored/0` and `digest/0` answer accordingly.
  The 112 values, their mnemonics, ontologies, subontologies and descriptions are
  unchanged but for the spelling below.

  The new page carries per-response script nonces and signed image URLs, so two
  fetches of an unchanged page do not agree byte for byte. The `:network` test that
  checked the vendored copy against the live page by digest now compares the
  ontology the two yield, value for value; `NOTICE` records why.
- **`TPTP0501` applies to the higher-order dialects only.** The TPTP language page
  gives TFF default typing — an undeclared predicate is `($i,...,$i) > $o` and an
  undeclared function `($i,...,$i) > $i` — and says that THF "does not admit default
  typing". The rule reported undeclared symbols in every typed dialect, so it fired
  on 517 legal occurrences across seventeen TFF, TXF, TCF and NXF library files,
  which the corpus gate carried as true findings. It now fires only in a unit
  containing a `thf` statement. The README's claim that the typed dialects require a
  declaration for every symbol is corrected with it.
- **Breaking, for a consumer comparing SZS names as strings.**
  `Tptp.Szs.Ontology.name(:counter_tautology_preserving)` answers
  `"CounterTautologyPreserving"`, and `from_string/1` admits that spelling alone.
  The page had spelled it `CounterTautologyyPreserving`, with a doubled `y`, and the
  move corrected it. The atom is unchanged; `Tptp.Szs.Generator`'s
  `@name_atom_overrides`, which had supplied it, is gone.
- `Tptp.Query.within?/2` is now a **partial** order and no longer a position
  comparison in a single list. The dialects are not a line — TCF and the
  non-classical languages are branches — and the old reading answered `true` for
  every pair, so `within?(:th1, :nxf)` and `within?(:tcf, :tf0)` were both true and
  an analyzer scoped to one branch was handed the other's files. It is therefore no
  longer usable as a sort comparator; `rank/1` is.

### Fixed

- `Tptp.Query.dialect/1` recognises TXF by its FOOL constructs, and no longer reads
  four TXF files in five as TF0. It recognised a tuple, a `$let` and a sequent, each
  of which has a node kind; but the rest of what TXF adds to TFF is FOOL, and no FOOL
  form has a node kind of its own, each being an ordinary TFF node standing where TF0
  also admits one. A `$o` variable, a formula or `$true`/`$false` in a term position,
  a declared `$o` argument type, `$ite` and `$distinct` now carry it. Against TPTP's
  own `SPC` headers over the problems under 1 MB, 51 of the 252 TX0 problems were
  classified correctly before and all 252 are now, with no false positive among the
  2,060 TF0, 590 TF1 and 60 TX1 problems beside them.
- `TPTP0504` no longer reports the literal `unknown` source as a missing parent.
  `<source> ::= … | unknown` is a literal, which the grammar reads as a `<name>` —
  the first of the generator's departures, the two being otherwise
  indistinguishable — and the rule went looking for a formula called `unknown`.
  Four library files write it, the `SYN000*2.p` demonstrations, and the rule fired
  twice on each; their parse failures had kept that out of every sweep.
- Every reference to the committed reports follows them into `reports/`.
  The move left `mix docs` failing outright — `extras:` still named a report at the
  root — and three quieter breakages behind it: the
  package's `files:` list no longer shipped any of the reports, `mix tptp.corpus`
  and `mix tptp.census` defaulted `--out` to the old root paths, so a plain run
  wrote a second copy at the root and `--check` failed on a file it could not read
  rather than on a stale one. `Tptp.Lint.Rules.DefinedWord` also pointed four
  directories up where it needed five, which ExDoc hid by resolving extras on
  basename alone; the link only broke when read on GitHub.
- `Tptp.Checks.NoDynamicAtoms` listed `String.to_charlist_atom` among the calls it
  forbids. No such function exists, so the entry could never fire, and a check that
  never fires reports a clean tree exactly as convincingly as a clean tree does.
  Removed, `:erlang.binary_to_term/1` added — it builds atoms out of a serialised
  term — and a test now asserts that every entry in the list names a function the
  runtime exports, so the next typo fails the suite instead of quietly widening the
  gap between what the check claims to cover and what it covers.
- `mix dialyzer` passes under `MIX_ENV=test`, which is the environment `mix check`
  uses. `Tptp.Test.Corpus.timeout/0` was specced as `timeout()` while only ever
  answering `:infinity`, and two functions that exist to raise lacked a
  `no_return()` spec.
- The corpus gates' heap budget no longer divides by ExUnit's `max_cases`. It
  divided both the budget and the worker count, on the reasoning that dividing both
  leaves each worker the share it would have had alone — but the worker count floors
  at one and `max_cases` defaults to twice the scheduler count, so the share shrank
  as the machine grew: 375 MB on a two-core runner, 96 MB on eight cores, 48 MB on
  sixteen. `mix test --only corpus` failed thirteen of twenty-nine gates on a default
  invocation, every one of them a heap kill on a large file rather than a
  disagreement about what a file means. Sweeps now take a lock and hold the whole
  budget one at a time, which is what the measurements allow: one file under the
  20 MB cap wants 4 GB to parse.
- `mix credo --strict` runs Credo's full check set again. `.credo.exs` declared
  `checks: %{enabled: [...]}`, which *replaces* the default set rather than
  extending it, so two checks ran instead of sixty-nine and the `:disabled` list was
  inert. The custom no-dynamic-atoms check was one of the two, so that property was
  never at risk.
- `Tptp.Unit.from_string/2` and `from_file/2` hand `Tptp.from_string/2` only the
  options it documents, instead of forwarding their own superset. It worked — the
  reader ignores keys it does not know — but it made the call a type error, and
  `:max_concurrency` was missing from `t:Tptp.Unit.option/0` besides, though
  `Tptp.Include` has always read it. Neither was caught because no code in `lib/`
  built a unit with a resolver until `mix tptp.lint` did, and Dialyzer does not read
  the tests.
- Documentation that had drifted from the code it describes: the role rule's count
  (354 files, not one), the generator's departure count (four, not three), the
  `<reserved_word>` list's provenance (this library's, not a `:==` rule of the BNF),
  a diagnostic tier that nothing emits, the `Parent` rule's description of
  `<source>` from before v9.3.1.2, the Credo check's module name, and the README's
  figures for the oversized files and the sweep's wall clock.

- A `$let` type binding is no longer counted as an application at arity zero.
  `$let(ff: ( $int * $int ) > $int, ff(X,Y) := ..., ...)` recorded `ff` at arities 0 and
  2, because a `type`-role statement's subject is recognised and skipped while a nested
  let binding was not. `Tptp.Lint.Collect` now claims the binding's position the way it
  already claims an `<ntf_index>`'s. This was the second place the same blind spot hid,
  and it was found by opening `SYN000_4.p` rather than by the tests.
- `Tptp.Lint.Collect` now records a `$let` binding as a declaration, so
  `TPTP0501` no longer reports `$let(a: array(elt), a := ..., ...)` as using an
  undeclared `a`. It fired on 39 `SWW` problems, every one of them wrong. The
  symbol table stays flat — two `$let`s binding one name are one entry — which is
  enough for a rule that asks only whether a name was ever declared, and is not
  the same as modelling scope.

### Notes

- Four library files still do not parse, and both reasons are defects in the files.
  `SYN000-2.p`, `SYN000+2.p` and `SYN000^2.p` use `theory(equality)` as an inference
  parent, which `<source>` has not derived since v9.3.1.2; that was fixed upstream on
  10/09/26 — see <https://tptp.org/TPTP/Distribution/BuggedProblems-v9.3.1.txt> — and
  all three parse against the corrected text, so they leave
  `Mix.Tasks.Tptp.Corpus.known_failures/0` when the distributed tarball carries the
  edit. `SYN000_2.p` carries a second and independent one, reachable only once the
  first was resolved: it writes `introduced(assumption,[from,the,world,[]])` where
  both the BNF and the TPTP language page state
  `introduced(<intro_type>,<useful_info>,<parents>)`, and the other three dialects'
  copies of the same file write `introduced(assumption,[from,the,world],[])`. Not
  reported upstream as of 2026-09-10.
- `SYN000^2.p` carries a further defect that only surfaces once it parses: its
  `let_tuple_4` applies `qll @ a @ b`, and nothing declares `qll`. THF admits no
  default typing, so that is an error, and `TPTP0501` reports it. `ql`, declared as
  `$int > $int > $o`, has exactly the type the use needs, so it is presumably a
  typo. Not reported upstream as of 2026-09-10.

## [0.1.0]

First release. Generated from TPTP BNF v9.3.1.2 and the SZS ontology as published on
2026-08-31.

### Added

- `Tptp.from_string/2`, `from_file/2` and the `!` variants, plus `stream_string!/1`
  and `stream_file!/2` for input too large to hold as statements.
- A resumable hand-written lexer with byte-accurate spans, and a statement splitter
  that bounds the blast radius of malformed input to one statement.
- An LALR(1) parser generated from the vendored BNF by `mix tptp.gen`, and a CST
  whose node tags are BNF nonterminals. No elaboration, no typing, no inference:
  explicit type arguments are recorded verbatim, in source order, with spans.
- `Tptp.Node.value/1`, the canonical atomic word behind a leaf's spelling, so that
  `'p'` and `p` are one symbol everywhere they are identified — the symbol table,
  statement names, inference parents and `include` selections all key on it.
- `Tptp.Node.new/3` for consumers that emit TPTP rather than read it, with the
  print-and-reparse round trip as the validity check for a constructed tree.
- `include` resolution over a pluggable resolver — `Fs`, `Http`, `Cascade`, `Map`
  and the default `None` — with cycle detection, formula selection and a `Tptp.Unit`
  that keeps both the flattened statement list and the include tree.
- Lint rules over one fused walk, and `Tptp.Query.dialect/1`.
- Three printers: canonical, pretty (`Inspect.Algebra`) and format-preserving, the
  last of which backs `mix tptp.format` and provably changes no token.
- `Tptp.Szs` for the status lines provers print, over a generated ontology of the
  112 published SZS values.
- Diagnostics on every stage, tiered by code, never raised at the caller.
- `mix tptp.corpus`, which reads a local TPTP library through the parser and writes
  [CORPUS.md](reports/CORPUS.md). A nightly workflow sweeps the library entire; a pull
  request sweeps one file in five.

### Notes

- Zero runtime dependencies. `yecc`, `:crypto`, `:inets` and `:ssl` ship with OTP.
- No atom is ever created from input. A custom Credo check enforces it, because the
  atom table is never collected and this library reads untrusted files.
- The SZS `isa` hierarchy is deliberately not modelled: it is published only as
  diagrams, and guessing at it would put unverifiable relations into a library whose
  contract is faithfulness.

[Unreleased]: https://github.com/jcschuster/tptp/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/jcschuster/tptp/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jcschuster/tptp/releases/tag/v0.1.0
