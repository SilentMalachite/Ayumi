defmodule AyumiWeb.SupportRecordLiveTest do
  use AyumiWeb.ConnCase

  import Ecto.Query, only: [from: 2]
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

  describe "support date (支援日)" do
    test "the form defaults the support date to today in Japan", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/support_records")

      today = Date.to_iso8601(Ayumi.JST.today())
      assert has_element?(lv, ~s|#support-record-form input[type="date"][value="#{today}"]|)
    end

    test "a back-dated record is stored and listed under its support date", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎"})
      {:ok, lv, _html} = live(conn, ~p"/support_records")

      lv
      |> form("#support-record-form",
        support_record: %{
          service_user_id: su.id,
          category: "interview",
          content: "先月の面談",
          support_date: "2026-06-01"
        }
      )
      |> render_submit()

      assert render(lv) =~ "支援記録を保存しました"
      # The list starts on today's records, so the back-dated one is not shown yet.
      refute has_element?(lv, "#support-records td", "先月の面談")

      html =
        lv
        |> element("#support-record-filter")
        |> render_change(%{"service_user_id" => "", "from" => "2026-06-01", "to" => "2026-06-01"})

      assert html =~ "先月の面談"
      assert has_element?(lv, "#support-records td", "2026-06-01")
    end

    test "a future support date is rejected with a Japanese message", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/support_records")
      tomorrow = Ayumi.JST.today() |> Date.add(1) |> Date.to_iso8601()

      html =
        lv
        |> form("#support-record-form",
          support_record: %{
            service_user_id: su.id,
            category: "work",
            content: "明日の記録",
            support_date: tomorrow
          }
        )
        |> render_submit()

      assert html =~ "未来の日付は指定できません"
      refute html =~ "支援記録を保存しました"
    end

    test "the list shows the recording time in Japan time", %{conn: conn} do
      su = service_user_fixture()
      record = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-02]})

      # 2026-06-01 15:30 UTC is 2026-06-02 00:30 in Japan.
      Ayumi.Repo.update_all(
        from(r in Ayumi.Plans.SupportRecord, where: r.id == ^record.id),
        set: [recorded_at: ~U[2026-06-01 15:30:00Z]]
      )

      {:ok, lv, _html} = live(conn, ~p"/support_records")

      lv
      |> element("#support-record-filter")
      |> render_change(%{"service_user_id" => "", "from" => "2026-06-02", "to" => "2026-06-02"})

      assert has_element?(lv, "#support-records td", "2026-06-02 00:30")
      refute has_element?(lv, "#support-records td", "2026-06-01 15:30")
    end

    test "the service user page shows the support date", %{conn: conn} do
      su = service_user_fixture()

      _ =
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: ~D[2026-06-01],
          content: "まとめ画面の確認"
        })

      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}")

      assert has_element?(lv, "#recent-support-records td", "2026-06-01")
    end
  end
end
