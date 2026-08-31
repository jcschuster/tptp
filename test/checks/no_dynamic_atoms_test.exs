defmodule Tptp.Checks.NoDynamicAtomsTest do
  use ExUnit.Case, async: true

  alias Tptp.Checks.NoDynamicAtoms

  setup_all do
    Application.ensure_all_started(:credo)

    if Process.whereis(Credo.Service.SourceFileAST) do
      :ok
    else
      {:ok, _pid} = Credo.Service.SourceFileAST.start_link([])
      :ok
    end
  end

  test "flags the calls that turn input into atoms" do
    for call <- [
          "String.to_atom(functor)",
          "List.to_atom(chars)",
          ":erlang.binary_to_atom(name, :utf8)"
        ] do
      assert [_issue] = issues("def f(x), do: #{call}"),
             "#{call} should have been flagged"
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
