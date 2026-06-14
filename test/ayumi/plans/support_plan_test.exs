defmodule Ayumi.Plans.SupportPlanTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.SupportPlan

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  defp valid_attrs do
    %{
      service_user_id: service_user_fixture().id,
      staff_id: user_fixture().id,
      period_start: ~D[2026-04-01],
      period_end: ~D[2026-09-30],
      long_term_goal: "安定した通所リズムを確立する",
      next_monitoring_date: ~D[2026-07-01]
    }
  end

  test "valid attrs produce a valid changeset" do
    assert SupportPlan.changeset(%SupportPlan{}, valid_attrs()).valid?
  end

  test "requires all body fields" do
    changeset = SupportPlan.changeset(%SupportPlan{}, %{})
    refute changeset.valid?
    errors = errors_on(changeset)

    for field <- [:service_user_id, :staff_id, :period_start, :period_end, :long_term_goal, :next_monitoring_date] do
      assert errors[field]
    end
  end

  test "period_end before period_start is invalid" do
    attrs = %{valid_attrs() | period_start: ~D[2026-09-30], period_end: ~D[2026-04-01]}
    changeset = SupportPlan.changeset(%SupportPlan{}, attrs)
    refute changeset.valid?
    assert errors_on(changeset)[:period_end]
  end
end
