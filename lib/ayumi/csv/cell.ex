defmodule Ayumi.CSV.Cell do
  @moduledoc """
  Pure cell formatters and parsers shared by every CSV dataset.

  Formatting: a missing value is always an empty cell. Parsing: a blank cell is
  always `{:ok, nil}` (`false` for booleans), and a cell that cannot be read is
  `{:error, message}` with a Japanese message for the import screen. Structured
  cells are NFKC-normalized and trimmed first, so full-width digits and the
  variants Excel writes (`2026/9/1`, `9:00`) are accepted; free text is kept as
  written.
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

  ## Parsers

  @doc "Free text, kept as written except that CRLF becomes LF."
  def parse_text(cell) when is_binary(cell) do
    if String.trim(cell) == "",
      do: {:ok, nil},
      else: {:ok, String.replace(cell, "\r\n", "\n")}
  end

  @doc "A database id: digits only."
  def parse_id(cell) when is_binary(cell) do
    case normalize(cell) do
      "" -> {:ok, nil}
      text -> parse_digits(text)
    end
  end

  defp parse_digits(text) do
    if text =~ ~r/^\d+$/,
      do: {:ok, String.to_integer(text)},
      else: {:error, "数字で入力してください"}
  end

  @doc "A date: `YYYY-MM-DD`, or `YYYY/M/D` as Excel writes it."
  def parse_date(cell) when is_binary(cell) do
    text = normalize(cell)

    with false <- text == "",
         [_, year, month, day] <- Regex.run(~r/^(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})$/, text),
         {:ok, date} <- Date.new(to_int(year), to_int(month), to_int(day)) do
      {:ok, date}
    else
      true -> {:ok, nil}
      _ -> {:error, "日付として読み取れません（例: 2026-09-01）"}
    end
  end

  @doc "A time: `HH:MM`, `H:MM`, or `HH:MM:SS`."
  def parse_time(cell) when is_binary(cell) do
    text = normalize(cell)

    with false <- text == "",
         [_, hour, minute | rest] <- Regex.run(~r/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/, text),
         {:ok, time} <- Time.new(to_int(hour), to_int(minute), seconds(rest)) do
      {:ok, time}
    else
      true -> {:ok, nil}
      _ -> {:error, "時刻として読み取れません（例: 09:00）"}
    end
  end

  defp seconds([second]), do: to_int(second)
  defp seconds([]), do: 0

  @truthy ["○", "〇", "◯", "1", "TRUE"]
  @falsy ["", "×", "0", "FALSE"]

  @doc "A boolean: `○` (or `1` / `TRUE`) is true; blank (or `×` / `0` / `FALSE`) is false."
  def parse_bool(cell) when is_binary(cell) do
    text = cell |> normalize() |> String.upcase()

    cond do
      text in @truthy -> {:ok, true}
      text in @falsy -> {:ok, false}
      true -> {:error, "○ か空欄で入力してください"}
    end
  end

  @doc "An enum value, from the Japanese label in its enum module (`from_label/1`)."
  def parse_enum(cell, enum_module) when is_binary(cell) do
    case normalize(cell) do
      "" -> {:ok, nil}
      text -> parse_label(text, enum_module)
    end
  end

  defp parse_label(text, enum_module) do
    case enum_module.from_label(text) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        labels = Enum.map_join(enum_module.all(), "・", &enum_module.label/1)
        {:error, "次のいずれかで入力してください: #{labels}"}
    end
  end

  defp normalize(cell), do: cell |> String.normalize(:nfkc) |> String.trim()

  defp to_int(digits), do: String.to_integer(digits)
end
