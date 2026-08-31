defmodule Tptp.ResolverTest do
  use ExUnit.Case, async: true

  doctest Tptp.Resolver
  doctest Tptp.Resolver.Http

  alias Tptp.Resolver

  @tmp Path.join(System.tmp_dir!(), "tptp-resolver-test")

  setup_all do
    File.rm_rf!(@tmp)
    File.mkdir_p!(Path.join([@tmp, "library", "Axioms"]))
    File.mkdir_p!(Path.join([@tmp, "library", "Problems", "PUZ"]))
    File.mkdir_p!(Path.join(@tmp, "local"))

    File.write!(Path.join([@tmp, "library", "Axioms", "shared.ax"]), "fof(library, axiom, p).\n")
    File.write!(Path.join([@tmp, "local", "shared.ax"]), "fof(local, axiom, p).\n")
    File.write!(Path.join([@tmp, "library", "beside.ax"]), "fof(beside, axiom, p).\n")

    on_exit(fn -> File.rm_rf!(@tmp) end)

    %{library: Path.join(@tmp, "library"), local: Path.join(@tmp, "local")}
  end

  describe "safe?/1" do
    test "accepts an ordinary TPTP include name" do
      assert Resolver.safe?("Axioms/SET007+0.ax")
      assert Resolver.safe?("a.ax")
    end

    test "refuses anything absolute or climbing" do
      refute Resolver.safe?("/etc/passwd")
      refute Resolver.safe?("../secret.ax")
      refute Resolver.safe?("Axioms/../../etc/passwd")
      refute Resolver.safe?("")
    end
  end

  describe "Tptp.Resolver.None" do
    test "declines without complaining" do
      assert Resolver.resolve(Tptp.Resolver.None, "a.ax", nil) == :not_followed
    end
  end

  describe "Tptp.Resolver.Map" do
    test "answers from its map" do
      resolver = {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a, axiom, p)."}}

      assert {:ok, "a.ax", "fof(a, axiom, p)."} = Resolver.resolve(resolver, "a.ax", nil)
    end

    test "matches names exactly, without guessing at paths" do
      resolver = {Tptp.Resolver.Map, files: %{"Axioms/a.ax" => "fof(a, axiom, p)."}}

      assert {:error, reason} = Resolver.resolve(resolver, "a.ax", nil)
      assert reason =~ "not in the resolver's map"
    end

    test "an empty map answers nothing" do
      assert {:error, _reason} = Resolver.resolve(Tptp.Resolver.Map, "a.ax", nil)
    end
  end

  describe "Tptp.Resolver.Fs" do
    test "finds a file under an explicit root", %{library: library} do
      resolver = {Tptp.Resolver.Fs, root: library, cwd: false}

      assert {:ok, path, "fof(library, axiom, p).\n"} =
               Resolver.resolve(resolver, "Axioms/shared.ax", nil)

      assert Path.expand(path) == path
    end

    test ":root takes a list, tried in order", %{library: library, local: local} do
      first = {Tptp.Resolver.Fs, root: [local, library], cwd: false}
      second = {Tptp.Resolver.Fs, root: [library, local], cwd: false}

      assert {:ok, _p, "fof(local, axiom, p).\n"} = Resolver.resolve(first, "shared.ax", nil)

      assert {:ok, _p, "fof(library, axiom, p).\n"} =
               Resolver.resolve(second, "Axioms/shared.ax", nil)
    end

    test "the including file's own directory comes first", %{library: library, local: local} do
      from = Path.join(library, "problem.p")
      resolver = {Tptp.Resolver.Fs, root: local, cwd: false}

      assert {:ok, _path, "fof(beside, axiom, p).\n"} =
               Resolver.resolve(resolver, "beside.ax", from)
    end

    test "an unfound name reports where it looked", %{library: library} do
      resolver = {Tptp.Resolver.Fs, root: library, cwd: false}

      assert {:error, reason} = Resolver.resolve(resolver, "absent.ax", nil)
      assert reason =~ "was not found"
      assert reason =~ library
    end

    test "it refuses to climb out, whatever the root", %{library: library} do
      resolver = {Tptp.Resolver.Fs, root: library, cwd: false}

      assert {:error, reason} = Resolver.resolve(resolver, "../local/shared.ax", nil)
      assert reason =~ "may not name an absolute path or climb out"

      assert {:error, _reason} = Resolver.resolve(resolver, "/etc/passwd", nil)
    end

    test "roots/2 reports the search order", %{library: library} do
      roots = Tptp.Resolver.Fs.roots("/somewhere/problem.p", root: library, cwd: false)

      assert ["/somewhere", ^library] = roots
    end
  end

  describe "Tptp.Resolver.Cascade" do
    test "takes the first resolver that answers" do
      resolver =
        {Tptp.Resolver.Cascade,
         resolvers: [
           {Tptp.Resolver.Map, files: %{}},
           {Tptp.Resolver.Map, files: %{"a.ax" => "fof(second, axiom, p)."}}
         ]}

      assert {:ok, "a.ax", "fof(second, axiom, p)."} = Resolver.resolve(resolver, "a.ax", nil)
    end

    test "reports every reason when all of them fail" do
      resolver =
        {Tptp.Resolver.Cascade,
         resolvers: [
           {Tptp.Resolver.Map, files: %{}},
           {Tptp.Resolver.Fs, root: "/nowhere", cwd: false}
         ]}

      assert {:error, reason} = Resolver.resolve(resolver, "a.ax", nil)
      assert reason =~ "not in the resolver's map"
      assert reason =~ "was not found"
    end

    test "a decline stops the cascade" do
      resolver =
        {Tptp.Resolver.Cascade,
         resolvers: [
           Tptp.Resolver.None,
           {Tptp.Resolver.Map, files: %{"a.ax" => "fof(a,axiom,p)."}}
         ]}

      assert Resolver.resolve(resolver, "a.ax", nil) == :not_followed
    end

    test "an empty cascade says so" do
      assert {:error, reason} = Resolver.resolve(Tptp.Resolver.Cascade, "a.ax", nil)
      assert reason =~ "no resolver was configured"
    end
  end

  describe "Tptp.Resolver.Http" do
    test "maps an axiom name to the Axioms category" do
      assert Tptp.Resolver.Http.url("Axioms/SET007+0.ax") ==
               "https://tptp.org/cgi-bin/SeeTPTP?Category=Axioms&File=SET007%2B0.ax"

      assert Tptp.Resolver.Http.url("SET007+0.ax") == Tptp.Resolver.Http.url("Axioms/SET007+0.ax")
    end

    test "maps a problem name to its domain" do
      assert Tptp.Resolver.Http.url("Problems/PUZ/PUZ001+1.p") ==
               "https://tptp.org/cgi-bin/SeeTPTP?Category=Problems&Domain=PUZ&File=PUZ001%2B1.p"

      assert Tptp.Resolver.Http.url("PUZ001+1.p") ==
               Tptp.Resolver.Http.url("Problems/PUZ/PUZ001+1.p")
    end

    test "the + in a TPTP name survives encoding" do
      assert Tptp.Resolver.Http.url("PUZ123^5.p") =~ "File=PUZ123%5E5.p"
      refute Tptp.Resolver.Http.url("SET007+0.ax") =~ "SET007 0.ax"
    end

    test "the base url can be pointed elsewhere" do
      assert Tptp.Resolver.Http.url("a.ax", base_url: "http://localhost:4000/see") ==
               "http://localhost:4000/see?Category=Axioms&File=a.ax"
    end

    test "it refuses an unsafe name without reaching the network" do
      assert {:error, reason} = Resolver.resolve(Tptp.Resolver.Http, "../../etc/passwd", nil)
      assert reason =~ "may not name an absolute path"
    end

    test "a cached body is served without reaching the network" do
      dir = Path.join(@tmp, "cache")
      options = [cache_dir: dir, base_url: "http://127.0.0.1:1/see"]
      url = Tptp.Resolver.Http.url("a.ax", options)

      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, Base.encode16(:crypto.hash(:sha256, url), case: :lower)),
        "fof(cached, axiom, p)."
      )

      assert {:ok, ^url, "fof(cached, axiom, p)."} =
               Resolver.resolve({Tptp.Resolver.Http, options}, "a.ax", nil)
    end

    test "an unreachable host is a reason, not a raise" do
      options = [cache_dir: false, base_url: "http://127.0.0.1:1/see", timeout: 500]

      assert {:error, reason} = Resolver.resolve({Tptp.Resolver.Http, options}, "a.ax", nil)
      assert reason =~ "could not be fetched"
    end

    test "a SeeTPTP page is unwrapped, anchors and all" do
      page = """
      <html><head><title>TPTP Problem File: X.p</title></head><body>
      <H2>TPTP Problem File: X.p</H2>
      <pre>
      %----A comment
      <A NAME="one"></A>fof(one,axiom,
          ( p &lt;=> q ) ).

      <A NAME="two"></A>fof(two,axiom,
          ( a & b ) ).
      </pre>
      </body></html>
      """

      assert {:ok, contents} = Tptp.Resolver.Http.contents(page)

      refute contents =~ "<A NAME"
      refute contents =~ "&lt;"
      assert contents =~ "( p <=> q )"
      assert contents =~ "( a & b )"

      assert {:ok, file, []} = Tptp.from_string(contents)
      assert length(file.statements) == 2
    end

    test "stripping markup does not eat the connectives it looks like" do
      page =
        "<pre>\nfof(a,axiom, (p &lt;=> q) | (r &lt;~> s)).\n" <>
          "thf(t,type, f: $i > $i).\nthf(u,axiom, a &lt;&lt; b).\n</pre>"

      assert {:ok, contents} = Tptp.Resolver.Http.contents(page)
      assert contents =~ "(p <=> q) | (r <~> s)"
      assert contents =~ "f: $i > $i"
      assert contents =~ "a << b"
      assert {:ok, file, []} = Tptp.from_string(contents)
      assert length(file.statements) == 3
    end

    test "a page with no pre block is the error page" do
      assert Tptp.Resolver.Http.contents("<html><body>No such file</body></html>") == :error
    end

    test "a plain body is already the file" do
      assert Tptp.Resolver.Http.contents("fof(a, axiom, p).") == {:ok, "fof(a, axiom, p)."}
    end

    test "the library does not make its consumers start :inets and :ssl" do
      declared = Application.spec(:tptp, :applications)

      refute :inets in declared
      refute :ssl in declared

      assert :crypto in declared
    end

    test "a cache hit resolves without needing them started" do
      dir = Path.join(@tmp, "no-network")
      options = [cache_dir: dir, base_url: "http://127.0.0.1:1/see"]
      url = Tptp.Resolver.Http.url("b.ax", options)

      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, Base.encode16(:crypto.hash(:sha256, url), case: :lower)),
        "fof(c, axiom, p)."
      )

      assert {:ok, ^url, "fof(c, axiom, p)."} =
               Resolver.resolve({Tptp.Resolver.Http, options}, "b.ax", nil)
    end

    test "starting them is idempotent and reports rather than raises" do
      assert Tptp.Resolver.Http.started() == :ok
      assert Tptp.Resolver.Http.started() == :ok
    end
  end
