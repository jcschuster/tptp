# Rationale that has nowhere else to live: a config file has no @moduledoc, and the
# two departures from Credo's defaults below are decisions rather than preferences.
#
# `checks` is a map with `:extra` and `:disabled`, which *extends* Credo's default
# set. `:enabled` would have replaced it, leaving the two custom checks running and
# the other sixty-seven not — the failure mode is silent, because a config that runs
# two checks reports no issues just as convincingly as a clean tree does.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "checks/", "test/", "bench/", "mix.exs"],
        excluded: ["lib/tptp/bnf/vocabulary.ex"]
      },
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [
          {Tptp.Checks.NoDynamicAtoms, []},
          {Credo.Check.Readability.Specs, files: %{included: ["lib/"]}},
          # `Tptp.Lexer.emit/9` and `quoted/9` thread the whole scan state as bare
          # arguments. Bundling it into a struct or a map would allocate once per
          # token in the hot loop, which is the one thing that module is written not
          # to do, so the ceiling is raised to what those two need rather than the
          # design being changed to suit the default.
          {Credo.Check.Refactor.FunctionArity, max_arity: 9}
        ],
        disabled: [
          # Fires on `@doc` heredocs whose doctests contain literal quotes, such as
          # `["X", "X"]` as an expected result. Credo intends to exclude heredocs —
          # `StringSigils` calls `Heredocs.replace_with_spaces/1` first — and does not
          # do so reliably here. A doctest cannot be rewritten as a sigil without
          # ceasing to be a doctest, so there is no finding to act on.
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
