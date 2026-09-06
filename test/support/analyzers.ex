defmodule Tptp.Test.Analyzers do
  @moduledoc """
  Trivial `Tptp.Analyzer` implementations, so the dispatch tests have more than
  one contract to exercise.
  """

  defmodule FirstOrderOnly do
    @moduledoc "Reports one hint per file. Scoped to `[:fof]`, so dialect gating bites."
    @behaviour Tptp.Analyzer

    @impl true
    def id, do: :test_fof_only

    @impl true
    def label, do: "test: first-order only"

    @impl true
    def dialects, do: [:fof]

    @impl true
    def analyze(%Tptp.Analysis{} = analysis, _options) do
      span = Tptp.Span.new(root_id(analysis), 0, 0)
      count = map_size(analysis.table.symbols)
      [Tptp.Diagnostic.new("TEST0001", :info, span, "ran over #{count} symbols")]
    end

    defp root_id(%Tptp.Analysis{file: %Tptp.File{id: id}}), do: id
    defp root_id(%Tptp.Analysis{file: %Tptp.Unit{root: root}}), do: root
  end

  defmodule HigherOrderCap do
    @moduledoc "Accepts anything within TH0. Emits nothing; there to prove a wider scope runs on FOF."
    @behaviour Tptp.Analyzer

    @impl true
    def id, do: :test_th0_cap

    @impl true
    def label, do: "test: up to TH0"

    @impl true
    def dialects, do: [:th0]

    @impl true
    def analyze(%Tptp.Analysis{}, _options), do: []
  end

  defmodule Boom do
    @moduledoc "Always raises, so `run_all/3` has something to contain."
    @behaviour Tptp.Analyzer

    @impl true
    def id, do: :test_boom

    @impl true
    def label, do: "test: boom"

    @impl true
    def dialects, do: :any

    @impl true
    def analyze(_analysis, _options), do: raise("boom")
  end
end
