defmodule Ayumi.Exports.RequestTest do
  use ExUnit.Case, async: true

  alias Ayumi.Exports.Request

  @valid %{"dataset" => "attendance", "unit" => "month", "anchor_date" => "2026-09-17"}

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  test "casts string params from a form or a query string" do
    changeset = Request.changeset(%Request{}, Map.put(@valid, "service_user_id", "12"))

    assert changeset.valid?

    assert %Request{
             dataset: :attendance,
             unit: :month,
             anchor_date: ~D[2026-09-17],
             service_user_id: 12
           } = Ecto.Changeset.apply_changes(changeset)
  end

  test "a blank service user means every service user" do
    changeset = Request.changeset(%Request{}, Map.put(@valid, "service_user_id", ""))

    assert changeset.valid?
    assert Ecto.Changeset.apply_changes(changeset).service_user_id == nil
  end

  test "requires dataset, unit, and anchor date, with Japanese messages" do
    changeset = Request.changeset(%Request{}, %{})

    refute changeset.valid?

    assert errors_on(changeset) == %{
             dataset: ["を選択してください"],
             unit: ["を選択してください"],
             anchor_date: ["を指定してください"]
           }
  end

  test "rejects unknown datasets and units and malformed dates" do
    changeset =
      Request.changeset(%Request{}, %{
        "dataset" => "passwords",
        "unit" => "decade",
        "anchor_date" => "2026-13-40"
      })

    refute changeset.valid?
    assert Map.keys(errors_on(changeset)) |> Enum.sort() == [:anchor_date, :dataset, :unit]
  end
end
