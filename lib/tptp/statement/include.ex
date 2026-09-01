defmodule Tptp.Statement.Include do
  @moduledoc """
  An include directive: `include('Axioms/SET007+0.ax', [a, b], space).`

  `selection` is the optional `<formula_selection>` — a list of names, or `*`
  spelled as a `:star` leaf — and `space_name` the optional third argument, which
  the BNF admits and attaches no meaning to. Both are kept verbatim.

  Nothing here is resolved. Following the directive is `Tptp.Include`'s job and
  needs a resolver, which needs the caller's permission, because reading a file the
  user did not name — or fetching one over the network — is not something a parser
  should decide on its own.
  """

  alias Tptp.Node

  @enforce_keys [:file_name, :off, :len]
  defstruct [:file_name, :selection, :space_name, :off, :len]

  @typedoc "An `include` directive: the file it names, the selection it applies, and the space it names."
  @type t :: %__MODULE__{
          file_name: Node.t(),
          selection: Node.t() | nil,
          space_name: Node.t() | nil,
          off: non_neg_integer(),
          len: non_neg_integer()
        }

  @doc """
  The included file's name, without its surrounding quotes.

  `<file_name>` is an `<atomic_word>`, and in practice always a `<single_quoted>`,
  so the raw text carries quotes the filesystem does not want. That unquoting is
  `Tptp.Node.value/1` — the same canonical value every other atomic word gets —
  and the copy is this function's own: a path outlives the read that produced it,
  and a sub-binary of a source file is the wrong thing to keep a directory alive.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("include('Axioms/SET007+0.ax').")
      iex> Tptp.Statement.Include.path(statement)
      "Axioms/SET007+0.ax"
  """
  @spec path(t()) :: binary()
  def path(%__MODULE__{file_name: %Node{text: text} = file_name}) when is_binary(text) do
    file_name |> Node.value() |> :binary.copy()
  end

  @doc """
  The names this include selects, or `nil` when it takes the whole file.

  `*` selects everything and is reported as `nil`, the same as no selection at all,
  because the two mean the same thing and a caller should not have to know both
  spellings. The names are canonical values rather than spellings, so
  `include('a.ax', ['b'])` selects the statement named `b`.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("include('a.ax',[b,c]).")
      iex> Tptp.Statement.Include.selected(statement)
      ["b", "c"]
  """
  @spec selected(t()) :: [binary()] | nil
  def selected(%__MODULE__{selection: nil}), do: nil
  def selected(%__MODULE__{selection: %Node{kind: :star}}), do: nil

  def selected(%__MODULE__{selection: selection}) do
    selection |> Node.select(:name) |> Enum.map(&Node.value/1)
  end
end
