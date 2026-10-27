# Contributing

Thanks for taking an interest. This page says how the repository is set up, what
CI checks, and how a change gets in. The design — what the library does and,
more importantly, what it refuses to do — is in the README's *Scope* section,
and a change that crosses it (type inference, elaboration, semantics) is better
raised as an issue first.

## Before you start

Open an issue for anything beyond a small fix. For a reading that disagrees with
the TPTP, the most useful report names the BNF rule or the documentation page
and gives the smallest input that shows it; for a library file, its name
(`PUZ001+1.p`) is enough.

## Setting up

The toolchain is in `.tool-versions` (any `~> 1.20` Elixir works). Then:

```bash
mix deps.get
mix check                   # format, compile --warnings-as-errors, credo --strict, test, dialyzer
mix test                    # unit and property tests
mix test --include corpus   # reads a TPTP library under $TPTP_ROOT
mix test --include network  # re-checks the vendored files against their pages
mix coveralls               # the suite with a coverage table
mix docs
```

## What CI checks

`ci.yml` runs on every push to `main` and every pull request: formatting, unused
lock entries, a forced `compile --warnings-as-errors`, `credo --strict`,
`docs --warnings-as-errors`, `hex.build`, the suite on two toolchains (one with
coverage) and Dialyzer. `generated.yml` regenerates from the vendored BNF and
fails on a stale generated file. `corpus.yml` reads one library file in five on a
pull request that touches the parser, and all of them nightly. `bnf.yml` looks
for a newer TPTP BNF every night and opens the pull request that vendors it.

## Conventions

- **Generated files are not edited.** `src/tptp_parser.yrl`,
  `lib/tptp/bnf/vocabulary.ex`, `lib/tptp/printer/shapes.ex`,
  `lib/tptp/szs/ontology.ex` and `test/support/bnf_oracle.ex` come from
  `mix tptp.gen`; change the generator, regenerate, commit both.
- **Vendored TPTP material is not edited either.** `priv/bnf/` carries the BNF and
  the SZS ontology unmodified, with their provenance in `NOTICE`; the TPTP's
  terms permit verbatim redistribution only. A new BNF arrives through
  `bnf.yml`, not by hand.
- **No atoms from input.** `mix credo --strict` includes `checks/no_dynamic_atoms.ex`,
  which fails on `String.to_atom/1` and its equivalents. A library that reads
  tens of thousands of untrusted files must not create atoms from them.
- **Spans are bytes, never copies.** Every leaf is a sub-binary of the file's
  `source`; a stage that copies text out of the input is a regression, and
  `bench/parse.exs` reports allocation alongside throughput so one is seen.
- **Documentation is enforced.** Every module has a `@moduledoc`, every public
  function a `@doc`, every type a `@typedoc`; `test/tptp/documentation_test.exs`
  checks the compiled docs chunk. Rationale a consumer needs goes in the docs,
  not in code comments.
- **CHANGELOG.** User-visible changes get an entry under `[Unreleased]` in
  `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)). The
  package version and `Tptp.bnf_version/0` are two different numbers; the latter
  moves only when the TPTP does.

## Releasing (maintainers)

Two paths, both through `release.yml`:

- **A BNF update.** `bnf.yml` opens a pull request labelled `bnf-update` that
  vendors the new BNF, regenerates, bumps the version (minor when the BNF takes
  something away, patch otherwise) and writes the CHANGELOG section. Review what
  it lists, merge, and the merge publishes to Hex and creates the tag and the
  GitHub release.
- **Anything else.** Set `@version` in `mix.exs`, the `## [x.y.z] - date` section
  in `CHANGELOG.md`, `version`/`date-released` in `CITATION.cff` and `version`
  in `.zenodo.json`; push the tag `vx.y.z`.

Hex is published through the workload identity of this repository (no stored
key); the GitHub release is what makes Zenodo mint the version's DOI under the
concept DOI the README and `CITATION.cff` carry.

## Licence

By contributing you agree that your contribution is licensed under the MIT
licence of this repository. The vendored TPTP material keeps its own terms
(see `NOTICE`).
