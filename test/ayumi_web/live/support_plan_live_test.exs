defmodule AyumiWeb.SupportPlanLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_manager

  test "退所者の支援計画作成フォームはまとめ画面へリダイレクトする", %{conn: conn} do
    su = service_user_fixture(enrollment_status: :withdrawn)

    {:error, redirect} = live(conn, ~p"/service_users/#{su.id}/support_plans/new")
    assert {_kind, %{to: path}} = redirect
    assert path == ~p"/service_users/#{su.id}"
  end

  test "在籍者の支援計画作成フォームは開ける", %{conn: conn} do
    su = service_user_fixture()
    {:ok, _lv, _html} = live(conn, ~p"/service_users/#{su.id}/support_plans/new")
  end

  test "creates a support plan for a service user", %{conn: conn, user: staff} do
    su = service_user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/support_plans/new")

    params = %{
      staff_id: staff.id,
      period_start: "2026-04-01",
      period_end: "2026-09-30",
      long_term_goal: "長期目標テキスト",
      next_monitoring_date: "2026-07-01"
    }

    lv
    |> form("#support-plan-form", support_plan: params)
    |> render_submit()

    assert_redirect(lv, ~p"/service_users/#{su.id}")
    assert [plan] = Ayumi.Plans.list_support_plans_for_user(su)
    assert plan.long_term_goal == "長期目標テキスト"
  end

  test "shows validation errors", %{conn: conn} do
    su = service_user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/support_plans/new")

    html =
      lv
      |> form("#support-plan-form", support_plan: %{long_term_goal: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "入力してください"
  end

  test "shows a plan and adds a goal", %{conn: conn} do
    plan = support_plan_fixture()

    {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")
    assert html =~ plan.long_term_goal

    html =
      lv
      |> form("#goal-form", goal: %{description: "毎日昼食を完食する"})
      |> render_submit()

    assert html =~ "毎日昼食を完食する"
  end

  test "records goal progress and shows current progress and history", %{conn: conn, user: staff} do
    plan = support_plan_fixture()
    goal = goal_fixture(%{support_plan_id: plan.id, description: "毎日昼食を完食する"})

    {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")

    assert has_element?(lv, "#goal-progress-form-#{goal.id}")
    assert html =~ "未記録"

    html =
      lv
      |> form("#goal-progress-form-#{goal.id}",
        goal_progress: %{stage: "working", note: "午前の作業に参加できた"}
      )
      |> render_submit()

    assert html =~ "取組中"
    assert html =~ "午前の作業に参加できた"
    assert html =~ (staff.name || staff.email)

    assert [progress] = Ayumi.Plans.list_goal_progress(goal)
    assert progress.recorded_by_id == staff.id
  end

  test "records a plan phase event and shows current phase and history", %{
    conn: conn,
    user: staff
  } do
    plan = support_plan_fixture()

    {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")

    assert has_element?(lv, "#plan-phase-form")
    assert html =~ "未記録"

    html =
      lv
      |> form("#plan-phase-form",
        plan_phase_event: %{stage: "support_meeting", note: "会議で支援内容を確認した"}
      )
      |> render_submit()

    assert html =~ "個別支援会議"
    assert html =~ "会議で支援内容を確認した"
    assert html =~ (staff.name || staff.email)

    assert [event] = Ayumi.Plans.list_plan_phase_events(plan)
    assert event.recorded_by_id == staff.id
  end

  test "rejects forged goal progress for a goal from another support plan", %{conn: conn} do
    plan = support_plan_fixture()
    visible_goal = goal_fixture(%{support_plan_id: plan.id})
    other_plan = support_plan_fixture()
    other_goal = goal_fixture(%{support_plan_id: other_plan.id})

    {:ok, lv, _html} = live(conn, ~p"/support_plans/#{plan.id}")

    html =
      render_submit(lv, "record_goal_progress", %{
        "goal_id" => to_string(other_goal.id),
        "goal_progress" => %{"stage" => "working", "note" => "改ざんされた記録"}
      })

    assert html =~ "進捗を記録できませんでした"
    assert has_element?(lv, "#goal-progress-form-#{visible_goal.id}")
    assert Ayumi.Plans.list_goal_progress(other_goal) == []
  end

  test "rejects nonnumeric goal progress goal_id without crashing", %{conn: conn} do
    plan = support_plan_fixture()
    visible_goal = goal_fixture(%{support_plan_id: plan.id})

    {:ok, lv, _html} = live(conn, ~p"/support_plans/#{plan.id}")

    html =
      render_submit(lv, "record_goal_progress", %{
        "goal_id" => "not-a-goal-id",
        "goal_progress" => %{"stage" => "working", "note" => "改ざんされた記録"}
      })

    assert html =~ "進捗を記録できませんでした"
    assert has_element?(lv, "#goal-progress-form-#{visible_goal.id}")
  end

  test "rejects missing goal progress goal_id without crashing", %{conn: conn} do
    plan = support_plan_fixture()
    visible_goal = goal_fixture(%{support_plan_id: plan.id})

    {:ok, lv, _html} = live(conn, ~p"/support_plans/#{plan.id}")

    html =
      render_submit(lv, "record_goal_progress", %{
        "goal_progress" => %{"stage" => "working", "note" => "改ざんされた記録"}
      })

    assert html =~ "進捗を記録できませんでした"
    assert has_element?(lv, "#goal-progress-form-#{visible_goal.id}")
    assert Ayumi.Plans.list_goal_progress(visible_goal) == []
  end

  describe "supporter access to support plans" do
    setup :register_and_log_in_user

    test "supporter cannot access new support plan form", %{conn: conn} do
      su = service_user_fixture()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/service_users/#{su.id}/support_plans/new")
    end

    test "supporter can view support plan and record progress", %{conn: conn} do
      plan = support_plan_fixture()
      goal = goal_fixture(%{support_plan_id: plan.id, description: "目標テスト"})

      {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")
      assert html =~ plan.long_term_goal

      html =
        lv
        |> form("#goal-progress-form-#{goal.id}",
          goal_progress: %{stage: "working", note: "支援者が記録"}
        )
        |> render_submit()

      assert html =~ "取組中"
      assert html =~ "支援者が記録"
    end
  end
end
