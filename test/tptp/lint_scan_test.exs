defmodule Tptp.LintScanTest do
  use ExUnit.Case, async: false

  alias Tptp.Lint

  @source """
  tff(t_p, type, p: $i > $o).
  tff(t_q, type, q: ($i * $i) > $o).
  tff(t_a, type, a: $i).
  tff(ax1, axiom, p(a)).
  tff(ax2, axiom, q(a, a) | ~ p(a)).
  fof(f1, axiom, ![X]: (big(X) => small(X))).
  fof(f2, conjecture, big(a) => small(a)).
  fof(f3, axiom, r, inference(rule, [], [f1, f2])).
  """

  test "scan/2 walks once where run/2 followed by table/1 walked twice" do
    {:ok, file, []} = Tptp.from_string(@source)

    fused = observe_calls(fn -> Lint.scan(file) end)
    split = observe_calls(fn -> Lint.run(file) && Lint.table(file) end)

    assert fused > 0
    assert split == 2 * fused
  end

  defp observe_calls(fun) do
    mfa = {Tptp.Lint.Collect, :observe, 3}
    Code.ensure_loaded!(Tptp.Lint.Collect)
    1 = :erlang.trace_pattern(mfa, true, [:call_count])
    1 = :erlang.trace_pattern(mfa, :restart, [:call_count])

    fun.()

    {:call_count, count} = :erlang.trace_info(mfa, :call_count)
    count
  end
end
