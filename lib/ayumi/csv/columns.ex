defmodule Ayumi.CSV.Columns do
  @moduledoc """
  A dataset's columns are one list of `{header, dump_fun}` pairs. Deriving both
  the header row and the data rows from that single list means the header order
  and the cell order cannot drift apart.
  """

  @doc "The header row."
  def headers(columns), do: Enum.map(columns, fn {header, _dump} -> header end)

  @doc "Renders records as rows of cells aligned with `headers/1`."
  def dump(columns, records) when is_list(records) do
    Enum.map(records, fn record ->
      Enum.map(columns, fn {_header, dump} -> dump.(record) end)
    end)
  end
end
