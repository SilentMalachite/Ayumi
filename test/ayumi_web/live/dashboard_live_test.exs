defmodule AyumiWeb.DashboardLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "authenticated dashboard" do
    setup :register_and_log_in_user

    test "shows an empty state when there are no monitoring alerts", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#monitoring-alerts")
      assert has_element?(lv, "#monitoring-alerts-empty")
    end

    test "pushes notify-deadlines event with alert counts", %{conn: conn, user: staff} do
      service_user = service_user_fixture(%{name: "通知 太郎", name_kana: "つうち たろう"})

      support_plan_fixture(%{
        service_user_id: service_user.id,
        staff_id: staff.id,
        next_monitoring_date: Date.add(Date.utc_today(), -3)
      })

      support_plan_fixture(%{
        service_user_id: service_user_fixture(%{name: "通知 花子", name_kana: "つうち はなこ"}).id,
        staff_id: staff.id,
        next_monitoring_date: Date.add(Date.utc_today(), 10)
      })

      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "notify-deadlines", %{overdue: 1, near: 1})
    end

    test "does not push notify-deadlines when no alerts", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      refute_push_event(lv, "notify-deadlines", %{})
    end

    test "shows overdue and near monitoring deadlines", %{conn: conn, user: staff} do
      service_user = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})

      overdue_plan =
        support_plan_fixture(%{
          service_user_id: service_user.id,
          staff_id: staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), -1)
        })

      {:ok, lv, html} = live(conn, ~p"/")

      assert has_element?(lv, "#monitoring-alert-#{overdue_plan.id}")
      assert html =~ "山田 太郎"
      assert html =~ "超過"
      assert html =~ ~p"/support_plans/#{overdue_plan.id}"
      assert html =~ ~p"/service_users/#{service_user.id}"
    end

    test "sorts current staff alerts first", %{conn: conn, user: current_staff} do
      other_staff = staff_fixture(%{name: "別 職員"})
      own_user = service_user_fixture(%{name: "自分 担当", name_kana: "じぶん たんとう"})
      other_user = service_user_fixture(%{name: "他 担当", name_kana: "た たんとう"})

      own_plan =
        support_plan_fixture(%{
          service_user_id: own_user.id,
          staff_id: current_staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), 7)
        })

      other_plan =
        support_plan_fixture(%{
          service_user_id: other_user.id,
          staff_id: other_staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), -10)
        })

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "monitoring-alert-#{own_plan.id}"
      assert html =~ "monitoring-alert-#{other_plan.id}"

      assert :binary.match(html, "monitoring-alert-#{own_plan.id}") <
               :binary.match(html, "monitoring-alert-#{other_plan.id}")
    end
  end
end
