defmodule Ayumi.ExportsTest do
  use Ayumi.DataCase, async: false

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  alias Ayumi.CSV.Attendance
  alias Ayumi.Exports

  @bom "﻿"

  defp params(attrs \\ %{}) do
    Map.merge(
      %{"dataset" => "attendance", "unit" => "month", "anchor_date" => "2026-06-15"},
      attrs
    )
  end

  defp data_lines(content) do
    @bom <> csv = content
    [_header | lines] = String.split(csv, "\r\n", trim: true)
    lines
  end

  describe "change_request/1" do
    test "defaults to this month's attendance" do
      request = Exports.change_request() |> Ecto.Changeset.apply_changes()

      assert request.dataset == :attendance
      assert request.unit == :month
      assert request.anchor_date == Ayumi.JST.today()
      assert request.service_user_id == nil
    end

    test "validates form params" do
      changeset = Exports.change_request(params(%{"anchor_date" => ""}))

      refute changeset.valid?
      assert changeset.action == :validate
    end
  end

  describe "period_label/1 and request_params/1" do
    test "describe a valid request" do
      changeset = Exports.change_request(params(%{"service_user_id" => "5"}))

      assert Exports.period_label(changeset) == "2026年6月（2026-06-01 〜 2026-06-30）"

      assert Exports.request_params(changeset) == %{
               "dataset" => "attendance",
               "unit" => "month",
               "anchor_date" => "2026-06-15",
               "service_user_id" => "5"
             }
    end

    test "omit the service user when none is selected" do
      changeset = Exports.change_request(params())

      refute Map.has_key?(Exports.request_params(changeset), "service_user_id")
    end

    test "are nil for an invalid request" do
      changeset = Exports.change_request(params(%{"unit" => ""}))

      assert Exports.period_label(changeset) == nil
      assert Exports.request_params(changeset) == nil
    end
  end

  describe "build/2 for attendance" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "returns a BOM-prefixed CSV with the attendance headers", %{scope: scope} do
      assert {:ok, %{filename: filename, content: content}} = Exports.build(scope, params())

      assert filename == "出欠実績_2026年06月.csv"
      assert content == @bom <> Enum.join(Attendance.headers(), ",") <> "\r\n"
    end

    test "exports only the latest row per service user and date", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})
      _ = attendance_record_fixture(%{service_user_id: su.id, provision_type: :commute})

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          provision_type: :absence,
          note: "訂正"
        })

      assert {:ok, %{content: content}} = Exports.build(scope, params())
      assert [line] = data_lines(content)
      assert line =~ "山田 太郎,2026-06-01,月,欠席"
      assert line =~ "訂正"
    end

    test "limits rows to the period containing the anchor date", %{scope: scope} do
      su = service_user_fixture()

      for date <- [~D[2026-05-31], ~D[2026-06-01], ~D[2026-06-30], ~D[2026-07-01]] do
        attendance_record_fixture(%{service_user_id: su.id, service_date: date})
      end

      assert {:ok, %{content: month}} = Exports.build(scope, params())
      assert length(data_lines(month)) == 2

      assert {:ok, %{content: week, filename: filename}} =
               Exports.build(scope, params(%{"unit" => "week", "anchor_date" => "2026-06-03"}))

      # The week of Monday 2026-06-01.
      assert filename == "出欠実績_2026-06-01週.csv"
      assert [line] = data_lines(week)
      assert line =~ "2026-06-01"

      assert {:ok, %{content: year}} =
               Exports.build(scope, params(%{"unit" => "fiscal_year"}))

      assert length(data_lines(year)) == 4
    end

    test "sorts by kana, then name, then date", %{scope: scope} do
      sato = service_user_fixture(%{name: "佐藤", name_kana: "サトウ"})
      abe = service_user_fixture(%{name: "阿部", name_kana: "アベ"})
      _ = attendance_record_fixture(%{service_user_id: sato.id, service_date: ~D[2026-06-01]})
      _ = attendance_record_fixture(%{service_user_id: abe.id, service_date: ~D[2026-06-02]})
      _ = attendance_record_fixture(%{service_user_id: abe.id, service_date: ~D[2026-06-01]})

      assert {:ok, %{content: content}} = Exports.build(scope, params())

      assert content |> data_lines() |> Enum.map(&(String.split(&1, ",") |> Enum.slice(1..2))) ==
               [["阿部", "2026-06-01"], ["阿部", "2026-06-02"], ["佐藤", "2026-06-01"]]
    end

    test "filters by service user and names the file after the id", %{scope: scope} do
      su = service_user_fixture(%{name: "対象者"})
      other = service_user_fixture(%{name: "別の人"})
      _ = attendance_record_fixture(%{service_user_id: su.id})
      _ = attendance_record_fixture(%{service_user_id: other.id})

      assert {:ok, %{filename: filename, content: content}} =
               Exports.build(scope, params(%{"service_user_id" => Integer.to_string(su.id)}))

      assert filename == "出欠実績_2026年06月_利用者#{su.id}.csv"
      assert [line] = data_lines(content)
      assert line =~ "対象者"
    end

    test "includes withdrawn service users", %{scope: scope} do
      su = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})
      _ = attendance_record_fixture(%{service_user_id: su.id})

      assert {:ok, %{content: content}} = Exports.build(scope, params())
      assert [line] = data_lines(content)
      assert line =~ "退所者"
    end

    test "returns an error changeset for invalid params", %{scope: scope} do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Exports.build(scope, params(%{"dataset" => "nope"}))
    end
  end
end
