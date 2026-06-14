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

  test "shows a 新規登録 link to the new form", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/service_users")
    refute has_element?(lv, "#service-user-form")
    assert html =~ "新規登録"

    {:ok, _form_lv, form_html} =
      lv |> element("a", "新規登録") |> render_click() |> follow_redirect(conn)

    assert form_html =~ "利用者の新規登録"
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

  test "shows basic info and certificates on the detail page", %{conn: conn} do
    {:ok, su} =
      Ayumi.Plans.create_service_user(%{
        name: "詳細 太郎",
        name_kana: "しょうさい たろう",
        gender: :male,
        phone: "03-1234-5678",
        recipient_cert_number: "R-777",
        disability_certificates: [%{kind: :physical, number: "B-55", grade: "2級"}]
      })

    {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

    assert html =~ "詳細 太郎"
    assert html =~ "男性"
    assert html =~ "03-1234-5678"
    assert html =~ "R-777"
    assert html =~ "身体障害者手帳"
    assert html =~ "B-55"
    assert html =~ "編集"
  end

  test "detail page shows a fallback when the user has no certificates", %{conn: conn} do
    su = service_user_fixture(%{name: "手帳なし"})
    {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

    assert html =~ "手帳なし"
    assert html =~ "登録なし"
    refute html =~ ~s(id="disability-certificates")
  end

  test "navigates to the new support plan form", %{conn: conn} do
    su = service_user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}")

    {:ok, _form_lv, html} =
      lv |> element("a", "支援計画を作成") |> render_click() |> follow_redirect(conn)

    assert html =~ "支援計画の作成"
  end

  test "creates a service user with a certificate via the new form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/service_users/new")

    params = %{
      "name" => "新規 太郎",
      "name_kana" => "しんき たろう",
      "disability_certificates" => %{
        "0" => %{"kind" => "physical", "number" => "B-9", "grade" => "2級"}
      }
    }

    {:ok, _show_lv, html} =
      lv
      |> form("#service-user-form", service_user: params)
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "新規 太郎"
    assert html =~ "B-9"
  end

  test "edits a service user via the edit form", %{conn: conn} do
    su = service_user_fixture(%{name: "編集前"})
    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

    {:ok, _show_lv, html} =
      lv
      |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "03-9999-0000"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "編集後"
    assert html =~ "03-9999-0000"
  end
end