end

defmodule Tptp.ResolverEnvTest do
  @moduledoc """
  The two tests that read `$TPTP_ROOT`, kept apart from the rest.

  They have to set a process-wide environment variable to test that it is honoured,
  and the corpus tests read the same variable to find the library. `async: false`
  is what keeps one from pulling the rug out from under the other.
  """

  use ExUnit.Case, async: false

  alias Tptp.Resolver

  @tmp Path.join(System.tmp_dir!(), "tptp-resolver-env-test")

  setup do
    library = Path.join(@tmp, "library")
    local = Path.join(@tmp, "local")
    File.mkdir_p!(Path.join(library, "Axioms"))
    File.mkdir_p!(local)
    File.write!(Path.join([library, "Axioms", "shared.ax"]), "fof(library, axiom, p).\n")
    File.write!(Path.join(local, "shared.ax"), "fof(local, axiom, p).\n")

    previous = System.get_env("TPTP_ROOT")
    System.put_env("TPTP_ROOT", library)

    on_exit(fn ->
      if previous, do: System.put_env("TPTP_ROOT", previous), else: System.delete_env("TPTP_ROOT")
      File.rm_rf!(@tmp)
    end)

    %{library: library, local: local}
  end

  test "$TPTP_ROOT is used when :root is absent" do
    assert {:ok, _path, "fof(library, axiom, p).\n"} =
             Resolver.resolve({Tptp.Resolver.Fs, cwd: false}, "Axioms/shared.ax", nil)
  end

  test ":root overrides it, so a local override needs no environment change", %{local: local} do
    resolver = {Tptp.Resolver.Fs, root: local, cwd: false}

    assert {:ok, _path, "fof(local, axiom, p).\n"} = Resolver.resolve(resolver, "shared.ax", nil)
  end
end
