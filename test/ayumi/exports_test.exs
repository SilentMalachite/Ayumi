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

  describe "the service user master" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "has no period", %{scope: _scope} do
      changeset = Exports.change_request(%{"dataset" => "service_users"})

      assert changeset.valid?
      refute Exports.periodic?(changeset)
      assert Exports.period_label(changeset) == nil
      assert Exports.request_params(changeset) == %{"dataset" => "service_users"}
    end

    test "the other datasets are periodic" do
      assert Exports.periodic?(Exports.change_request())
      assert Exports.periodic?(Exports.change_request(params(%{"dataset" => "support_records"})))
    end

    test "build/2 exports every service user, withdrawn included, in list order", %{
      scope: scope
    } do
      _ = service_user_fixture(%{name: "佐藤", name_kana: "さとう"})
      _ = service_user_fixture(%{name: "阿部", name_kana: "あべ", enrollment_status: :withdrawn})
      _ = service_user_with_certificate_fixture(%{name: "手帳 太郎", name_kana: "てちょう"})

      assert {:ok, %{filename: filename, content: content}} =
               Exports.build(scope, %{"dataset" => "service_users"})

      assert filename == "利用者台帳_#{Date.to_iso8601(Ayumi.JST.today())}.csv"
      assert content =~ Enum.join(Ayumi.CSV.ServiceUsers.headers(), ",")

      assert [abe, sato, techo] = data_lines(content)
      assert abe =~ "阿部,あべ,,,退所"
      assert sato =~ "佐藤,さとう,,,在籍"
      assert techo =~ "身体障害者手帳 B-123 2級"
    end

    test "build/2 ignores period params for the master", %{scope: scope} do
      _ = service_user_fixture(%{name: "佐藤"})

      assert {:ok, %{content: content}} =
               Exports.build(scope, params(%{"dataset" => "service_users"}))

      assert [_line] = data_lines(content)
    end
  end

  describe "build/2 for the logs" do
    setup do
      %{scope: user_scope_fixture()}
    end

    defp log_params(dataset, attrs \\ %{}) do
      Map.merge(
        %{"dataset" => dataset, "unit" => "month", "anchor_date" => "2026-09-15"},
        attrs
      )
    end

    test "support records are selected by support date, not by when they were typed in", %{
      scope: scope
    } do
      su = service_user_fixture(%{name: "山田 太郎"})

      for {date, content} <- [
            {~D[2026-05-31], "五月の最後"},
            {~D[2026-06-01], "六月の最初"},
            {~D[2026-06-30], "六月の最後"},
            {~D[2026-07-01], "七月の最初"}
          ] do
        support_record_fixture(%{service_user_id: su.id, support_date: date, content: content})
      end

      assert {:ok, %{filename: filename, content: content}} =
               Exports.build(
                 scope,
                 log_params("support_records", %{"anchor_date" => "2026-06-15"})
               )

      assert filename == "支援記録_2026年06月.csv"
      assert [first, last] = data_lines(content)
      assert first =~ "山田 太郎,在籍,2026-06-01,作業,六月の最初"
      assert last =~ "2026-06-30,作業,六月の最後"
    end

    test "support records of withdrawn service users are included", %{scope: scope} do
      su = service_user_fixture(%{name: "のちに退所"})
      _ = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-10]})

      {:ok, _} =
        su.id
        |> Ayumi.Plans.get_service_user!()
        |> Ayumi.Plans.update_service_user(%{enrollment_status: :withdrawn})

      assert {:ok, %{content: content}} =
               Exports.build(
                 scope,
                 log_params("support_records", %{"anchor_date" => "2026-06-15"})
               )

      assert [line] = data_lines(content)
      assert line =~ "のちに退所,退所"
    end

    test "goal progress history", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})
      plan = support_plan_fixture(%{service_user_id: su.id})
      goal = goal_fixture(%{support_plan_id: plan.id, description: "週3日通所する"})

      _ =
        goal_progress_fixture(%{
          goal_id: goal.id,
          stage: :met,
          recorded_at: ~U[2026-09-10 00:00:00Z]
        })

      # 2026-08-31 23:59:59 JST is still August in Japan; one second later is September.
      _ = goal_progress_fixture(%{goal_id: goal.id, recorded_at: ~U[2026-08-31 14:59:59Z]})

      _ =
        goal_progress_fixture(%{
          goal_id: goal.id,
          stage: :working,
          recorded_at: ~U[2026-08-31 15:00:00Z]
        })

      # 2026-10-01 00:00:00 JST is already October.
      _ = goal_progress_fixture(%{goal_id: goal.id, recorded_at: ~U[2026-09-30 15:00:00Z]})
      _ = goal_progress_fixture(%{recorded_at: ~U[2026-09-10 00:00:00Z]})

      assert {:ok, %{filename: filename, content: content}} =
               Exports.build(
                 scope,
                 log_params("goal_progress", %{"service_user_id" => Integer.to_string(su.id)})
               )

      assert filename == "目標進捗_2026年09月_利用者#{su.id}.csv"
      assert content =~ Enum.join(Ayumi.CSV.GoalProgress.headers(), ",")
      assert [first_second, line] = data_lines(content)
      assert first_second =~ "2026-09-01 00:00:00"
      assert line =~ "週3日通所する,達成"
      assert line =~ "2026-09-10 09:00:00"
    end

    test "plan phase history", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})
      plan = support_plan_fixture(%{service_user_id: su.id})

      _ =
        plan_phase_event_fixture(%{
          support_plan_id: plan.id,
          stage: :monitoring,
          recorded_at: ~U[2026-09-10 00:00:00Z]
        })

      _ =
        plan_phase_event_fixture(%{
          support_plan_id: plan.id,
          recorded_at: ~U[2026-10-10 00:00:00Z]
        })

      assert {:ok, %{filename: filename, content: content}} =
               Exports.build(scope, log_params("plan_phase_events"))

      assert filename == "計画段階_2026年09月.csv"
      assert content =~ Enum.join(Ayumi.CSV.PlanPhaseEvents.headers(), ",")
      assert [line] = data_lines(content)
      assert line =~ "山田 太郎,在籍"
      assert line =~ "モニタリング"
    end
  end
end
