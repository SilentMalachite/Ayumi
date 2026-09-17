defmodule Ayumi.JST do
  @moduledoc """
  Japan Standard Time helpers for exported data.

  Timestamps are stored as UTC. Japan has no daylight saving time, so a fixed
  +9h offset is exact and no time zone database is needed. Keep every JST
  conversion here so the offset lives in one place.
  """

  @offset_seconds 9 * 60 * 60

  @doc "Today's date on the JST wall clock."
  def today(%DateTime{} = now \\ DateTime.utc_now()) do
    now |> to_naive() |> NaiveDateTime.to_date()
  end

  @doc "The JST wall-clock time of a UTC datetime."
  def to_naive(%DateTime{} = datetime) do
    datetime |> DateTime.add(@offset_seconds, :second) |> DateTime.to_naive()
  end

  @doc """
  Formats a UTC datetime as JST text: `"YYYY-MM-DD HH:MM:SS"`, or
  `"YYYY-MM-DD HH:MM"` with `:minute` precision.
  """
  def format(%DateTime{} = datetime, precision \\ :second) do
    datetime |> to_naive() |> Calendar.strftime(strftime_format(precision))
  end

  defp strftime_format(:second), do: "%Y-%m-%d %H:%M:%S"
  defp strftime_format(:minute), do: "%Y-%m-%d %H:%M"

  @doc """
  The half-open UTC range `{from, to_exclusive}` covering the JST dates
  `from_date..to_date` — from 00:00 JST on the first day up to, but not
  including, 00:00 JST on the day after the last.
  """
  def utc_range(%Date{} = from_date, %Date{} = to_date) do
    {jst_midnight(from_date), jst_midnight(Date.add(to_date, 1))}
  end

  defp jst_midnight(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(-@offset_seconds, :second)
  end
end
