defmodule AyumiWeb.SupportRecordLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_manager

  describe "support record creation via LiveView" do
    test "LiveView フォーム（文字列キー）から支援記録を作成できる", %{conn: conn} do
      su = service_user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/support_records")

      lv
      |> form("#support-record-form",
        support_record: %{service_user_id: su.id, category: "work", content: "テスト支援内容"}
      )
      |> render_submit()

      assert render(lv) =~ "支援記録を保存しました"
      assert render(lv) =~ "テスト支援内容"
    end

    test "クライアント由来の監査フィールドは無視される", %{conn: conn, user: user} do
      su = service_user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/support_records")

      render_submit(lv, "create", %{
        "support_record" => %{
          "service_user_id" => to_string(su.id),
          "category" => "work",
          "content" => "改ざんテスト",
          "recorded_by_id" => "99999",
          "recorded_at" => "2000-01-01T00:00:00Z"
        }
      })

      [record] =
        Ayumi.Plans.list_support_records(%Ayumi.Accounts.Scope{user: user})

      assert record.recorded_by_id == user.id
      assert record.recorded_at != ~U[2000-01-01 00:00:00Z]
    end
  end
end
