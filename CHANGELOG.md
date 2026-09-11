# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/spec/v2.0.0.html) over its Elixir API.

Note that the package version and `Tptp.bnf_version/0` are two different numbers: the
latter is the TPTP release whose BNF the shipped parser was generated from, and it
moves when TPTP moves, not when this library does.

## [Unreleased]

## [0.1.0] - 2026-09-11

First release. The parser is generated from TPTP BNF v9.3.1.3, and the SZS values are
transcribed from the ontology published at <https://szs.tptp.org>. Every problem and
axiom file of TPTP v9.3.1 is read through it; the four it refuses are defects in the
files, and are recorded under Notes below.

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
- Lint rules over one fused walk. The undeclared-symbol rule applies to the dialects
  written with `thf` alone — TH0, TH1, DH0, DH1 and NHF — since the TPTP language
  page gives TFF, TXF, TCF and NXF default typing, `($i,...,$i) > $o` for a predicate
  and `($i,...,$i) > $i` for a function, and says THF "does not admit default
  typing".
- `Tptp.Query`: the dialect of a file or a unit, `rank/1` and `dialects/0` for the
  total listing order, and `within?/2` as a **partial** order over the dialects. They
  are not a line — TCF and the non-classical languages are branches — so `within?/2`
  answers a containment question and is not a sort comparator.

  It recognises the dependently typed higher-order dialects, DH0 and DH1. What a `!>`
  binds is the whole difference: `!>[A: $tType]` abstracts over a type and is
  polymorphism, `!>[A: nat]` abstracts over a term and is a dependent type, and the
  same distinction separates `list: $tType > $tType` from `fin: nat > $tType`.
  Checked against the TPTP's own `SPC` header over the 26,021 problems of v9.3.1 that
  carry one: 85 DH0 and 46 DH1 identified exactly, with no TH0 or TH1 problem misread
  as either.

  TXF is recognised by its FOOL constructs and not only by the three that have a node
  kind of their own. A `$o` variable, a formula or `$true`/`$false` in a term
  position, a declared `$o` argument type, `$ite` and `$distinct` all carry it, so
  all 340 TX0 problems in the library are classified correctly, with no false
  positive among the 2,251 TF0, 679 TF1 and 148 TX1 problems beside them.
- `Tptp.analyze/2` and `Tptp.Analysis`: the file, its diagnostics, the symbol table
  and the dialect from a single traversal, `Tptp.Lint.scan/2`, of which
  `Tptp.Lint.run/2`, `run_unit/2` and `table/1` are projections. An opt-in line index
  turns span offsets into line and column once rather than once per diagnostic, and
  input that does not parse still yields an analysis carrying the diagnostics that
  record the failure.
- `Tptp.Analyzer`, a behaviour for a named diagnostic producer over a
  `Tptp.Analysis`, with `run_all/3` dispatching by dialect, `{:exactly, dialects}`
  for an analyzer that means the dialects it named, and a raising analyzer contained
  as a `TPTP0800` diagnostic naming it. `Tptp.Lint` implements it as `:tptp_lint`.
- Three printers: canonical, pretty (`Inspect.Algebra`) and format-preserving, the
  last of which backs `mix tptp.format` and provably changes no token.
- `Inspect` implementations for `Tptp.File`, `Tptp.Unit`, `Tptp.Node`,
  `Tptp.Analysis`, `Tptp.Lint.Table` and both statement structs, each printing a
  summary in constant time rather than the source binary and every node that points
  into it. `inspect(term, structs: false)` still shows the map.
- `Tptp.Szs` for the status lines provers print, over the 112 published SZS values.
- Diagnostics on every stage, tiered by code, never raised at the caller.
- `mix tptp.lint`, a command line over `Tptp.analyze/2`. It prints
  `path:line:column: severity: message [CODE]` and exits non-zero where anything at
  or above `--severity` was reported; `--include` resolves the graph and lints the
  unit, `--only` and `--suppress` filter by code, and `--format json` emits one
  object per line.
