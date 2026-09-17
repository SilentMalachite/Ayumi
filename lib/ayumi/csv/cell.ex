defmodule Ayumi.CSV.Cell do
  @moduledoc """
  Pure cell formatters shared by every CSV dataset. A missing value is always an
  empty cell.
  """

  alias Ayumi.JST

  @weekdays {"月", "火", "水", "木", "金", "土", "日"}

  @doc "Free text."
  def format_text(nil), do: ""
  def format_text(text) when is_binary(text), do: text

  @doc "A database id."
  def format_id(nil), do: ""
  def format_id(id) when is_integer(id), do: Integer.to_string(id)

  @doc "A date as `YYYY-MM-DD`."
  def format_date(nil), do: ""
  def format_date(%Date{} = date), do: Date.to_iso8601(date)

  @doc "The one-letter Japanese weekday of a date."
  def format_weekday(nil), do: ""
  def format_weekday(%Date{} = date), do: elem(@weekdays, Date.day_of_week(date) - 1)

  @doc "A time as `HH:MM`."
  def format_time(nil), do: ""
  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  @doc "A boolean as `○` or blank, matching the printed attendance sheet."
  def format_bool(true), do: "○"
  def format_bool(_), do: ""

  @doc "A UTC datetime as JST text with seconds."
  def format_datetime(nil), do: ""
  def format_datetime(%DateTime{} = datetime), do: JST.format(datetime)

  @doc "An enum value as the Japanese label from its enum module."
  def format_enum(nil, _enum_module), do: ""
  def format_enum(value, enum_module), do: format_text(enum_module.label(value))
end
