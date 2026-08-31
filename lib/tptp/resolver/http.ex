defmodule Tptp.Resolver.Http do
  @moduledoc """
  Fetches from tptp.org over HTTPS, through a local cache.

  For a machine without the TPTP distribution installed. It is never a default and
  never composed in by accident: reaching the network is the caller's decision, so
  it has to be written down.

      Tptp.Unit.from_name("Problems/PUZ/PUZ001+1.p", resolver: Tptp.Resolver.Http)

      Tptp.Unit.from_file("problem.p",
        resolver: {Tptp.Resolver.Cascade,
                   resolvers: [Tptp.Resolver.Fs, Tptp.Resolver.Http]}
      )

  ## The SeeTPTP mapping

  tptp.org serves the library through a CGI script that wants the name taken apart
  rather than a path:

      Axioms/SET007+0.ax   ->  ?Category=Axioms&File=SET007+0.ax
      SET007+0.ax          ->  ?Category=Axioms&File=SET007+0.ax
      Problems/PUZ/PUZ001+1.p  ->  ?Category=Problems&Domain=PUZ&File=PUZ001+1.p
      PUZ001+1.p           ->  ?Category=Problems&Domain=PUZ&File=PUZ001+1.p

  A bare problem name takes its domain from the leading three letters, which is how
  TPTP names are built. `url/2` is public so the mapping can be tested and read
  without a network.

  Note the `+` in `SET007+0.ax`: it is part of the name, and form-encoding turns it
  into a space unless every parameter is escaped. They are.

  ## SeeTPTP answers with a web page, not a file

  Every successful response is an HTML page with the file inside a `<pre>` block,
  and the block is not the file either: SeeTPTP injects an `<A NAME="...">` anchor
  before every formula so that each can be linked to. `contents/1` recovers the
  file, and is public so that it can be read and tested without a network.

  Two steps, in this order and not the other:

    1. **Strip the markup.** Every `<` that belongs to TPTP arrives as `&lt;` — the
       page escapes `<` but leaves `>` and `&` alone — so a literal `<` in the block
       is always injected markup and never `<=>`, `<~>` or `<<`. That is what makes
       removing `<[^>]*>` safe here when it would be reckless anywhere else.
    2. **Undo the entities.** Only now does `&lt;` become `<` again, which is why it
       cannot be mistaken for a tag by step 1.

  Doing it the other way round would silently delete every equivalence in the file.

  A page with no `<pre>` block is SeeTPTP's error page and is reported as one; a body
  that is not HTML at all is passed through untouched, which is what a plain file
  server behind `:base_url` gets.

  ## Caching

  Every response is written to `:cache_dir` under a digest of its URL, and a hit is
  served from disk without asking the network. A corpus run therefore costs one
  request per file, once, ever. `~/.cache/tptp` by default, or set `:cache_dir` to
  `false` to disable.

  ## `:inets` and `:ssl` are started here, not by the application

  They are deliberately absent from this library's `extra_applications`. Listing
  them would start two OTP applications in every consumer, including the ones whose
  resolver is `Tptp.Resolver.None` and which never open a socket — which is at odds
  with `None` being the default in the first place. So `started/0` brings them up on
  the path that is about to make a request. A cache hit never reaches it, so a warm
  cache costs nothing either.

  ### Why that needs more than `ensure_all_started/1`

  Mix prunes the code path to the applications named in the `.app` file, so dropping
  `:ssl` from `extra_applications` also removes `ssl`, `public_key` and `asn1` from
  the code path. The application controller still reports them as *running* — they
  are, in the VM — while their modules are not loadable, and `ensure_all_started/1`
  cheerfully answers `{:ok, []}`. The first symptom is an `:undef` from deep inside
  `:httpc`, raised while it builds the default HTTPS options.

  So `started/0` puts the ebin directories back on the path first, resolving them
  under `:code.root_dir/0` rather than `:code.lib_dir/1` — the latter consults the
  code path it is trying to repair and answers `:bad_name`. It then checks a
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

  @base_url "https://tptp.org/cgi-bin/SeeTPTP"
  @timeout 30_000
  @lib_path [:asn1, :crypto, :public_key, :ssl, :inets]
  @needed [{:public_key, :public_key}, {:ssl, :ssl}, {:inets, :httpc}]

  @impl true
  @spec resolve(binary(), Path.t() | nil, keyword()) :: Tptp.Resolver.result()
  def resolve(name, _from, options) do
    if Tptp.Resolver.safe?(name) do
      fetch(url(name, options), name, options)
    else
      {:error, Tptp.Resolver.unsafe_reason(name)}
    end
  end

  @doc """
  The SeeTPTP URL an include name maps to.

      iex> Tptp.Resolver.Http.url("Problems/PUZ/PUZ001+1.p")
      "https://tptp.org/cgi-bin/SeeTPTP?Category=Problems&Domain=PUZ&File=PUZ001%2B1.p"

      iex> Tptp.Resolver.Http.url("Axioms/SET007+0.ax")
      "https://tptp.org/cgi-bin/SeeTPTP?Category=Axioms&File=SET007%2B0.ax"

      iex> Tptp.Resolver.Http.url("SET007+0.ax")
      "https://tptp.org/cgi-bin/SeeTPTP?Category=Axioms&File=SET007%2B0.ax"
  """
  @spec url(binary(), keyword()) :: binary()
  def url(name, options \\ []) when is_binary(name) do
    base = Keyword.get(options, :base_url, @base_url)
    base <> "?" <> query(name)
  end

  defp query(name) do
    name
    |> parameters()
    |> Enum.map_join("&", fn {key, value} -> key <> "=" <> URI.encode_www_form(value) end)
    |> String.replace("+", "%2B")
  end

  @spec parameters(binary()) :: [{binary(), binary()}]
  defp parameters(name) do
    case Path.split(name) do
      ["Axioms", file] -> [{"Category", "Axioms"}, {"File", file}]
      ["Problems", domain, file] -> [{"Category", "Problems"}, {"Domain", domain}, {"File", file}]
      [file] -> bare(file)
      other -> [{"Category", "Problems"}, {"File", List.last(other)}]
    end
  end

  defp bare(file) do
    if String.ends_with?(file, ".ax") do
      [{"Category", "Axioms"}, {"File", file}]
    else
      [
        {"Category", "Problems"},
        {"Domain", String.upcase(String.slice(file, 0, 3))},
        {"File", file}
      ]
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
    if not ready?(), do: Enum.each(@lib_path, &extend_path/1)

    Enum.reduce_while(@needed, :ok, fn {application, module}, :ok ->
      case start(application, module) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end)
  end

  defp ready?,
    do: Enum.all?(@needed, fn {_application, module} -> Code.ensure_loaded?(module) end)

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
    timeout = Keyword.get(options, :timeout, @timeout)
    request = {String.to_charlist(url), [{~c"user-agent", ~c"tptp-elixir"}]}
    http = [timeout: timeout, connect_timeout: timeout, autoredirect: true]

    case safe_request(request, http) do
      {:ok, {{_version, 200, _phrase}, _headers, body}} ->
        accept(IO.iodata_to_binary(body), url, name, options)

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
    case contents(body) do
      {:ok, contents} ->
        store(url, contents, options)
        {:ok, url, contents}

      :error ->
        {:error, "#{url} returned SeeTPTP's error page rather than #{inspect(name)}"}
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
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
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
      false -> nil
      nil -> nil
      dir -> Path.join(dir, Base.encode16(:crypto.hash(:sha256, url), case: :lower))
    end
  end

  defp default_cache_dir do
    case System.user_home() do
      nil -> nil
      home -> Path.join([home, ".cache", "tptp"])
    end
  end
end
