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
               ~w[利用者ID 氏名 在籍状態 支援日 区分 内容 記録者 記録日時(日本時間) 記録ID]
    end

    test "dump/1 keeps multi-line content as one cell" do
      record = %SupportRecord{
        id: 21,
        service_user_id: 3,
        service_user: @service_user,
        support_date: ~D[2026-09-16],
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
                 "2026-09-16",
                 "面談",
                 "面談を実施。\n次回は来週。",
                 "支援 花子",
                 "2026-09-17 10:02:03",
                 "21"
               ]
             ]
    end
  end

  describe "SupportRecords import" do
    @cells %{
      "利用者ID" => "3",
      "氏名" => "山田 太郎",
      "在籍状態" => "在籍",
      "支援日" => "2026/9/16",
      "区分" => "面談",
      "内容" => "面談を実施。\r\n次回は来週。",
      "記録者" => "無視される",
      "記録日時(日本時間)" => "無視される",
      "記録ID" => "21"
    }

    test "required_headers/0 leaves 記録ID optional, so hand-made files need no such column" do
      assert CSV.SupportRecords.required_headers() == ~w[利用者ID 氏名 支援日 区分 内容]
    end

    test "parse/1 reads the support itself plus 記録ID for recognizing an exported row" do
      assert CSV.SupportRecords.parse(@cells) ==
               {:ok,
                %{
                  service_user_id: 3,
                  service_user_name: "山田 太郎",
                  support_date: ~D[2026-09-16],
                  category: :interview,
                  content: "面談を実施。\n次回は来週。",
                  record_id: 21
                }}
    end

    test "parse/1 works without the optional 記録ID column" do
      assert {:ok, %{record_id: nil}} = CSV.SupportRecords.parse(Map.delete(@cells, "記録ID"))
    end

    test "parse/1 requires 支援日, 区分, and 内容" do
      cells = Map.merge(@cells, %{"支援日" => "", "区分" => "", "内容" => " "})

      assert {:error, errors} = CSV.SupportRecords.parse(cells)
      assert Enum.map(errors, & &1.column) == ["支援日", "区分", "内容"]
    end

    test "header_for/1" do
      assert CSV.SupportRecords.header_for(:support_date) == "支援日"
      assert CSV.SupportRecords.header_for(:service_user_id) == "利用者ID"
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
