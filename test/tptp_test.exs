defmodule TptpTest do
  use ExUnit.Case, async: true

  doctest Tptp
  doctest Tptp.File
  doctest Tptp.Statement

  alias Tptp.Diagnostic

  @tmp Path.join(System.tmp_dir!(), "tptp-api-test")

  setup_all do
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  defp write!(name, contents) do
    path = Path.join(@tmp, name)
    File.write!(path, contents)
    path
  end

  describe "bnf_version/0" do
    test "matches the vendored file" do
      assert Tptp.bnf_version() == Tptp.Bnf.version!(Tptp.Bnf.vendored_path!())
    end
  end

  describe "from_string/2" do
    test "reads statements, comments and diagnostics" do
      {:ok, file, []} =
        Tptp.from_string("% a comment\nfof(a, axiom, p).\ninclude('b.ax').\n")

      assert Enum.map(file.statements, & &1.__struct__) == [
               Tptp.Statement.Annotated,
               Tptp.Statement.Include
             ]

      assert length(file.comments) == 1
      assert file.bnf_version == Tptp.bnf_version()
      assert file.path == nil
      assert file.id == 0
    end

    test "an empty source is a file with nothing in it" do
      {:ok, file, []} = Tptp.from_string("")

      assert file.statements == []
      assert file.comments == []
      assert file.source == ""
    end

    test "it never fails, it only reports" do
      {:ok, file, diagnostics} = Tptp.from_string("wibble. fof(a, axiom, p q). fof(b, axiom, r).")

      assert Enum.map(diagnostics, & &1.code) == ["TPTP0201", "TPTP0301"]
      assert Enum.map(file.statements, & &1.name.text) == ["b"]
    end

    test "diagnostics come back in reading order" do
      {:ok, _file, diagnostics} = Tptp.from_string("fof(a,axiom,p q). wibble. fof(c,axiom,r s).")

      offsets = Enum.map(diagnostics, & &1.span.offset)
      assert offsets == Enum.sort(offsets)
    end

    test "the file id is stamped into every span" do
      {:ok, _file, [diagnostic]} = Tptp.from_string("wibble.", file: 7)

      assert diagnostic.span.file == 7
    end

    test "max_statements stops early and says so" do
      source = String.duplicate("fof(a, axiom, p).\n", 100)
      {:ok, file, [diagnostic]} = Tptp.from_string(source, max_statements: 10)

      assert length(file.statements) == 10
      assert diagnostic.code == "TPTP0002"
      assert diagnostic.severity == :warning
      assert diagnostic.message =~ "10 statements"
    end

    test "max_statements is not reached when the file is shorter" do
      {:ok, file, []} = Tptp.from_string("fof(a, axiom, p).", max_statements: 10)

      assert length(file.statements) == 1
    end
  end

  describe "from_string!/2" do
    test "returns the file when nothing is error-severity" do
      assert %Tptp.File{} = Tptp.from_string!("fof(a, axiom, p).")
    end

    test "raises Tptp.Error carrying every diagnostic" do
      error = assert_raise(Tptp.Error, fn -> Tptp.from_string!("wibble. also_wibble.") end)

      assert Enum.map(error.diagnostics, & &1.code) == ["TPTP0201", "TPTP0201"]
      assert error.message =~ "2 problems in the given source"
      assert error.message =~ "1:1: error"
    end

    test "the message names the path when there is one" do
      path = write!("broken.p", "wibble.\n")
      error = assert_raise(Tptp.Error, fn -> Tptp.from_file!(path) end)

      assert error.message =~ path
      assert error.path == path
    end

    test "a warning alone does not raise" do
      source = String.duplicate("fof(a, axiom, p).\n", 5)
      file = Tptp.from_string!(source, max_statements: 2)

      assert length(file.statements) == 2
    end
  end

  describe "from_file/2" do
    test "reads a file and records its path" do
      path = write!("good.p", "fof(a, axiom, p).\n")
      {:ok, file, []} = Tptp.from_file(path)

      assert file.path == path
      assert length(file.statements) == 1
    end

    test "an unreadable file is the one failure case" do
      {:error, [diagnostic]} = Tptp.from_file(Path.join(@tmp, "absent.p"))

      assert diagnostic.code == "TPTP0001"
      assert diagnostic.message =~ "no such file or directory"
    end

    test "from_file! raises on an unreadable file" do
      error = assert_raise(Tptp.Error, fn -> Tptp.from_file!(Path.join(@tmp, "absent.p")) end)

      assert [%Diagnostic{code: "TPTP0001"}] = error.diagnostics
    end

    test "an explicit path option is not overwritten" do
      path = write!("named.p", "fof(a, axiom, p).\n")
      {:ok, file, []} = Tptp.from_file(path, path: "as-reported.p")

      assert file.path == "as-reported.p"
    end

    test "includes are recorded, never followed" do
      path = write!("includer.p", "include('absent-on-purpose.ax').\nfof(a, axiom, p).\n")
      {:ok, file, []} = Tptp.from_file(path)

      assert file |> Tptp.File.includes() |> Enum.map(&Tptp.Statement.Include.path/1) ==
               ["absent-on-purpose.ax"]
    end
  end

  describe "streaming" do
    test "stream_string! yields one result per statement" do
      results =
        "fof(a,axiom,p). wibble. fof(c,axiom,r)." |> Tptp.stream_string!() |> Enum.to_list()

      assert [{:ok, _a, []}, {:error, [_diagnostic]}, {:ok, _c, []}] = results
    end

    test "it is lazy" do
      source = String.duplicate("fof(a,axiom,p).\n", 100_000)

      assert source |> Tptp.stream_string!() |> Enum.take(2) |> length() == 2
    end

    test "streaming and reading eagerly agree on the statements" do
      source = "fof(a,axiom,p). include('b.ax'). cnf(c,axiom,q | ~r)."
      {:ok, file, []} = Tptp.from_string(source)

      streamed =
        source |> Tptp.stream_string!() |> Enum.map(fn {:ok, statement, []} -> statement end)

      assert streamed == file.statements
    end

    test "stream_file! reads from disk" do
      path = write!("streamed.p", "fof(a,axiom,p).\nfof(b,axiom,q).\n")

      assert path |> Tptp.stream_file!() |> Enum.count() == 2
    end

    test "stream_file! raises on an unreadable file, like File.stream!" do
      assert_raise File.Error, fn ->
        Path.join(@tmp, "absent.p") |> Tptp.stream_file!() |> Enum.to_list()
      end
    end
  end

  describe "Tptp.File" do
    setup do
      source = """
      % a header comment
      fof(one, axiom, p(a)).
      include('b.ax', [one]).
      cnf(two, axiom, q | ~r).
      """

      {:ok, file, []} = Tptp.from_string(source, path: "sample.p")
      %{parsed: file, source: source}
    end

    test "includes/1 and formulae/1 partition the statements", %{parsed: file} do
      assert length(Tptp.File.includes(file)) == 1
      assert length(Tptp.File.formulae(file)) == 2

      assert length(Tptp.File.includes(file)) + length(Tptp.File.formulae(file)) ==
               length(file.statements)
    end

    test "digest/1 is the SHA-256 of the source", %{parsed: file, source: source} do
      assert Tptp.File.digest(file) == :crypto.hash(:sha256, source)
    end

    test "statement_at/2 finds the statement under an offset", %{parsed: file, source: source} do
      offset = :binary.match(source, "include") |> elem(0)

      assert %Tptp.Statement.Include{} = Tptp.File.statement_at(file, offset)
    end

    test "statement_at/2 answers nil between statements", %{parsed: file} do
      assert Tptp.File.statement_at(file, 0) == nil
    end

    test "node_at/2 descends to the innermost node", %{parsed: file, source: source} do
      offset = :binary.match(source, "p(a)") |> elem(0)

      assert Tptp.File.node_at(file, offset).kind == :functor
    end

    test "format_diagnostics/1 renders against one line index" do
      {:ok, file, _diagnostics} = Tptp.from_string("fof(a,axiom,p).\nwibble.\n", path: "x.p")

      assert Tptp.File.format_diagnostics(file) == [
               "x.p:2:1: error: `wibble` does not start a TPTP statement [TPTP0201]"
             ]
    end

    test "any_errors?/1 separates warnings from errors" do
      source = String.duplicate("fof(a,axiom,p).\n", 5)
      {:ok, warned, _diagnostics} = Tptp.from_string(source, max_statements: 2)
      {:ok, broken, _diagnostics} = Tptp.from_string("wibble.")

      refute Tptp.File.any_errors?(warned)
      assert Tptp.File.any_errors?(broken)
    end
  end

  describe "detach/1" do
    test "a detached statement owns its bytes" do
      source = String.duplicate("% padding\n", 500) <> "fof(a, axiom, p(bcd))."
      {:ok, file, []} = Tptp.from_string(source)
      detached = file.statements |> hd() |> Tptp.detach()

      for root <- Tptp.Statement.roots(detached),
          node <- Tptp.Node.walk(root),
          node.text != nil do
        assert :binary.referenced_byte_size(node.text) == byte_size(node.text)
      end
    end

    test "detaching preserves the tree" do
      {:ok, file, []} = Tptp.from_string("fof(a, axiom, p(b) & q).")
      statement = hd(file.statements)

      assert statement |> Tptp.detach() |> Map.get(:formula) |> Tptp.Node.shape() ==
               Tptp.Node.shape(statement.formula)
    end

    test "an include detaches too" do
      {:ok, file, []} = Tptp.from_string("include('a.ax', [b]).")
      detached = file.statements |> hd() |> Tptp.detach()

      assert Tptp.Statement.Include.path(detached) == "a.ax"
      assert Tptp.Statement.Include.selected(detached) == ["b"]
    end
  end
end
