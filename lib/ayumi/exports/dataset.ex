defmodule Ayumi.Exports.Dataset do
  @moduledoc "Exportable datasets. Labels live here, not in views."

  @labels [
    attendance: "出欠・実績記録",
    support_records: "支援記録",
    goal_progress: "目標進捗の履歴",
    plan_phase_events: "計画段階の履歴",
    service_users: "利用者台帳"
  ]

  @file_labels [
    attendance: "出欠実績",
    support_records: "支援記録",
    goal_progress: "目標進捗",
    plan_phase_events: "計画段階",
    service_users: "利用者台帳"
  ]

  # Datasets that are a current list rather than a dated log.
  @non_periodic [:service_users]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)

  @doc "Whether the dataset is exported for a period. False for master lists."
  def periodic?(value), do: value not in @non_periodic

  @doc "Short Japanese label used in file names."
  def file_label(value), do: Keyword.get(@file_labels, value)
end
