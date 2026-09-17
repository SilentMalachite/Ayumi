defmodule Ayumi.Plans.LogRangeQueriesTest do
  use Ayumi.DataCase, async: false

  import Ayumi.PlansFixtures

  alias Ayumi.Plans
  alias Ayumi.Plans.SupportRecord

  # September 2026 in JST, as the half-open UTC range Ayumi.JST.utc_range/2 yields.
  @from ~U[2026-08-31 15:00:00Z]
  @to ~U[2026-09-30 15:00:00Z]

  defp support_record_at(recorded_at, attrs \\ %{}) do
    record = support_record_fixture(attrs)

    Repo.update_all(from(r in SupportRecord, where: r.id == ^record.id),
      set: [recorded_at: recorded_at]
    )

    record
  end

  defp goal_for(service_user) do
    plan = support_plan_fixture(%{service_user_id: service_user.id})
    goal_fixture(%{support_plan_id: plan.id})
  end

  describe "list_support_records_between/3" do
    test "includes the lower bound and excludes the upper bound" do
      first_second = support_record_at(@from)
      last_second = support_record_at(DateTime.add(@to, -1, :second))
      too_early = support_record_at(DateTime.add(@from, -1, :second))
      too_late = support_record_at(@to)

      ids = @from |> Plans.list_support_records_between(@to) |> Enum.map(& &1.id)

      assert ids == [first_second.id, last_second.id]
      refute too_early.id in ids
      refute too_late.id in ids
    end

    test "orders by recorded_at, then id" do
      later = support_record_at(~U[2026-09-10 00:00:00Z])
      earlier = support_record_at(~U[2026-09-05 00:00:00Z])
      same_time = support_record_at(~U[2026-09-05 00:00:00Z])

      assert @from |> Plans.list_support_records_between(@to) |> Enum.map(& &1.id) ==
               [earlier.id, same_time.id, later.id]
    end

    test "includes records of service users who have since withdrawn" do
      su = service_user_fixture(%{name: "のちに退所"})
      record = support_record_at(~U[2026-09-05 00:00:00Z], %{service_user_id: su.id})
      su = Plans.get_service_user!(su.id)
      {:ok, _} = Plans.update_service_user(su, %{enrollment_status: :withdrawn})

      assert [row] = Plans.list_support_records_between(@from, @to)
      assert row.id == record.id
      assert row.service_user.enrollment_status == :withdrawn
    end

    test "filters by :service_user_id and preloads the recorder" do
      su = service_user_fixture()
      mine = support_record_at(~U[2026-09-05 00:00:00Z], %{service_user_id: su.id})
      _other = support_record_at(~U[2026-09-05 00:00:00Z])

      assert [row] = Plans.list_support_records_between(@from, @to, service_user_id: su.id)
      assert row.id == mine.id
      assert %Ayumi.Accounts.User{} = row.recorded_by
    end
  end

  describe "list_goal_progress_between/3" do
    test "returns rows in the half-open range, oldest first, with the plan chain preloaded" do
      su = service_user_fixture(%{name: "山田 太郎"})
      goal = goal_for(su)
      inside = goal_progress_fixture(%{goal_id: goal.id, recorded_at: @from})
      _early = goal_progress_fixture(%{goal_id: goal.id, recorded_at: ~U[2026-08-31 14:59:59Z]})
      _late = goal_progress_fixture(%{goal_id: goal.id, recorded_at: @to})

      assert [row] = Plans.list_goal_progress_between(@from, @to)
      assert row.id == inside.id
      assert row.goal.support_plan.service_user.name == "山田 太郎"
      assert %Ayumi.Accounts.User{} = row.recorded_by
    end

    test "filters by :service_user_id through the goal's plan" do
      su = service_user_fixture()
      mine = goal_progress_fixture(%{goal_id: goal_for(su).id, recorded_at: @from})
      _other = goal_progress_fixture(%{recorded_at: @from})

      assert [row] = Plans.list_goal_progress_between(@from, @to, service_user_id: su.id)
      assert row.id == mine.id
    end
  end

  describe "list_plan_phase_events_between/3" do
    test "returns rows in the half-open range, oldest first, with the plan chain preloaded" do
      su = service_user_fixture(%{name: "山田 太郎"})
      plan = support_plan_fixture(%{service_user_id: su.id})
      inside = plan_phase_event_fixture(%{support_plan_id: plan.id, recorded_at: @from})

      _early =
        plan_phase_event_fixture(%{
          support_plan_id: plan.id,
          recorded_at: ~U[2026-08-31 14:59:59Z]
        })

      _late = plan_phase_event_fixture(%{support_plan_id: plan.id, recorded_at: @to})

      assert [row] = Plans.list_plan_phase_events_between(@from, @to)
      assert row.id == inside.id
      assert row.support_plan.service_user.name == "山田 太郎"
      assert %Ayumi.Accounts.User{} = row.recorded_by
    end

    test "filters by :service_user_id through the plan" do
      su = service_user_fixture()
      plan = support_plan_fixture(%{service_user_id: su.id})
      mine = plan_phase_event_fixture(%{support_plan_id: plan.id, recorded_at: @from})
      _other = plan_phase_event_fixture(%{recorded_at: @from})

      assert [row] = Plans.list_plan_phase_events_between(@from, @to, service_user_id: su.id)
      assert row.id == mine.id
    end
  end
end
