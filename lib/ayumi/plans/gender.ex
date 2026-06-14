defmodule Ayumi.Plans.Gender do
  @moduledoc "Gender enumeration for a service user. Labels live here, not in views."

  @labels [male: "男性", female: "女性", other: "その他"]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
