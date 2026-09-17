defmodule Ayumi.Plans.EnrollmentStatus do
  @moduledoc "Enrollment status enumeration for a service user. Labels live here, not in views."

  @labels [trial: "体験利用", enrolled: "在籍", suspended: "休止", withdrawn: "退所"]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Values considered active (not withdrawn)."
  def active_values, do: [:trial, :enrolled, :suspended]

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
