defmodule Tptp.Checks.NoDynamicAtoms do
  use Credo.Check,
    id: "TPTP001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Atoms are never garbage collected and the VM's table holds around a million
      of them. This library reads other people's files — tens of thousands of them
      in a corpus run — so turning a functor, a formula name or a role into an atom
      is a denial-of-service waiting to happen, not merely a leak.

      Every atom this library uses is created at compile time: node kinds and token
      categories come from the generated grammar, and the `:==` vocabularies come
      from `Tptp.Bnf.Vocabulary`. Where input must reach an atom at all, use
      `String.to_existing_atom/1` inside a closed vocabulary and handle the
      `ArgumentError`.

          # not this
          String.to_atom(functor)

          # this
          Tptp.Bnf.Vocabulary.formula_role?(role)
      """
    ]

  @forbidden [
    {String, :to_atom},
    {String, :to_charlist_atom},
    {List, :to_atom},
    {:erlang, :binary_to_atom},
    {:erlang, :list_to_atom}
  ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({{:., _, [module, function]}, meta, _args} = ast, issues, issue_meta) do
    if forbidden?(module, function) do
      {ast, [issue_for(issue_meta, meta[:line], module, function) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp forbidden?(module, function) do
    Enum.any?(@forbidden, fn {forbidden_module, forbidden_function} ->
      function == forbidden_function and name_of(module) == forbidden_module
    end)
  end

  defp name_of({:__aliases__, _meta, parts}), do: Module.concat(parts)
  defp name_of(atom) when is_atom(atom), do: atom
  defp name_of(_other), do: nil

  defp issue_for(issue_meta, line, module, function) do
    format_issue(issue_meta,
      message: "#{inspect(module_label(module))}.#{function} creates atoms from input",
      trigger: "#{function}",
      line_no: line
    )
  end

  defp module_label({:__aliases__, _meta, parts}), do: Module.concat(parts)
  defp module_label(atom), do: atom
end
