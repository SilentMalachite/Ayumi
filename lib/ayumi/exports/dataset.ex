defmodule Ayumi.Exports.Dataset do
  @moduledoc "Exportable datasets. Labels live here, not in views."

  @labels [
    attendance: "出欠・実績記録"
  ]

  @file_labels [
    attendance: "出欠実績"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)

  @doc "Short Japanese label used in file names."
  def file_label(value), do: Keyword.get(@file_labels, value)
end
