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
end
