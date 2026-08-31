defmodule Tptp.Error do
  @moduledoc """
  Raised by the `!` variants of the public API, carrying the diagnostics.

  The library never raises on input of its own accord — every stage threads an
  accumulator and a partial result is always available. This exception exists only
  because a caller who wrote `Tptp.from_file!/2` asked to be interrupted instead of
  handed a result to inspect, and it carries the full diagnostic list so that the
  choice costs no information.
  """

  alias Tptp.Diagnostic

  defexception [:message, :path, diagnostics: []]

  @typedoc "The exception, carrying every diagnostic and not just the ones in the message."
  @type t :: %__MODULE__{
          message: binary(),
          path: Path.t() | nil,
          diagnostics: [Diagnostic.t()]
        }

  @shown 5

  @doc """
  Build the exception from diagnostics, resolving each span against the source.

  Only the errors are shown, at most #{@shown} of them, because an exception
  message is read in a terminal and the rest are on the struct for a caller that
  wants them.
  """
  @impl true
  @spec exception(keyword()) :: t()
  def exception(options) do
    diagnostics = Keyword.fetch!(options, :diagnostics)
    path = Keyword.get(options, :path)
    source = Keyword.get(options, :source, "")

    %__MODULE__{
      message: describe(diagnostics, path, source),
      path: path,
      diagnostics: diagnostics
    }
  end

  defp describe([], path, _source), do: "#{where(path)} could not be read"

  defp describe(diagnostics, path, source) do
    errors = Enum.filter(diagnostics, &(&1.severity == :error))
    shown = if errors == [], do: diagnostics, else: errors
    index = Tptp.Span.line_index(source)

    lines = shown |> Enum.take(@shown) |> Enum.map(&("  " <> Diagnostic.format(&1, index)))
    more = length(shown) - length(lines)
    tail = if more > 0, do: ["  ... and #{more} more"], else: []

    Enum.join(
      ["#{length(shown)} problem#{plural(shown)} in #{where(path)}" | lines ++ tail],
      "\n"
    )
  end

  defp plural([_one]), do: ""
  defp plural(_many), do: "s"

  defp where(nil), do: "the given source"
  defp where(path), do: path
end
