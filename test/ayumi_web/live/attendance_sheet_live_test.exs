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

    test "renders recipient cert number and municipality when present", %{conn: conn} do
      su = service_user_fixture(%{
        recipient_cert_number: "1234567890",
        recipient_cert_municipality: "渋谷区"
      })

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "1234567890"
      assert html =~ "渋谷区"
    end

    test "renders without crashing when :ayumi, :facility is unset", %{conn: conn} do
      Application.delete_env(:ayumi, :facility)
      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      # ヘッダのラベルは出る (値は空)
      assert html =~ "事業所名"
      assert html =~ "事業所番号"
    end

    test "renders facility name and number when :ayumi, :facility is set", %{conn: conn} do
      Application.put_env(:ayumi, :facility, name: "歩みワークス", number: "1311234567")
      on_exit(fn -> Application.delete_env(:ayumi, :facility) end)

      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "歩みワークス"
      assert html =~ "1311234567"
    end
  end
end
