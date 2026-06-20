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
  end
end
