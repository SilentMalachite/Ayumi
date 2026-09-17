defmodule AyumiWeb.ExportControllerTest do
  use AyumiWeb.ConnCase, async: false

  import Ayumi.PlansFixtures

  @bom "﻿"
  @params %{"dataset" => "attendance", "unit" => "month", "anchor_date" => "2026-06-15"}

  describe "GET /exports/download (unauthenticated)" do
    test "redirects to the log-in page", %{conn: conn} do
      conn = get(conn, ~p"/exports/download?#{@params}")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "GET /exports/download (supporter)" do
    setup :register_and_log_in_user

    test "downloads a BOM-prefixed CSV as an attachment", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎"})
      _ = attendance_record_fixture(%{service_user_id: su.id})

      conn = get(conn, ~p"/exports/download?#{@params}")

      assert @bom <> csv = response(conn, 200)
      assert csv =~ "利用者ID,氏名,利用日"
      assert csv =~ "山田 太郎,2026-06-01"

      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ URI.encode("出欠実績_2026年06月.csv", &URI.char_unreserved?/1)
    end

    test "downloads each recorded_at-based log", %{conn: conn} do
      _ = support_record_fixture(%{content: "午前の作業に集中できた"})
      today = Date.to_iso8601(Ayumi.JST.today())

      for {dataset, header} <- [
            {"support_records", "区分,内容"},
            {"goal_progress", "短期目標,進捗"},
            {"plan_phase_events", "段階,所見"}
          ] do
        params = %{"dataset" => dataset, "unit" => "week", "anchor_date" => today}
        conn = get(conn, ~p"/exports/download?#{params}")

        assert @bom <> csv = response(conn, 200)
        assert csv =~ header
      end

      params = %{"dataset" => "support_records", "unit" => "week", "anchor_date" => today}
      assert response(get(conn, ~p"/exports/download?#{params}"), 200) =~ "午前の作業に集中できた"
    end

    test "downloads the service user master without a period", %{conn: conn} do
      _ = service_user_fixture(%{name: "山田 太郎"})

      conn = get(conn, ~p"/exports/download?#{%{"dataset" => "service_users"}}")

      assert @bom <> csv = response(conn, 200)
      assert csv =~ "利用者ID,氏名,ふりがな"
      assert csv =~ "山田 太郎"
    end

    test "redirects back to the export page when the params are invalid", %{conn: conn} do
      conn = get(conn, ~p"/exports/download?#{%{@params | "unit" => "decade"}}")

      assert redirected_to(conn) == ~p"/exports"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "出力条件"
    end
  end
end
