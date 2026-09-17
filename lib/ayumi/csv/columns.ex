defmodule Ayumi.CSV.Columns do
  @moduledoc """
  A dataset's columns are one list. Deriving the header row, the data rows, and
  the import parser from that single list means they cannot drift apart — which
  is what makes export → edit in Excel → import a safe round trip.

  A column is `{header, dump_fun}` when it is export-only, or
  `{header, dump_fun, import}` when the import reads it, where `import` is a
  keyword list:

    * `:key` — the attrs key the parsed value is stored under
    * `:parse` — a `Ayumi.CSV.Cell` parser, `cell -> {:ok, value} | {:error, message}`
    * `:required` — when true, a blank cell is an error (default false)
  """

  @required_message "入力してください"

  @doc "The header row."
  def headers(columns), do: Enum.map(columns, &elem(&1, 0))

  @doc "Renders records as rows of cells aligned with `headers/1`."
  def dump(columns, records) when is_list(records) do
    Enum.map(records, fn record ->
      Enum.map(columns, fn column -> elem(column, 1).(record) end)
    end)
  end

  @doc "Headers of the columns the import reads. A file must contain all of them."
  def required_headers(columns) do
    for {header, _dump, _import} <- columns, do: header
  end

  @doc "The header of the column stored under `key`; nil when there is none."
  def header_for(columns, key) do
    Enum.find_value(columns, fn
      {header, _dump, import} -> if import[:key] == key, do: header
      _export_only -> nil
    end)
  end

  @doc """
  Parses one row's `cells` (`%{header => text}`) into attrs. Returns every
  problem at once, in column order, as `{:error, [%{column: header, message: text}]}`.
  """
  def parse_row(columns, cells) when is_map(cells) do
    results = for {header, _dump, import} <- columns, do: parse_cell(header, import, cells)

    case for {:error, error} <- results, do: error do
      [] -> {:ok, Map.new(for {:ok, pair} <- results, do: pair)}
      errors -> {:error, errors}
    end
  end

  defp parse_cell(header, import, cells) do
    key = Keyword.fetch!(import, :key)
    parse = Keyword.fetch!(import, :parse)

    case parse.(Map.get(cells, header, "")) do
      {:ok, nil} -> blank_cell(header, key, Keyword.get(import, :required, false))
      {:ok, value} -> {:ok, {key, value}}
      {:error, message} -> {:error, %{column: header, message: message}}
    end
  end

  defp blank_cell(header, _key, true), do: {:error, %{column: header, message: @required_message}}
  defp blank_cell(_header, key, false), do: {:ok, {key, nil}}
end
