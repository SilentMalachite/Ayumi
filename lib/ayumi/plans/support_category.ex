defmodule Ayumi.Plans.SupportCategory do
  @moduledoc "Disability support category (障害支援区分) enumeration. Labels live here."

  @labels [
    not_applicable: "非該当",
    category_1: "区分1",
    category_2: "区分2",
    category_3: "区分3",
    category_4: "区分4",
    category_5: "区分5",
    category_6: "区分6"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "Value for a Japanese label (CSV import); the inverse of `label/1`. `:error` when unknown."
  def from_label(label) do
    case List.keyfind(@labels, label, 1) do
      {value, _label} -> {:ok, value}
      nil -> :error
    end
  end

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
