defmodule Tptp.SpanTest do
  use ExUnit.Case, async: true

  doctest Tptp.Span

  alias Tptp.Span

  @sources [
    "",
    "\n",
    "\n\n",
    "fof(a,axiom,p).",
    "fof(a,axiom,p).\n",
    "fof(a,axiom,p).\nfof(b,axiom,q).\n",
    "% c\n\nfof(a,axiom,p).\r\n  fof(b,axiom,q).",
    "fof('ä',axiom,p).\n"
  ]

  describe "offset/3" do
    test "inverts line_column/2 on every byte offset, and the end" do
      for source <- @sources, offset <- 0..byte_size(source) do
        index = Span.line_index(source)
        {line, column} = Span.line_column(index, offset)

        assert Span.offset(index, line, column) == {:ok, offset},
               "#{inspect(source)} at #{offset} -> #{line}:#{column}"
      end
    end

    test "every position it accepts maps back under line_column/2" do
      for source <- @sources,
          line <- -1..(Span.line_count(Span.line_index(source)) + 1),
          column <- -1..(byte_size(source) + 2) do
        index = Span.line_index(source)

        case Span.offset(index, line, column) do
          {:ok, offset} -> assert Span.line_column(index, offset) == {line, column}
          :error -> :ok
        end
      end
    end

    test "it rejects lines the index does not have and columns below one" do
      index = Span.line_index("ab\ncd")

      assert Span.offset(index, 0, 1) == :error
      assert Span.offset(index, 3, 1) == :error
      assert Span.offset(index, 1, 0) == :error
      assert Span.offset(index, -1, -1) == :error
    end

    test "it rejects a column past a line's line feed, except on the last line" do
      index = Span.line_index("ab\ncd")

      assert Span.offset(index, 1, 3) == {:ok, 2}
      assert Span.offset(index, 1, 4) == :error
      assert Span.offset(index, 2, 3) == {:ok, 5}
      assert Span.offset(index, 2, 40) == {:ok, 42}
    end

    test "columns count bytes, so a multi-byte character spans several" do
      source = "fof('ä',axiom,p).\n"
      index = Span.line_index(source)

      assert Span.offset(index, 1, 6) == {:ok, 5}
      assert {:ok, offset} = Span.offset(index, 1, 8)
      assert binary_part(source, offset, 1) == "'"
    end

    test "a line and column resolve to the byte they name" do
      source = "fof(a, axiom, p).\nfof(b, axiom, q)).\n"
      index = Span.line_index(source)

      assert {:ok, offset} = Span.offset(index, 2, 17)
      assert binary_part(source, offset, 1) == ")"
    end
  end
end
