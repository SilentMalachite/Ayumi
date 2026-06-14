defmodule Ayumi.Plans.GoalTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.Goal

  import Ayumi.PlansFixtures

  test "requires support_plan_id and description" do
    changeset = Goal.changeset(%Goal{}, %{})
    refute changeset.valid?
    assert errors_on(changeset)[:support_plan_id]
    assert errors_on(changeset)[:description]
  end

  test "valid with a plan and description" do
    plan = support_plan_fixture()
    changeset = Goal.changeset(%Goal{}, %{support_plan_id: plan.id, description: "毎日昼食を完食する"})
    assert changeset.valid?
  end
end
