defmodule Ayumi.Plans.GoalProgressTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.GoalProgress

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  test "requires goal_id, stage, recorded_by_id, and recorded_at" do
    changeset = GoalProgress.changeset(%GoalProgress{}, %{})

    refute changeset.valid?
    assert errors_on(changeset)[:goal_id]
    assert errors_on(changeset)[:stage]
    assert errors_on(changeset)[:recorded_by_id]
    assert errors_on(changeset)[:recorded_at]
  end

  test "rejects an unknown stage" do
    goal = goal_fixture()
    staff = user_fixture()

    changeset =
      GoalProgress.changeset(%GoalProgress{}, %{
        goal_id: goal.id,
        stage: :bogus,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:02:03Z]
      })

    refute changeset.valid?
    assert errors_on(changeset)[:stage]
  end

  test "valid with a goal, allowed stage, staff, recorded_at, and optional note" do
    goal = goal_fixture()
    staff = user_fixture()

    changeset =
      GoalProgress.changeset(%GoalProgress{}, %{
        goal_id: goal.id,
        stage: :working,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:02:03Z],
        note: "午前の作業に参加できた"
      })

    assert changeset.valid?
  end
end
