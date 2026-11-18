defmodule Tptp.Resolver.Http do
  @moduledoc """
  Fetches from tptp.org over HTTPS, through a local cache.

  For use where the TPTP distribution is not installed locally. It is never a
  default and is never composed implicitly, network access being a decision for the
  caller.

      Tptp.Unit.from_name("Problems/PUZ/PUZ001+1.p", resolver: Tptp.Resolver.Http)

      Tptp.Unit.from_file("problem.p",
        resolver: {Tptp.Resolver.Cascade,
                   resolvers: [Tptp.Resolver.Fs, Tptp.Resolver.Http]}
      )

  ## The SeeTPTP mapping

  SeeTPTP serves the library by its path under the library root:

      Axioms/SET007/SET007+0.ax  ->  .../TPTP/Axioms/SET007/SET007+0.ax
      Problems/PUZ/PUZ001+1.p    ->  .../TPTP/Problems/PUZ/PUZ001+1.p
      SET007+0.ax                ->  .../TPTP/Axioms/SET007+0.ax
                                     .../TPTP/Axioms/SET007/SET007+0.ax
      PUZ001+1.p                 ->  .../TPTP/Problems/PUZ/PUZ001+1.p

  A name of more than one segment is that path. A bare problem name takes its
  domain from the leading three letters, following the TPTP naming convention.

  An axiom set may sit in a subdirectory named for it, as the 2,125 files under
  `Axioms/SET007/` and `Axioms/ITP001/` do. Which ones do cannot be told from the
  name, so a bare axiom name, or `Axioms/` and a bare name, is tried at the top of
  `Axioms` and, on a 404, in the subdirectory named by its leading six characters.
  Any other failure is reported at once rather than costing a second request.

  `urls/2` and `url/2` are public so that the mapping can be read and tested
  without network access.

  Not the older CGI script at `tptp.org/cgi-bin/SeeTPTP`: it redirects here for a
  flat name, but answers a name in a subdirectory of `Axioms` with the file's
  header alone, followed by "problem and solutions unavailable".

  Every segment is percent-encoded, so the `+` in `SET007+0.ax` cannot be read as
  a space.

  ## SeeTPTP answers with a web page, not a file

  Every successful response is an HTML page containing the file within a `<pre>`
  block, and the block need not be the file: the older CGI script inserts an
  `<A NAME="...">` anchor before each formula. `contents/1` recovers the file and is
  public so that it can be read and tested without network access.

  Two steps, in this order:

    1. **Remove the markup.** Every `<` belonging to the TPTP source arrives as
       `&lt;`, so a literal `<` within the block is inserted markup rather than
       `<=>`, `<~>` or `<<`. This is what renders removing `<[^>]*>` sound in this
       context.
    2. **Resolve the entities.** `&lt;` becomes `<` only at this point, so it cannot
       be treated as a tag by the first step. Numeric references are resolved too:
       SeeTPTP writes `"` as `&#34;` and `'` as `&#39;`. `&amp;` is resolved last,
       so that an `&amp;lt;` in the page stays the `&lt;` that is in the file.

  The reverse order would delete every equivalence in the file.

  A file over 10 MiB is not displayed: the page carries no `<pre>` block but links
  a `.tgz` of the file under `/download/`, which is fetched and unpacked instead.
  Otherwise a page containing no `<pre>` block is SeeTPTP's error page and is
  reported as such. A body that is not HTML is passed through unmodified, which is what a plain
  file server behind `:base_url` returns.

  ## Caching

  Every response is written to `:cache_dir` under a digest of its URL, and a hit is
  served from disk without network access, so a corpus run costs one request per
  file. The default is `~/.cache/tptp`; set `:cache_dir` to `false` to disable
  caching.

  What is cached is the recovered file, not the page, so a fix to `contents/1`
  would not reach a file already cached. Entries therefore sit in a subdirectory
  named for the version of the recovery, which changes with it; an older
  subdirectory is never read again and can be deleted.

  ## `:inets` and `:ssl` are started here, not by the application

  Both are absent from this library's `extra_applications`. Listing them would
  start two OTP applications in every consumer, including those whose resolver is
  `Tptp.Resolver.None` and which open no socket. `started/0` starts them on the path
  about to issue a request; a cache hit does not reach it.

  ### Why that needs more than `ensure_all_started/1`

  Mix prunes the code path to the applications named in the `.app` file, so dropping
  `:ssl` from `extra_applications` also removes `ssl`, `public_key` and `asn1` from
  the code path. The application controller still reports them as *running* — they
  are, in the VM — while their modules are not loadable, and `ensure_all_started/1`
  cheerfully answers `{:ok, []}`. The first symptom is an `:undef` from deep inside
  `:httpc`, raised while it builds the default HTTPS options.

  Mix and Hex load `:httpc` themselves, so a loaded `:httpc` does not mean the rest
  of `:inets` is loadable: with its directory pruned, the request exits with an
  `:undef` from `:http_util`.

  So `started/0` puts back on the path every ebin directory `:code.lib_dir/1`
  reports missing — it consults the code path and answers `:bad_name` — resolving
  them under `:code.root_dir/0` instead. It then checks a
  representative module of each application is really loadable, so a genuine absence
  is reported as a sentence rather than surfacing later as an `:undef`.

  In a release the applications must be included as usual; nothing here can conjure
  code that was not shipped, and `started/0` says so plainly if it was not.

  ## Failure

  A non-200, a timeout, a connection error or a body that looks like SeeTPTP's HTML
  error page all come back as `{:error, reason}`, and `Tptp.Include` turns that into
  a diagnostic. Nothing here raises and nothing retries — a resolver that retries on
  its own turns one slow file into a much slower run without telling anyone.
  """

  @behaviour Tptp.Resolver

  @base_url "https://seetptp.tptp.org/file/TPTPWorld/TPTP"
  @timeout 30_000
  # Bumped whenever `contents/1` changes what it recovers from a page.
  @cache_version "v2"
  @lib_path [:asn1, :crypto, :public_key, :ssl, :inets]
  @needed [{:public_key, :public_key}, {:ssl, :ssl}, {:inets, :httpc}]

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: Tptp.Resolver.result()
  def resolve(name, _from, options) do
    if Tptp.Resolver.safe?(name) do
      name |> urls(options) |> first_found(name, options)
    else
      {:error, Tptp.Resolver.unsafe_reason(name)}
    end
  end

  @doc """
  The SeeTPTP URL an include name maps to, the first of `urls/2`.

      iex> Tptp.Resolver.Http.url("Problems/PUZ/PUZ001+1.p")
      "https://seetptp.tptp.org/file/TPTPWorld/TPTP/Problems/PUZ/PUZ001%2B1.p"

      iex> Tptp.Resolver.Http.url("Axioms/SET007/SET007+0.ax")
      "https://seetptp.tptp.org/file/TPTPWorld/TPTP/Axioms/SET007/SET007%2B0.ax"

      iex> Tptp.Resolver.Http.url("SET007+0.ax")
      "https://seetptp.tptp.org/file/TPTPWorld/TPTP/Axioms/SET007%2B0.ax"
  """
  @spec url(binary(), keyword()) :: binary()
  def url(name, options \\ []) when is_binary(name), do: hd(urls(name, options))

  @doc """
  The SeeTPTP URLs an include name may be found at, in the order they are tried.

      iex> Tptp.Resolver.Http.urls("SET007+0.ax")
      ["https://seetptp.tptp.org/file/TPTPWorld/TPTP/Axioms/SET007%2B0.ax",
       "https://seetptp.tptp.org/file/TPTPWorld/TPTP/Axioms/SET007/SET007%2B0.ax"]
  """
  @spec urls(binary(), keyword()) :: [binary(), ...]
  def urls(name, options \\ []) when is_binary(name) do
    base = Keyword.get(options, :base_url, @base_url)

    for path <- paths(name) do
      Enum.join([base | Enum.map(path, &encode/1)], "/")
    end
  end

  defp encode(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp paths(name) do
    case Path.split(name) do
      ["Axioms", file] -> axiom(file)
      [file] -> bare(file)
      path -> [path]
    end
  end

  defp bare(file) do
    if String.ends_with?(file, ".ax") do
      axiom(file)
    else
      [["Problems", String.upcase(String.slice(file, 0, 3)), file]]
    end
  end

  defp axiom(file), do: [["Axioms", file], ["Axioms", String.slice(file, 0, 6), file]]

  defp first_found([url | rest], name, options) do
    case fetch(url, name, options) do
      {:not_found, _reason} when rest != [] -> first_found(rest, name, options)
      {:not_found, reason} -> {:error, reason}
      result -> result
    end
  end

  defp fetch(url, name, options) do
    case cached(url, options) do
      {:ok, contents} -> {:ok, url, contents}
      :miss -> request(url, name, options)
    end
  end

  defp request(url, name, options) do
    case started() do
      :ok -> get(url, name, options)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Make `:inets` and `:ssl` usable, if they are not already.

  Idempotent, and a handful of module lookups once they are up. Public so that a
  caller who would rather pay it once up front — a long corpus run, or a release
  that wants every application accounted for at boot — can, and so that the lazy
  start is testable without a network.

      iex> Tptp.Resolver.Http.started()
      :ok
  """
  @spec started() :: :ok | {:error, binary()}
  def started do
    Enum.each(@lib_path, &extend_path/1)

    Enum.reduce_while(@needed, :ok, fn {application, module}, :ok ->
      case start(application, module) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end)
  end

  defp start(application, module) do
    if Code.ensure_loaded?(module) do
      running(application)
    else
      {:error, absent(application)}
    end
  end

  defp running(application) do
    case Application.ensure_all_started(application) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, "could not start :#{application}: #{inspect(reason)}"}
    end
  end

  defp extend_path(application) do
    if :code.lib_dir(application) == {:error, :bad_name}, do: append_path(application)
  end

  defp append_path(application) do
    :code.root_dir()
    |> List.to_string()
    |> Path.join("lib/#{application}-*/ebin")
    |> Path.wildcard()
    |> Enum.each(&Code.append_path/1)
  end

  defp absent(application) do
    ":#{application} is not on the code path, so #{inspect(__MODULE__)} cannot fetch. " <>
      "It ships with OTP, so this normally means a release left it out; " <>
      "add :#{application} to the release's applications."
  end

  defp get(url, name, options) do
    case body(url, options) do
      {:ok, body} -> accept(body, url, name, options)
      failure -> failure
    end
  end

  defp body(url, options) do
    timeout = Keyword.get(options, :timeout, @timeout)
    request = {String.to_charlist(url), [{~c"user-agent", ~c"tptp-elixir"}]}
    http = [timeout: timeout, connect_timeout: timeout, autoredirect: true]

    case safe_request(request, http) do
      {:ok, {{_version, 200, _phrase}, _headers, body}} ->
        {:ok, IO.iodata_to_binary(body)}

      {:ok, {{_version, 404, phrase}, _headers, _body}} ->
        {:not_found, "#{url} returned 404 #{phrase}"}

      {:ok, {{_version, status, phrase}, _headers, _body}} ->
        {:error, "#{url} returned #{status} #{phrase}"}

      {:error, reason} ->
        {:error, "#{url} could not be fetched: #{inspect(reason)}"}
    end
  end

  defp safe_request(request, http) do
    :httpc.request(:get, request, http, body_format: :binary)
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp accept(body, url, name, options) do
    with :error <- contents(body),
         [_whole, href] <- Regex.run(~r{href="(/download/[^"]+)"}, body) do
      download(URI.to_string(URI.merge(url, href)), url, name, options)
    else
      {:ok, contents} ->
        store(url, contents, options)
        {:ok, url, contents}

      nil ->
        {:error, "#{url} returned SeeTPTP's error page rather than #{inspect(name)}"}
    end
  end

  defp download(archive, url, name, options) do
    with {:ok, body} <- body(archive, options),
         {:ok, contents} <- unpack(body, archive, name) do
      store(url, contents, options)
      {:ok, url, contents}
    end
  end

  defp unpack(body, archive, name) do
    case :erl_tar.extract({:binary, body}, [:memory, :compressed]) do
      {:ok, [{_file, contents}]} ->
        {:ok, contents}

      {:ok, files} ->
        {:error, "#{archive} held #{length(files)} files, not #{inspect(name)} alone"}

      {:error, reason} ->
        {:error, "#{archive} could not be unpacked: #{inspect(reason)}"}
    end
  end

  @doc """
  The TPTP file inside a SeeTPTP response.

  A body that is not HTML is already the file and comes back unchanged. An HTML body
  must carry a `<pre>` block, which is unwrapped and unescaped; without one it is
  SeeTPTP's error page and the answer is `:error`.

      iex> Tptp.Resolver.Http.contents("fof(a, axiom, p).")
      {:ok, "fof(a, axiom, p)."}

      iex> Tptp.Resolver.Http.contents(~s|<pre><A NAME="a"></A>fof(a, axiom, p &lt;=> q).</pre>|)
      {:ok, "fof(a, axiom, p <=> q)."}

      iex> Tptp.Resolver.Http.contents("<html><body>No such file</body></html>")
      :error
  """
  @spec contents(binary()) :: {:ok, binary()} | :error
  def contents(body) when is_binary(body) do
    if html?(body), do: preformatted(body), else: {:ok, body}
  end

  defp preformatted(body) do
    case Regex.run(~r{<pre>\r?\n?(.*?)</pre>}is, body) do
      [_whole, inner] -> {:ok, inner |> strip_markup() |> unescape()}
      nil -> :error
    end
  end

  defp strip_markup(text), do: String.replace(text, ~r{<[^>]*>}, "")

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> numeric_references()
    |> String.replace("&amp;", "&")
  end

  defp numeric_references(text),
    do: Regex.replace(~r/&#(?:x([0-9a-f]+)|([0-9]+));/i, text, &numeric/3)

  defp numeric(reference, "", decimal), do: character(reference, String.to_integer(decimal))
  defp numeric(reference, hex, _decimal), do: character(reference, String.to_integer(hex, 16))

  defp character(reference, code) do
    <<code::utf8>>
  rescue
    ArgumentError -> reference
  end

  defp html?(body) do
    trimmed = body |> binary_part(0, min(byte_size(body), 200)) |> String.trim_leading()

    String.starts_with?(trimmed, "<") or trimmed == ""
  end

  defp cached(url, options) do
    with path when is_binary(path) <- cache_path(url, options),
         {:ok, contents} <- File.read(path) do
      {:ok, contents}
    else
      _otherwise -> :miss
    end
  end

  defp store(url, body, options) do
    case cache_path(url, options) do
      nil ->
        :ok

      path ->
        File.mkdir_p(Path.dirname(path))
        File.write(path, body)
        :ok
    end
  end

  defp cache_path(url, options) do
    case Keyword.get(options, :cache_dir, default_cache_dir()) do
      false ->
        nil

      nil ->
        nil

      dir ->
        Path.join([dir, @cache_version, Base.encode16(:crypto.hash(:sha256, url), case: :lower)])
    end
  end

  defp default_cache_dir do
    case System.user_home() do
      nil -> nil
      home -> Path.join([home, ".cache", "tptp"])
    end
  end
end
