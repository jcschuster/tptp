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
        enabled: [
          {Tptp.Checks.NoDynamicAtoms, []},
          {Credo.Check.Readability.Specs, files: %{included: ["lib/"]}}
        ],
        disabled: [
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
