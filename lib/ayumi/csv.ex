defmodule Ayumi.CSV do
  @moduledoc """
  CSV codec for files exchanged with Excel.

  Output is UTF-8 with a BOM (so Excel detects the encoding), RFC 4180 quoting,
  and CRLF line endings. Cells that Excel would evaluate as a formula are
  prefixed with an apostrophe.
  """

  NimbleCSV.define(Ayumi.CSV.Parser,
    separator: ",",
    escape: "\"",
    line_separator: "\r\n",
    escape_formula: %{["=", "+", "-", "@", "\t", "\r"] => "'"},
    moduledoc: false
  )

  @bom "﻿"

  @doc "Encodes a header row and data rows (lists of strings) into a CSV binary."
  def encode(headers, rows) when is_list(headers) and is_list(rows) do
    IO.iodata_to_binary([@bom, Ayumi.CSV.Parser.dump_to_iodata([headers | rows])])
  end
end
