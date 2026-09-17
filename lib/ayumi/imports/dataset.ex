defmodule Ayumi.Imports.Dataset do
  @moduledoc "Importable datasets. Labels live here, not in views."

  @labels [
    attendance: "出欠・実績記録",
    support_records: "支援記録",
    service_users: "利用者台帳"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for a select."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)

  @doc "Casts a form value to a dataset without creating atoms. `:error` when unknown."
  def from_param(param) do
    case Enum.find(all(), &(Atom.to_string(&1) == param)) do
      nil -> :error
      dataset -> {:ok, dataset}
    end
  end
end
