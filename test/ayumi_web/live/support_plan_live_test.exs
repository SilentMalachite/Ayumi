defmodule AyumiWeb.SupportPlanLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

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
end
