defmodule AyumiWeb.AttendanceLive.MonthParams do
  @moduledoc "出欠系 LiveView 共通の年月パラメータ解釈。"

  @doc """
  Parses `params["year"]` and `params["month"]` (string or nil) into a
  `{year, month}` tuple. Falls back to today's year/month when missing or
  invalid; `month` is always within 1..12.
  """
  @spec parse(map()) :: {integer(), integer()}
  def parse(params) do
    today = Date.utc_today()
    year = parse_int(params["year"], today.year)
    month = parse_int(params["month"], today.month)
    if month in 1..12, do: {year, month}, else: {today.year, today.month}
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default
end
