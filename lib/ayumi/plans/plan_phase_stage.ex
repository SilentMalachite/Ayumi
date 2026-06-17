defmodule Ayumi.Plans.PlanPhaseStage do
  @moduledoc "Support-plan lifecycle stage enumeration. Labels live here, not in views."

  @labels [
    assessment: "アセスメント",
    draft: "計画原案",
    support_meeting: "個別支援会議",
    consent: "説明・同意・交付",
    in_progress: "支援の実施",
    monitoring: "モニタリング",
    review: "見直し"
  ]

  @doc "All values, in lifecycle display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
