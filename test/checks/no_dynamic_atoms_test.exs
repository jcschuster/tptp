defmodule Tptp.Checks.NoDynamicAtomsTest do
  use ExUnit.Case, async: true

  alias Credo.Service.SourceFileAST
  alias Tptp.Checks.NoDynamicAtoms

  setup_all do
    Application.ensure_all_started(:credo)

    if Process.whereis(SourceFileAST) do
      :ok
    else
      {:ok, _pid} = SourceFileAST.start_link([])
      :ok
    end
  end

  test "flags the calls that turn input into atoms" do
    for call <- [
          "String.to_atom(functor)",
          "List.to_atom(chars)",
          ":erlang.binary_to_atom(name, :utf8)",
          ":erlang.list_to_atom(chars)",
          ":erlang.binary_to_term(payload)"
        ] do
      assert [_issue] = issues("def f(x), do: #{call}"),
             "#{call} should have been flagged"
    end
  end

  test "every forbidden call names a function that exists" do
    for {module, function} <- NoDynamicAtoms.forbidden() do
      {:module, ^module} = Code.ensure_loaded(module)

      assert Enum.any?(module.module_info(:exports), fn {name, _arity} -> name == function end),
             "#{inspect(module)}.#{function} is not a real function, so the check can " <>
               "never fire on it and its presence in the list is misleading"
    end
  end

  test "allows the guarded lookup into a closed vocabulary" do
    assert issues("def f(x), do: String.to_existing_atom(x)") == []
    assert issues("def f(x), do: Tptp.Bnf.Vocabulary.formula_role?(x)") == []
  end

  test "does not flag an unrelated function of the same name on another module" do
    assert issues("def f(x), do: MyThing.to_atom(x)") == []
  end

  defp issues(body) do
    "defmodule Sample do\n  #{body}\nend\n"
    |> Credo.SourceFile.parse("sample.ex")
    |> NoDynamicAtoms.run([])
  end
end
