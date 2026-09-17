defmodule Ayumi.CSV do
  @moduledoc """
  CSV codec for files exchanged with Excel.

  Output is UTF-8 with a BOM (so Excel detects the encoding), RFC 4180 quoting,
  and CRLF line endings. Cells that Excel would evaluate as a formula are
  prefixed with an apostrophe, and `decode/1` strips that apostrophe again, so a
  file written by `encode/2` reads back unchanged.

  Input must be UTF-8 (with or without a BOM). Excel's plain "CSV" format is
  Shift_JIS, which is rejected with advice to save as "CSV UTF-8" instead — there
  is deliberately no Shift_JIS codec.
  """

  @formula_triggers ["=", "+", "-", "@", "\t", "\r"]

  NimbleCSV.define(Ayumi.CSV.Parser,
    separator: ",",
    escape: "\"",
    line_separator: "\r\n",
    escape_formula: %{@formula_triggers => "'"},
    moduledoc: false
  )

  @bom "﻿"

  @doc "Encodes a header row and data rows (lists of strings) into a CSV binary."
  def encode(headers, rows) when is_list(headers) and is_list(rows) do
    IO.iodata_to_binary([@bom, Ayumi.CSV.Parser.dump_to_iodata([headers | rows])])
  end

  @doc """
  Decodes a CSV binary into `%{headers: [...], rows: [{row_number, cells}]}`,
  where `cells` maps each header to its cell text.

  Row numbers are the ones Excel shows (the header is row 1). They count records,
  not physical lines, so a multi-line cell does not shift the rows after it. Blank
  rows are skipped but still counted. Headers are NFKC-normalized with whitespace
  removed; empty headers (the trailing columns Excel appends) are dropped along
  with their cells.

  Returns `{:error, message}` with a Japanese message when the file as a whole
  cannot be used.
  """
  def decode(binary) when is_binary(binary) do
    with {:ok, text} <- validate_utf8(strip_bom(binary)),
         {:ok, [header_row | records]} <- parse(text),
         {:ok, headers} <- normalize_headers(header_row),
         {:ok, rows} <- build_rows(headers, records) do
      {:ok, %{headers: Enum.reject(headers, &(&1 == "")), rows: rows}}
    end
  end

  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(binary), do: binary

  defp validate_utf8(text) do
    if String.valid?(text) do
      {:ok, text}
    else
      {:error,
       "文字コードが UTF-8 ではありません。Excel では「名前を付けて保存」で" <>
         "ファイルの種類を「CSV UTF-8（コンマ区切り）」にして保存してください。"}
    end
  end

  defp parse(text) do
    case Ayumi.CSV.Parser.parse_string(text, skip_headers: false) do
      [] -> {:error, "ファイルが空です。"}
      records -> {:ok, records}
    end
  rescue
    NimbleCSV.ParseError ->
      {:error, "CSV として読み取れません。引用符（\"）が閉じているか確認してください。"}
  end

  defp normalize_headers(header_row) do
    headers = Enum.map(header_row, &normalize_header/1)
    named = Enum.reject(headers, &(&1 == ""))

    case named -- Enum.uniq(named) do
      [] -> {:ok, headers}
      [duplicate | _] -> {:error, "見出し「#{duplicate}」が重複しています。"}
    end
  end

  defp normalize_header(header) do
    header |> String.normalize(:nfkc) |> String.replace(~r/\s/u, "")
  end

  defp build_rows(headers, records) do
    rows =
      records
      |> Enum.with_index(2)
      |> Enum.reject(fn {cells, _row_number} -> blank_record?(cells) end)
      |> Enum.map(fn {cells, row_number} -> {row_number, to_cells(headers, cells)} end)

    if rows == [],
      do: {:error, "データ行がありません。見出しの下に 1 行以上入力してください。"},
      else: {:ok, rows}
  end

  defp blank_record?(cells), do: Enum.all?(cells, &(String.trim(&1) == ""))

  # A row may be shorter than the header row; its missing cells are blank.
  defp to_cells(headers, cells) do
    padded = cells ++ List.duplicate("", max(length(headers) - length(cells), 0))

    headers
    |> Enum.zip(padded)
    |> Enum.reject(fn {header, _cell} -> header == "" end)
    |> Map.new(fn {header, cell} -> {header, unescape_formula(cell)} end)
  end

  defp unescape_formula("'" <> rest = cell) do
    if String.starts_with?(rest, @formula_triggers), do: rest, else: cell
  end

  defp unescape_formula(cell), do: cell
end
