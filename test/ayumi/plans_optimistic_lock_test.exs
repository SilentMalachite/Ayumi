defmodule Ayumi.PlansOptimisticLockTest do
  use Ayumi.DataCase, async: false

  alias Ayumi.Plans
  alias Ayumi.Plans.ServiceUser
  alias Ayumi.Plans.SupportPlan
  alias Ayumi.Plans.Goal

  import Ayumi.PlansFixtures

  describe "optimistic locking" do
    test "new body records start at lock_version 0" do
      assert service_user_fixture().lock_version == 0
      assert support_plan_fixture().lock_version == 0
      assert goal_fixture().lock_version == 0
    end

    test "changeset/2 ignores a lock_version supplied via params (no form tampering)" do
      cs = ServiceUser.changeset(%ServiceUser{}, %{"name" => "X", "lock_version" => "999"})
      refute Map.has_key?(cs.changes, :lock_version)
    end

    test "SupportPlan.changeset/2 ignores a lock_version supplied via params" do
      cs =
        SupportPlan.changeset(%SupportPlan{}, %{"long_term_goal" => "目標", "lock_version" => "999"})

      refute Map.has_key?(cs.changes, :lock_version)
    end

    test "Goal.changeset/2 ignores a lock_version supplied via params" do
      cs = Goal.changeset(%Goal{}, %{"description" => "目標", "lock_version" => "999"})
      refute Map.has_key?(cs.changes, :lock_version)
    end

    test "update_service_user/2 bumps lock_version on success" do
      su = service_user_fixture()
      assert su.lock_version == 0
      assert {:ok, updated} = Plans.update_service_user(su, %{phone: "03-1111-2222"})
      assert updated.lock_version == 1
    end

    test "update_service_user/2 returns {:error, :stale} on a concurrent update" do
      su = service_user_fixture()

      # Two staff load the same row (both at lock_version 0).
      a = Plans.get_service_user!(su.id)
      b = Plans.get_service_user!(su.id)

      assert {:ok, _} = Plans.update_service_user(a, %{phone: "first"})
      assert {:error, :stale} = Plans.update_service_user(b, %{phone: "second"})

      # The first writer's value survives; the second was rejected, never silently lost.
      assert Plans.get_service_user!(su.id).phone == "first"
    end
  end
end
