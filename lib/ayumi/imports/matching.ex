defmodule Ayumi.Imports.Matching do
  @moduledoc """
  Keys for recognizing the same person or number across a CSV file and the
  database, tolerant of what Excel and keyboards do to text.
  """

  @doc "A name ignoring width and spacing: 「山田　太郎」 equals 「山田 太郎」."
  def name_key(name) when is_binary(name) do
    name |> String.normalize(:nfkc) |> String.replace(~r/\s/u, "")
  end

  @doc """
  A 受給者証番号 ignoring width, spacing, and leading zeros — Excel drops the
  leading zero of a 10-digit number. nil for a blank number.
  """
  def cert_key(nil), do: nil

  def cert_key(number) when is_binary(number) do
    case number |> name_key() |> String.trim_leading("0") do
      "" -> nil
      key -> key
    end
  end
end
