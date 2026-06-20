defmodule Ayumi.Plans.SupportRecordCategory do
  @moduledoc "Support record category enumeration. Labels live here, not in views."

  @labels [
    work: "作業",
    daily_living: "生活",
    health: "健康",
    interview: "面談",
    other: "その他"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