- `mix tptp.corpus`, which reads a local TPTP library through the parser and writes
  [CORPUS.md](reports/CORPUS.md), and `mix tptp.census`, which records where that
  library applies a type constructor and in which dialects
  ([CENSUS.md](reports/CENSUS.md)) — including the files applying one at arity ≥ 2
  over a type variable, which is the one shape an elaborator cannot monomorphise into
  a fresh sort. A nightly workflow sweeps the library entire; a pull request sweeps
  one file in five.

  Both sweeps parse each file in its own process under a `max_heap_size` ceiling,
  with `--heap` as the total across workers and a serial retry for a file that
  exceeds its share. A file's size does not predict its parse: the corpus runs from
  2.5 to 111 bytes per CST node, so bounding a sweep by bytes of source bounds the
  wrong quantity.
- [FINDINGS.md](reports/FINDINGS.md): what the four unparseable `SYN000*2.p` files
  were hiding from every stage after the parser. With the announced fix applied to
  copies, two further defects in those files surfaced, and a sweep of the library for
  anything else a skipped file could conceal showed three rules of this library's to
  be wrong. Each finding carries its citation and a command reproducing it, and the
  checks that found nothing are recorded with them.

### Notes

- Zero runtime dependencies. `yecc`, `:crypto`, `:inets` and `:ssl` ship with OTP.
- No atom is ever created from input. A custom Credo check enforces it, because the
  atom table is never collected and this library reads untrusted files.
- The TPTP is this library's ground truth: where the two disagree the parser is
  wrong, being generated from the published BNF, and correcting it by hand would make
  it a parser for something else. Where the TPTP's own published sources disagreed
  with each other, the disagreement was reported upstream rather than worked around.
  Six were carried during development; BNF v9.3.1.3 and the SZS ontology's move to
  <https://szs.tptp.org> resolve all of them.
- Four library files do not parse, and both reasons are defects in the files.
  `SYN000-2.p`, `SYN000+2.p` and `SYN000^2.p` use `theory(equality)` as an inference
  parent, which `<source>` has not derived since v9.3.1.2; that was fixed upstream on
  10/09/26 — see <https://tptp.org/TPTP/Distribution/BuggedProblems-v9.3.1.txt> — and
  all three parse against the corrected text, so they leave
  `Mix.Tasks.Tptp.Corpus.known_failures/0` when the distributed tarball carries the
  edit. `SYN000_2.p` carries a second and independent one, reachable only once the
  first was resolved: it writes `introduced(assumption,[from,the,world,[]])` where
  both the BNF and the TPTP language page state
  `introduced(<intro_type>,<useful_info>,<parents>)`, and the other three dialects'
  copies of the same file write `introduced(assumption,[from,the,world],[])`.
  Reported upstream on 2026-09-11.
- `SYN000^2.p` carries a further defect that only surfaces once it parses: its
  `let_tuple_4` applies `qll @ a @ b`, and nothing declares `qll`. THF admits no
  default typing, so that is an error, and `TPTP0501` reports it. `ql`, declared as
  `$int > $int > $o`, has exactly the type the use needs, so it is presumably a
  typo. Reported upstream on 2026-09-11.
- The SZS `isa` hierarchy is deliberately not modelled: it is published only as
  diagrams, and guessing at it would put unverifiable relations into a library whose
  contract is faithfulness.
- One condition the TPTP states is not checked: "If a symbol's type is declared more
  than once, and the types are not the same, that's an error." A symbol is a name and
  an arity — "Symbols may be overloaded with different arity signatures, and are
  treated as different symbols" — so this compares two declarations at the same
  arity, and `Tptp.Lint.Table` keys on the name alone and cannot express it yet.

[Unreleased]: https://github.com/jcschuster/tptp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jcschuster/tptp/releases/tag/v0.1.0
