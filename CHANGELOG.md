# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[semantic versioning](https://semver.org/spec/v2.0.0.html) over its Elixir API.

Note that the package version and `Tptp.bnf_version/0` are two different numbers: the
latter is the TPTP release whose BNF the shipped parser was generated from, and it
moves when TPTP moves, not when this library does.

## [Unreleased]

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
- `include` resolution over a pluggable resolver — `Fs`, `Http`, `Cascade`, `Map`
  and the default `None` — with cycle detection, formula selection and a `Tptp.Unit`
  that keeps both the flattened statement list and the include tree.
- Eight lint rules over one fused walk, and `Tptp.Query.dialect/1`.
- Three printers: canonical, pretty (`Inspect.Algebra`) and format-preserving, the
  last of which backs `mix tptp.format` and provably changes no token.
- `Tptp.Szs` for the status lines provers print, over a generated ontology of the
  111 published SZS values.
- Diagnostics on every stage, tiered by code, never raised at the caller.

### Notes

- Zero runtime dependencies. `yecc`, `:crypto`, `:inets` and `:ssl` ship with OTP.
- No atom is ever created from input. A custom Credo check enforces it, because the
  atom table is never collected and this library reads untrusted files.
- The SZS `isa` hierarchy is deliberately not modelled: it is published only as
  diagrams, and guessing at it would put unverifiable relations into a library whose
  contract is faithfulness.

[Unreleased]: https://github.com/johannes-schuster/tptp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/johannes-schuster/tptp/releases/tag/v0.1.0
