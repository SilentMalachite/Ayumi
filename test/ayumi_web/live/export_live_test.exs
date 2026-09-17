defmodule AyumiWeb.ExportLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  describe "unauthenticated" do
    test "redirects to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/exports")
    end
  end

  describe "supporter" do
    setup :register_and_log_in_user

    test "renders the form with this month's attendance preselected", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/exports")

      assert html =~ "CSV出力"
      assert html =~ "出欠・実績記録"
      assert has_element?(lv, "#export-form")
      assert has_element?(lv, ~s|#export-download[href^="/exports/download?"]|)
      assert has_element?(lv, ~s|#export-download[href*="unit=month"]|)
    end

    test "changing the form updates the period and the download link", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎"})
      {:ok, lv, _html} = live(conn, ~p"/exports")

      html =
        lv
        |> form("#export-form", %{
          "export" => %{
            "unit" => "fiscal_year",
            "anchor_date" => "2027-02-01",
            "service_user_id" => Integer.to_string(su.id)
          }
        })
        |> render_change()

      assert html =~ "2026年度（2026-04-01 〜 2027-03-31）"
      assert has_element?(lv, ~s|#export-download[href*="unit=fiscal_year"]|)
      assert has_element?(lv, ~s|#export-download[href*="anchor_date=2027-02-01"]|)
      assert has_element?(lv, ~s|#export-download[href*="service_user_id=#{su.id}"]|)
    end

    test "offers every dataset and links to the chosen one", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/exports")

      for label <- ["出欠・実績記録", "支援記録", "目標進捗の履歴", "計画段階の履歴"] do
        assert html =~ label
      end

      lv
      |> form("#export-form", %{"export" => %{"dataset" => "support_records"}})
      |> render_change()

      assert has_element?(lv, ~s|#export-download[href*="dataset=support_records"]|)
    end

    test "the service user master hides the period inputs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/exports")

      assert has_element?(lv, "#export_unit")
      assert has_element?(lv, "#export_anchor_date")

      html =
        lv
        |> form("#export-form", %{"export" => %{"dataset" => "service_users"}})
        |> render_change()

      assert html =~ "利用者台帳"
      refute has_element?(lv, "#export_unit")
      refute has_element?(lv, "#export_anchor_date")
      refute has_element?(lv, "#export_service_user_id")
      refute has_element?(lv, "#export-period")

      assert has_element?(
               lv,
               ~s|#export-download[href="/exports/download?dataset=service_users"]|
             )
    end

    test "lists withdrawn service users too", %{conn: conn} do
      _ = service_user_fixture(%{name: "退所した人", enrollment_status: :withdrawn})

      {:ok, _lv, html} = live(conn, ~p"/exports")

      assert html =~ "退所した人"
    end

    test "hides the download link while the form is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/exports")

      html =
        lv
        |> form("#export-form", %{"export" => %{"anchor_date" => ""}})
        |> render_change()

      refute has_element?(lv, "#export-download")
      assert html =~ "を指定してください"
    end

    test "the nav links to the export page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, ~s|header a[href="/exports"]|)
    end
  end
end
