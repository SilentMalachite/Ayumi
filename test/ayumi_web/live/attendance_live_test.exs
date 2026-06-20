defmodule AyumiWeb.AttendanceLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

  describe "GET /service_users/:id/attendance (general staff)" do
    test "renders the service user name and a row per day of the current month", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      today = Date.utc_today()
      days = Date.days_in_month(Date.new!(today.year, today.month, 1))

      {:ok, view, html} = live(conn, ~p"/service_users/#{su.id}/attendance")

      assert html =~ "山田 太郎"
      assert html =~ "#{today.year}"
      assert html =~ "#{today.month}"

      # one form per day, identified by `phx-submit="save_day"`
      rendered = render(view)
      submit_form_count =
        rendered
        |> String.split(~s|phx-submit="save_day"|)
        |> length()
        |> Kernel.-(1)

      assert submit_form_count == days
    end

    test "renders 28 rows for February 2026 when year/month is given", %{conn: conn} do
      su = service_user_fixture()
      {:ok, _view, html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 2]}")

      assert html =~ "2026"
      assert html =~ "2月"
      form_count =
        html |> String.split(~s|phx-submit="save_day"|) |> length() |> Kernel.-(1)

      assert form_count == 28
    end

    test "prev/next month links cross year boundaries", %{conn: conn} do
      su = service_user_fixture()

      # 2026-01 → prev → 2025-12
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 1]}")
      view |> element("a", "← 前月") |> render_click()
      assert render(view) =~ "2025"
      assert render(view) =~ "12月"

      # 2026-12 → next → 2027-01
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 12]}")
      view |> element("a", "翌月 →") |> render_click()
      assert render(view) =~ "2027"
      assert render(view) =~ "1月"
    end
  end
end
