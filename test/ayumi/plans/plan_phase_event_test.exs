defmodule Ayumi.Plans.PlanPhaseEventTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.PlanPhaseEvent

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  test "requires support_plan_id, stage, recorded_by_id, and recorded_at" do
    changeset = PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{})

    refute changeset.valid?
    assert errors_on(changeset)[:support_plan_id]
    assert errors_on(changeset)[:stage]
    assert errors_on(changeset)[:recorded_by_id]
    assert errors_on(changeset)[:recorded_at]
  end

  test "rejects an unknown stage" do
    plan = support_plan_fixture()
    staff = staff_fixture()

    changeset =
      PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{
        support_plan_id: plan.id,
        stage: :bogus,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:02:03Z]
      })

    refute changeset.valid?
    assert errors_on(changeset)[:stage]
  end

  test "valid with a support plan, allowed stage, staff, recorded_at, and optional note" do
    plan = support_plan_fixture()
    staff = staff_fixture()

    changeset =
      PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{
        support_plan_id: plan.id,
        stage: :support_meeting,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:02:03Z],
        note: "会議で支援内容を確認した"
      })

    assert changeset.valid?
  end
end
