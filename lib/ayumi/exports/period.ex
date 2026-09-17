defmodule Ayumi.Exports.Period do
  @moduledoc """
  Export periods. A period is a unit plus an anchor date: the week, month,
  fiscal year, or calendar year that contains the date. Pure functions only.
  """

  @labels [
    week: "週",
    month: "月",
    fiscal_year: "年度",
    calendar_year: "暦年"
  ]

  # The Japanese fiscal year runs April 1 through March 31.
  @fiscal_year_start_month 4

  @doc "All units, in display order."
  def units, do: Keyword.keys(@labels)

  @doc "Japanese label for a unit. Unknown / nil returns nil."
  def unit_label(unit), do: Keyword.get(@labels, unit)

  @doc "`[{label, value}]` for `<.input type=\"select\">`."
  def unit_options, do: Enum.map(@labels, fn {unit, label} -> {label, unit} end)

  @doc "Inclusive `{first_day, last_day}` of the period containing `date`."
  def range(:week, %Date{} = date) do
    {Date.beginning_of_week(date, :monday), Date.end_of_week(date, :monday)}
  end

  def range(:month, %Date{} = date) do
    {Date.beginning_of_month(date), Date.end_of_month(date)}
  end

  def range(:fiscal_year, %Date{} = date) do
    year = fiscal_year(date)

    {Date.new!(year, @fiscal_year_start_month, 1),
     Date.new!(year + 1, @fiscal_year_start_month, 1) |> Date.add(-1)}
  end

  def range(:calendar_year, %Date{year: year}) do
    {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}
  end

  @doc "Human-readable description of the period, including its date range."
  def label(:week, %Date{} = date), do: range_text(:week, date)

  def label(unit, %Date{} = date) do
    "#{period_name(unit, date)}（#{range_text(unit, date)}）"
  end

  @doc "Short period text for file names."
  def filename_part(:week, %Date{} = date) do
    {first, _last} = range(:week, date)
    "#{Date.to_iso8601(first)}週"
  end

  def filename_part(:month, %Date{year: year, month: month}) do
    "#{year}年#{String.pad_leading(Integer.to_string(month), 2, "0")}月"
  end

  def filename_part(unit, %Date{} = date), do: period_name(unit, date)

  defp period_name(:month, %Date{year: year, month: month}), do: "#{year}年#{month}月"
  defp period_name(:fiscal_year, date), do: "#{fiscal_year(date)}年度"
  defp period_name(:calendar_year, %Date{year: year}), do: "#{year}年"

  defp range_text(unit, date) do
    {first, last} = range(unit, date)
    "#{Date.to_iso8601(first)} 〜 #{Date.to_iso8601(last)}"
  end

  defp fiscal_year(%Date{year: year, month: month}) when month >= @fiscal_year_start_month,
    do: year

  defp fiscal_year(%Date{year: year}), do: year - 1
end
