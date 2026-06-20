defmodule Ayumi.Plans.ProvisionType do
  @moduledoc "サービス提供形態（実績記録票）。ラベルはここに集約し、view に散らさない。"

  @labels [
    commute: "通所",
    offsite_work: "施設外就労",
    offsite_support: "施設外支援",
    absence: "欠席",
    absence_support: "欠席時対応"
  ]

  @doc "全値（表示順）。"
  def all, do: Keyword.keys(@labels)

  @doc "値の日本語ラベル。未知/nil は nil。"
  def label(value), do: Keyword.get(@labels, value)

  @doc "`<.input type=\"select\">` 用の `[{label, value}]`。"
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)

  @doc "利用日数の算定対象となる提供形態。"
  def billable, do: [:commute, :offsite_work, :offsite_support]
end
