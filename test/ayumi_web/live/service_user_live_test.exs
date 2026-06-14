defmodule AyumiWeb.ServiceUserLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

  test "lists existing service users", %{conn: conn} do
    service_user_fixture(%{name: "既存 利用者"})
    {:ok, _lv, html} = live(conn, ~p"/service_users")
    assert html =~ "既存 利用者"
  end

  test "creates a service user", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/service_users")

    html =
      lv
      |> form("#service-user-form", service_user: %{name: "新規 利用者", name_kana: "しんき"})
      |> render_submit()

    assert html =~ "新規 利用者"
  end

  test "requires login", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/service_users")
  end

  test "shows a service user with their support plans", %{conn: conn} do
    su = service_user_fixture(%{name: "表示 利用者"})
    support_plan_fixture(%{service_user_id: su.id, long_term_goal: "長期目標テキスト"})

    {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
    assert html =~ "表示 利用者"
    assert html =~ "長期目標テキスト"
  end
end
