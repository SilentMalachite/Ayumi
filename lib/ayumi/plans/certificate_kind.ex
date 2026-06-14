defmodule Ayumi.Plans.CertificateKind do
  @moduledoc "Disability certificate (障害者手帳) kind enumeration. Labels live here."

  @labels [
    physical: "身体障害者手帳",
    intellectual: "療育手帳",
    mental: "精神障害者保健福祉手帳"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
