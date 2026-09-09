# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/spec/v2.0.0.html) over its Elixir API.

Note that the package version and `Tptp.bnf_version/0` are two different numbers: the
latter is the TPTP release whose BNF the shipped parser was generated from, and it
moves when TPTP moves, not when this library does.

## [Unreleased]

### Added

- `Tptp.analyze/2` and `Tptp.Analysis`: the file, its diagnostics, the symbol
  table and the dialect from a single traversal, with an opt-in line index for
  turning span offsets into line and column once rather than once per diagnostic.
- `Tptp.Analyzer`, a behaviour for a named diagnostic producer over a
  `Tptp.Analysis`, with `run_all/3` dispatching by dialect and containing a
  raising analyzer as a `TPTP0800` diagnostic. `Tptp.Lint` implements it as
  `:tptp_lint`.
- `Tptp.Lint.scan/2`, the one traversal `run/2`, `run_unit/2` and `table/1` are
  now projections of — the symbol table is no longer rebuilt by a second walk.
- `mix tptp.census` and `CENSUS.md`: where the library uses applied type
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
- `TPTP-DEFECTS.md`, the register of places where the published TPTP sources
  disagree with each other. Five entries, each with its citation, the files it
  affects and a command that reproduces the count, so they can be reported upstream
  as they stand, plus two notes on things that look like defects and are not. The
  library works around none of them.
- `Tptp.Query.rank/1` and `Tptp.Query.dialects/0`, the total listing order that
  `within?/2` used to be mistaken for.
- `Tptp.Bnf.Generator.departures/0`, so `mix tptp.gen` prints the departures from
  the constants that cause them rather than from a second copy that can fall behind.
- `{:exactly, dialects}` as an `Tptp.Analyzer` gate, for an analyzer that means the
  dialects it named and does not want `within?/2`'s judgement applied to them.

### Removed

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

- The modal system and axiom vocabularies are corrected against the TPTP language
  page, so `TPTP0402` no longer fires on the 76 library occurrences of a system name
  the BNF omits. The Non-classical Logics section states that `$modalities` may be a
  system name of the form `$modal_system_Sys` with Sys drawn from sixteen values, or
  a tuple of axiom names `$modal_axiom_Ax` with Ax drawn from ten; the `:==` rules on
  the same page name six of each. The library previously recorded this as the two
  sources agreeing against the corpus, which was wrong: the first check grepped the
  page for literal `$modal_system_X` strings, and the page states the values as a
  schema, so the only literals found were those in its own embedded BNF.

  `@documented_values` now quotes the set a cited source publishes in full rather
  than the difference against the BNF, so an entry is a citation; `add_documented/1`
  computes the difference and the build fails once the BNF covers the set. Corrected
  `$`-words also enter `<reserved_word>`, which is the list
  `Tptp.Lint.Rules.DefinedWord` consults.
- `$abs` is now accepted as a defined functor, so `TPTP0402` no longer fires on the
  four occurrences in `ARI763_1.p`. The arithmetic table of the TPTP language page
  defines it over `$int`, `$rat` and `$real`; the `:==` rule on the same page omits
  it. The other extended arithmetic symbols visible on that page — `$min`, `$max`,
  `$sqrt`, `$pi` and fifteen more — are inside HTML comments and are not published,
  so they are not added.
- `logic` is now accepted as a formula role, so `TPTP0401` no longer fires on the 354
  library problems that carry one. The TPTP language page lists fourteen roles
  including `logic` and describes what it is for; the `:==` rule quoted further down
  the same page lists thirteen and omits it. `Tptp.Bnf.Generator` corrects the list
  against the prose under `@documented_values`, with the citation and a build check
  that fails when the BNF catches up — the same discipline the misspelled SZS value
  gets. It is not a general licence to edit the vocabularies: an entry needs a
  citation to a TPTP source.
- `Tptp.Query.within?/2` is now a **partial** order and no longer a position
  comparison in a single list. The dialects are not a line — TCF and the
  non-classical languages are branches — and the old reading answered `true` for
  every pair, so `within?(:th1, :nxf)` and `within?(:tcf, :tf0)` were both true and
  an analyzer scoped to one branch was handed the other's files. It is therefore no
  longer usable as a sort comparator; `rank/1` is.

### Fixed

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

### Changed

- The SZS value the ontology page spells `CounterTautologyyPreserving` is now
  `:counter_tautology_preserving`, not `:counter_tautologyy_preserving`.
  `Tptp.Szs.Ontology.name/1` still answers the page's spelling, doubled `y` and
  all, and `from_string/1` still admits that spelling and no other — the name
  quotes the source, while the atom is this library's own identifier and every
  consumer has to pattern match on it. `Tptp.Szs.Generator` carries the override in
  `@name_atom_overrides` and fails the build if the page stops needing it.

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
  [CORPUS.md](CORPUS.md). A nightly workflow sweeps the library entire; a pull
  request sweeps one file in five.

### Notes

- Zero runtime dependencies. `yecc`, `:crypto`, `:inets` and `:ssl` ship with OTP.
- No atom is ever created from input. A custom Credo check enforces it, because the
  atom table is never collected and this library reads untrusted files.
- The SZS `isa` hierarchy is deliberately not modelled: it is published only as
  diagrams, and guessing at it would put unverifiable relations into a library whose
  contract is faithfulness.

[Unreleased]: https://github.com/jcschuster/tptp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jcschuster/tptp/releases/tag/v0.1.0
