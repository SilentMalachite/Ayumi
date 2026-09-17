defmodule Ayumi.CSV.LogDatasetsTest do
  use ExUnit.Case, async: true

  alias Ayumi.Accounts.User
  alias Ayumi.CSV
  alias Ayumi.Plans.{Goal, GoalProgress, PlanPhaseEvent, ServiceUser, SupportPlan, SupportRecord}

  @service_user %ServiceUser{id: 3, name: "山田 太郎", enrollment_status: :withdrawn}
  @recorder %User{name: "支援 花子", email: "hanako@example.com"}
  @plan %SupportPlan{
    id: 11,
    period_start: ~D[2026-04-01],
    period_end: ~D[2026-09-30],
    service_user: @service_user
  }

  describe "SupportRecords" do
    test "headers/0" do
      assert CSV.SupportRecords.headers() ==
               ~w[利用者ID 氏名 在籍状態 区分 内容 記録者 記録日時(日本時間) 記録ID]
    end

    test "dump/1 keeps multi-line content as one cell" do
      record = %SupportRecord{
        id: 21,
        service_user_id: 3,
        service_user: @service_user,
        category: :interview,
        content: "面談を実施。\n次回は来週。",
        recorded_by: @recorder,
        recorded_at: ~U[2026-09-17 01:02:03Z]
      }

      assert CSV.SupportRecords.dump([record]) == [
               [
                 "3",
                 "山田 太郎",
                 "退所",
                 "面談",
                 "面談を実施。\n次回は来週。",
                 "支援 花子",
                 "2026-09-17 10:02:03",
                 "21"
               ]
             ]
    end
  end

  describe "GoalProgress" do
    test "headers/0" do
      assert CSV.GoalProgress.headers() ==
               ~w[利用者ID 氏名 在籍状態 計画ID 計画期間開始 計画期間終了 目標ID 短期目標 進捗 所見 記録者 記録日時(日本時間) 記録ID]
    end

    test "dump/1 walks goal → plan → service user" do
      progress = %GoalProgress{
        id: 31,
        goal_id: 5,
        goal: %Goal{id: 5, description: "週3日通所する", support_plan: @plan},
        stage: :mostly_met,
        note: nil,
        recorded_by: @recorder,
        recorded_at: ~U[2026-09-17 01:02:03Z]
      }

      assert CSV.GoalProgress.dump([progress]) == [
               [
                 "3",
                 "山田 太郎",
                 "退所",
                 "11",
                 "2026-04-01",
                 "2026-09-30",
                 "5",
                 "週3日通所する",
                 "概ね達成",
                 "",
                 "支援 花子",
                 "2026-09-17 10:02:03",
                 "31"
               ]
             ]
    end
  end

  describe "PlanPhaseEvents" do
    test "headers/0" do
      assert CSV.PlanPhaseEvents.headers() ==
               ~w[利用者ID 氏名 在籍状態 計画ID 計画期間開始 計画期間終了 段階 所見 記録者 記録日時(日本時間) 記録ID]
    end

    test "dump/1 walks plan → service user" do
      event = %PlanPhaseEvent{
        id: 41,
        support_plan_id: 11,
        support_plan: @plan,
        stage: :monitoring,
        note: "モニタリング実施",
        recorded_by: @recorder,
        recorded_at: ~U[2026-09-17 01:02:03Z]
      }

      assert CSV.PlanPhaseEvents.dump([event]) == [
               [
                 "3",
                 "山田 太郎",
                 "退所",
                 "11",
                 "2026-04-01",
                 "2026-09-30",
                 "モニタリング",
                 "モニタリング実施",
                 "支援 花子",
                 "2026-09-17 10:02:03",
                 "41"
               ]
             ]
    end
  end
end
