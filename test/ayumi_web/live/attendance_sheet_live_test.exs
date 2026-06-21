defmodule AyumiWeb.AttendanceSheetLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

  describe "GET /service_users/:id/attendance/sheet (general staff)" do
    test "renders the service user name and a row per day of the given month", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "山田 太郎"
      assert html =~ "2026"
      assert html =~ "6月"

      # 6月は30日 — 明細テーブルの行数 (data-day 属性を付与してカウント)
      row_count =
        html |> String.split(~s|data-day=|) |> length() |> Kernel.-(1)

      assert row_count == 30
    end
  end
end
