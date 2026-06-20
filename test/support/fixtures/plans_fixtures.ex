defmodule Ayumi.PlansFixtures do
  @moduledoc "Test fixtures for the Plans context."

  import Ayumi.AccountsFixtures

  alias Ayumi.Plans

  def service_user_fixture(attrs \\ %{}) do
    {:ok, service_user} =
      attrs
      |> Enum.into(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      |> Plans.create_service_user()

    service_user
  end

  def service_user_with_certificate_fixture(attrs \\ %{}) do
    {:ok, service_user} =
      %{
        name: "手帳 太郎",
        name_kana: "てちょう たろう",
        disability_certificates: [%{kind: :physical, number: "B-123", grade: "2級"}]
      }
      |> Map.merge(Map.new(attrs))
      |> Plans.create_service_user()

    service_user
  end

  def support_plan_fixture(attrs \\ %{}) do
    service_user_id = attrs[:service_user_id] || service_user_fixture().id
    staff_id = attrs[:staff_id] || user_fixture().id

    {:ok, support_plan} =
      attrs
      |> Enum.into(%{
        service_user_id: service_user_id,
        staff_id: staff_id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-09-30],
        long_term_goal: "安定した通所リズムを確立する",
        next_monitoring_date: ~D[2026-07-01]
      })
      |> Plans.create_support_plan()

    support_plan
  end

  def goal_fixture(attrs \\ %{}) do
    support_plan_id = attrs[:support_plan_id] || support_plan_fixture().id

    {:ok, goal} =
      attrs
      |> Enum.into(%{support_plan_id: support_plan_id, description: "毎日昼食を完食する"})
      |> Plans.create_goal()

    goal
  end

  def goal_progress_fixture(attrs \\ %{}) do
    goal_id = attrs[:goal_id] || goal_fixture().id
    recorded_by_id = attrs[:recorded_by_id] || user_fixture().id

    {:ok, goal_progress} =
      attrs
      |> Enum.into(%{
        goal_id: goal_id,
        stage: :working,
        note: "午前の作業に参加できた",
        recorded_by_id: recorded_by_id,
        recorded_at: ~U[2026-06-17 01:02:03Z]
      })
      |> Plans.record_goal_progress()

    goal_progress
  end

  def support_record_fixture(attrs \\ %{}) do
    service_user_id = attrs[:service_user_id] || service_user_fixture().id
    recorded_by = attrs[:recorded_by] || user_fixture()
    scope = Ayumi.Accounts.Scope.for_user(recorded_by)

    {:ok, record} =
      Plans.create_support_record(
        scope,
        Enum.into(attrs, %{
          service_user_id: service_user_id,
          content: "午前の作業に集中できた",
          category: :work
        })
      )

    record
  end

  def attendance_record_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    service_user_id = Map.get(attrs, :service_user_id) || service_user_fixture().id
    recorded_by = Map.get(attrs, :recorded_by) || user_fixture()
    scope = Ayumi.Accounts.Scope.for_user(recorded_by)

    defaults = %{
      service_user_id: service_user_id,
      service_date: ~D[2026-06-01],
      provision_type: :commute
    }

    {:ok, record} =
      Plans.create_attendance_record(scope, Map.merge(defaults, Map.drop(attrs, [:recorded_by])))

    record
  end

  def plan_phase_event_fixture(attrs \\ %{}) do
    support_plan_id = attrs[:support_plan_id] || support_plan_fixture().id
    recorded_by_id = attrs[:recorded_by_id] || user_fixture().id

    {:ok, plan_phase_event} =
      attrs
      |> Enum.into(%{
        support_plan_id: support_plan_id,
        stage: :assessment,
        note: "アセスメントを記録した",
        recorded_by_id: recorded_by_id,
        recorded_at: ~U[2026-06-18 01:02:03Z]
      })
      |> Plans.record_plan_phase_event()

    plan_phase_event
  end
end
