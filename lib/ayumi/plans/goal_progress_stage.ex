defmodule Ayumi.Plans.GoalProgressStage do
  @moduledoc "Goal progress stage enumeration. Labels live here, not in views."

  @labels [
    not_started: "未着手",
    working: "取組中",
    partially_met: "一部達成",
    mostly_met: "概ね達成",
    met: "達成"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
