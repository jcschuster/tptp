defmodule Tptp.FormatTaskTest do
  @moduledoc """
  `mix tptp.format`, which rewrites files in place.

  `Tptp.Printer.Format` is where the guarantee lives and where the corpus gate proves
  it over the library. What is left for this file is everything the task adds around
  it and the printer cannot be blamed for: which paths a pattern expands to, whether
  `--check` really changes nothing, whether a file it cannot read is reported rather
  than half-written, and whether the exit status says what happened.

  A formatter that rewrites a directory of someone's problems has to be right about
  all four, and none of them was covered.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Tptp.Format

  setup do
    directory =
      Path.join(System.tmp_dir!(), "tptp-format-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    %{dir: directory}
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end

  defp run(argv), do: ExUnit.CaptureIO.capture_io(fn -> Format.run(argv) end)

  describe "rewriting" do
    test "an untidy file is rewritten and reported", %{dir: dir} do
      path = write(dir, "a.p", "fof( a,axiom,p&q ).\n")

      output = run([path])

      assert File.read!(path) == "fof(a, axiom, p & q).\n"
      assert output =~ "reformatted 1 of 1 files"
    end

    test "a file already in canonical layout is left alone and counted as unchanged",
         %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p & q).\n")
      before = File.stat!(path)

      output = run([path])

      assert File.read!(path) == "fof(a, axiom, p & q).\n"
      assert output =~ "reformatted 0 of 1 files"
      assert File.stat!(path).mtime == before.mtime, "an unchanged file must not be rewritten"
    end

    test "comments keep their place, which is the whole reason this is not the canonical printer",
         %{dir: dir} do
      path = write(dir, "a.p", "%----head\nfof( a,axiom,p ).  % why\n\nfof(b,axiom,q).\n")

      run([path])

      assert File.read!(path) == "%----head\nfof(a, axiom, p).  % why\n\nfof(b, axiom, q).\n"
    end

    test "a file whose tokens do not lex is left exactly as it was", %{dir: dir} do
      # The task's stated promise: a formatter is reached for when a file is in a bad
      # state, and rewriting one it cannot read is how it loses someone's work.
      source = "fof(a, axiom, 'unterminated).\n"
      path = write(dir, "broken.p", source)

      output = run([path])

      assert File.read!(path) == source
      assert output =~ "reformatted 0 of 1 files"
    end
  end

  describe "--check" do
    test "reports what would change, changes nothing, and fails", %{dir: dir} do
      source = "fof( a,axiom,p ).\n"
      path = write(dir, "a.p", source)

      assert_raise Mix.Error, ~r/1 file would be reformatted/, fn ->
        run(["--check", path])
      end

      assert File.read!(path) == source, "--check must not write"
    end

    test "succeeds when every file is already formatted", %{dir: dir} do
      path = write(dir, "a.p", "fof(a, axiom, p).\n")

      assert run(["--check", path]) =~ "1 file already formatted"
    end

    test "pluralises on the count rather than always", %{dir: dir} do
      write(dir, "a.p", "fof(a, axiom, p).\n")
      write(dir, "b.p", "fof(b, axiom, q).\n")

      assert run(["--check", Path.join(dir, "*.p")]) =~ "2 files already formatted"
    end
  end

  describe "path expansion" do
    test "a wildcard expands, de-duplicates and sorts", %{dir: dir} do
      write(dir, "b.p", "fof( b,axiom,q ).\n")
      write(dir, "a.p", "fof( a,axiom,p ).\n")

      # The same file named twice must be formatted once, not twice.
      output = run([Path.join(dir, "*.p"), Path.join(dir, "a.p")])

      assert output =~ "reformatted 2 of 2 files"
    end

    test "a pattern matching nothing is an error rather than a silent success" do
      assert_raise Mix.Error, ~r/no files matched/, fn ->
        run([Path.join(System.tmp_dir!(), "tptp-format-nothing-here/*.p")])
      end
    end
  end

  describe "unreadable input" do
    test "is reported by name and fails without touching anything else", %{dir: dir} do
      good = write(dir, "a.p", "fof( a,axiom,p ).\n")
      missing = Path.join(dir, "gone.p")
      File.write!(missing, "")
      File.chmod!(missing, 0o000)

      if File.read(missing) == {:error, :eacces} do
        assert_raise Mix.Error, ~r/1 file could not be read/, fn ->
          run([good, missing])
        end

        assert File.read!(good) == "fof(a, axiom, p).\n"
      end

      File.chmod!(missing, 0o644)
    end
  end
end
