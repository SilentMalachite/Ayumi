defmodule AyumiWeb.ServiceUserLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

  test "shows a service user with their support plans", %{conn: conn} do
    su = service_user_fixture(%{name: "表示 利用者"})
    support_plan_fixture(%{service_user_id: su.id, long_term_goal: "長期目標テキスト"})

    {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
    assert html =~ "表示 利用者"
    assert html =~ "長期目標テキスト"
  end
end
