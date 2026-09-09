defmodule Tptp.LintTaskTest do
  @moduledoc """
  `mix tptp.lint`, the command line over `Tptp.analyze/2`.

  Everything it reports is the library's; what it owns is the parts a shell needs and
  Elixir does not — which paths a pattern expands to, how a diagnostic renders, which
  ones are filtered, whether the exit status says what happened, and whether
  `include` is followed. Those are what is tested here.

  The exit status matters most. A linter that prints findings and exits zero is a
  linter nobody's CI notices.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Tptp.Lint

  setup do
    directory =
      Path.join(System.tmp_dir!(), "tptp-lint-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    %{dir: directory}
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    path
  end

  defp run(argv), do: ExUnit.CaptureIO.capture_io(fn -> Lint.run(argv) end)

  describe "reporting" do
    test "renders a finding as path:line:column: severity: message [CODE]", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axim, p).\n")

      output = run([path, "--severity", "none"])

      assert output =~ "a.p:1:8: warning: \"axim\" is not a TPTP formula role [TPTP0401]"
      assert output =~ "hint:"
    end

    test "a clean file reports nothing but still says what it read", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\n")

      assert run([path]) =~ "1 file, 0 reported"
    end

    test "a parse error is reported with its position", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\nwibble.\n")

      assert_raise Mix.Error, fn -> run([path]) end
    end

    test "--quiet prints nothing and still fails", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\nwibble.\n")

      assert ExUnit.CaptureIO.capture_io(fn ->
               assert_raise Mix.Error, fn -> Lint.run([path, "--quiet"]) end
             end) == ""
    end
  end

  describe "exit status" do
    test "warnings alone succeed at the default threshold", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axim, p).\n")

      assert run([path]) =~ "1 reported"
    end

    test "--severity warning makes a warning fail", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axim, p).\n")

      assert_raise Mix.Error, ~r/1 diagnostic at warning or above/, fn ->
        run([path, "--severity", "warning"])
      end
    end

    test "--severity none never fails", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\nwibble.\n")

      assert run([path, "--severity", "none"]) =~ "TPTP0201"
    end

    test "an unknown severity is refused rather than guessed at", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\n")

      assert_raise Mix.Error, ~r/unknown severity/, fn -> run([path, "--severity", "loud"]) end
    end
  end

  describe "filtering by code" do
    @noisy "fof(a, axim, p(x)).\nfof(a, axiom, p(x, y)).\n"

    test "--only keeps one code", %{dir: dir} do
      path = write(dir, "a.p", @noisy)
      output = run([path, "--only", "TPTP0503", "--severity", "none"])

      assert output =~ "TPTP0503"
      refute output =~ "TPTP0401"
    end

    test "--suppress drops one code", %{dir: dir} do
      path = write(dir, "a.p", @noisy)
      output = run([path, "--suppress", "TPTP0401", "--severity", "none"])

      refute output =~ "TPTP0401"
      assert output =~ "TPTP0503"
    end

    test "both options are repeatable", %{dir: dir} do
      path = write(dir, "a.p", @noisy)

      output =
        run([path, "--only", "TPTP0401", "--only", "TPTP0503", "--severity", "none"])

      assert output =~ "TPTP0401"
      assert output =~ "TPTP0503"
      refute output =~ "TPTP0402"
    end
  end

  describe "--format json" do
    test "emits one object per line with the fields a tool wants", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axim, p).\n")

      [line] =
        [path, "--format", "json", "--severity", "none"]
        |> run()
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "{"))

      assert line =~ ~s("code":"TPTP0401")
      assert line =~ ~s("severity":"warning")
      assert line =~ ~s("line":1)
      assert line =~ ~s("column":8)
      assert line =~ ~s("file":)
    end

    test "an unknown format is refused", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\n")

      assert_raise Mix.Error, ~r/unknown format/, fn -> run([path, "--format", "xml"]) end
    end
  end

  describe "includes" do
    setup %{dir: dir} do
      write(dir, "Axioms/sig.ax", "tff(t1, type, p: $i > $o).\ntff(t2, type, c: $i).\n")
      path = write(dir, "problem.p", "include('Axioms/sig.ax').\ntff(a, axiom, p(c)).\n")

      %{problem: path}
    end

    test "without --include the symbols look undeclared", %{problem: problem} do
      output = run([problem, "--severity", "none"])

      assert output =~ "TPTP0501"
    end

    test "--root resolves the graph and the finding goes away", %{dir: dir, problem: problem} do
      output = run([problem, "--root", dir, "--severity", "none"])

      refute output =~ "TPTP0501"
    end
  end

  describe "path expansion" do
    test "a wildcard expands and de-duplicates", %{dir: dir} do
      write(dir, "a.p", "fof(a, axiom, p).\n")
      write(dir, "b.p", "fof(b, axiom, q).\n")

      assert run([Path.join(dir, "*.p"), Path.join(dir, "a.p")]) =~ "2 files, 0 reported"
    end

    test "a pattern matching nothing is an error rather than a silent success" do
      assert_raise Mix.Error, ~r/no files matched/, fn ->
        run([Path.join(System.tmp_dir!(), "tptp-lint-nothing/*.p")])
      end
    end
  end
end
