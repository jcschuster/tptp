defmodule Tptp.DocumentationTest do
  @moduledoc """
  The documentation policy, enforced rather than remembered.

  Every module carries a `@moduledoc`, every public function and macro a `@doc`,
  every type and callback a `@typedoc` or `@doc`. Credo already insists on the
  first through `Credo.Check.Readability.ModuleDoc` and on `@spec` through
  `Credo.Check.Readability.Specs`; neither can see `@doc` or `@typedoc`, so this
  reads the docs chunk of every compiled module instead.

  This library is a ground layer for consumers that will read its documentation and
  not its source, and a type without a `@typedoc` is exactly the one a caller has to
  go and read the source for. Enforcing it here means it cannot decay quietly.

  Two exclusions, both principled:

    * `:tptp_parser` is generated Erlang from yecc and has no docs chunk at all.
      `Tptp.Parser` documents it on its behalf.
    * `@doc false` and `@impl` entries are deliberate — a callback implementation
      inherits the callback's documentation, and hiding an entry is a decision that
      was made, not one that was forgotten. Only a missing doc fails.
  """

  use ExUnit.Case, async: true

  @excluded [:tptp_parser]

  defp modules do
    :tptp |> Application.spec(:modules) |> Kernel.--(@excluded)
  end

  defp chunks do
    for module <- modules() do
      {:docs_v1, _anno, _language, _format, moduledoc, _meta, entries} = Code.fetch_docs(module)

      {module, moduledoc, entries}
    end
  end

  defp undocumented(kinds) do
    for {module, _moduledoc, entries} <- chunks(),
        {{kind, name, arity}, _anno, _signature, :none, _meta} <- entries,
        kind in kinds,
        do: "#{inspect(module)}.#{name}/#{arity}"
  end

  test "every module has a @moduledoc" do
    missing = for {module, :none, _entries} <- chunks(), do: inspect(module)

    assert missing == []
  end

  test "every public function and macro has a @doc" do
    assert undocumented([:function, :macro]) == []
  end

  test "every type has a @typedoc" do
    assert undocumented([:type]) == []
  end

  test "every callback has a @doc" do
    assert undocumented([:callback, :macrocallback]) == []
  end

  test "the policy is checking something" do
    {_module, _moduledoc, entries} = List.keyfind(chunks(), Tptp, 0)

    assert Enum.count(entries, &match?({{:function, _name, _arity}, _, _, _, _}, &1)) > 5
    assert length(modules()) > 40
  end
end
