defmodule AyumiWeb.ImportLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  alias Ayumi.CSV
  alias Ayumi.Plans

  @headers CSV.Attendance.required_headers()

  # A row in @headers order: 利用者ID 氏名 利用日 提供形態 開始 終了 送迎(往) 送迎(復) 備考
  defp row(service_user, date, provision \\ "通所") do
    [Integer.to_string(service_user.id), service_user.name, date, provision, "09:00", "15:00"] ++
      ["", "", ""]
  end

  defp csv(rows), do: CSV.encode(@headers, rows)

  defp upload_and_preview(lv, content) do
    lv
    |> file_input("#import-form", :csv, [
      %{name: "attendance.csv", content: content, type: "text/csv"}
    ])
    |> render_upload("attendance.csv")

    lv |> form("#import-form") |> render_submit()
  end

  describe "access" do
    test "unauthenticated visitors are sent to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/import")
    end

    test "supporters are redirected and see no nav link", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/import")

      {:ok, lv, _html} = live(conn, ~p"/")
      refute has_element?(lv, ~s|header a[href="/admin/import"]|)
    end

    test "managers see the page and the nav link", %{conn: conn} do
      %{conn: conn} = register_and_log_in_manager(%{conn: conn})

      {:ok, lv, html} = live(conn, ~p"/admin/import")

      assert html =~ "CSV取込"
      assert html =~ "CSV UTF-8"
      assert html =~ "削除されません"
      assert has_element?(lv, "#import-form")
      assert has_element?(lv, ~s|header a[href="/admin/import"]|)
      refute has_element?(lv, "#import-preview")
    end
  end

  describe "importing attendance" do
    setup :register_and_log_in_manager

    test "upload → preview → commit appends the rows", %{conn: conn, user: manager} do
      su = service_user_fixture(%{name: "山田 太郎"})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-09-01]})
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      html =
        upload_and_preview(
          lv,
          csv([row(su, "2026-09-01", "欠席"), row(su, "2026-09-02"), row(su, "2026-09-03")])
        )

      assert has_element?(lv, "#import-preview")
      assert html =~ "追加 3 件"
      assert html =~ "うち訂正 1 件"
      assert html =~ "変更なし 0 件"

      # Nothing is written until the manager confirms.
      assert length(Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-30])) == 1

      html = lv |> element("#import-commit") |> render_click()

      assert html =~ "取込が完了しました"
      assert has_element?(lv, "#import-result")
      refute has_element?(lv, "#import-preview")

      records = Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-30])
      assert length(records) == 4

      latest = Plans.latest_attendance_by_user_date(records)
      assert latest[{su.id, ~D[2026-09-01]}].provision_type == :absence
      assert latest[{su.id, ~D[2026-09-01]}].recorded_by_id == manager.id
    end

    test "row errors are listed with row and column, and block the commit", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      html = upload_and_preview(lv, csv([row(su, "2026-09-01"), row(su, "9月2日", "出席")]))

      assert html =~ "エラー 2 件"
      assert has_element?(lv, "#import-errors tr", "3")
      assert has_element?(lv, "#import-errors tr", "利用日")
      assert has_element?(lv, "#import-errors tr", "提供形態")
      refute has_element?(lv, "#import-commit")
      assert Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-30]) == []
    end

    test "a file that cannot be used at all shows one message", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      # "氏名" in Shift_JIS, as Excel's plain "CSV" format writes it.
      html = upload_and_preview(lv, <<0x8E, 0x81, 0x96, 0xBC, ?\r, ?\n>>)

      assert has_element?(lv, "#import-file-error")
      assert html =~ "CSV UTF-8"
      refute has_element?(lv, "#import-preview")
    end

    test "submitting without a file asks for one", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      html = lv |> form("#import-form") |> render_submit()

      assert html =~ "ファイルを選択してください"
    end

    test "an unchanged file offers nothing to commit", %{conn: conn} do
      su = service_user_fixture()

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-09-01],
          start_time: ~T[09:00:00],
          end_time: ~T[15:00:00]
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      html = upload_and_preview(lv, csv([row(su, "2026-09-01")]))

      assert html =~ "変更なし 1 件"
      assert html =~ "取り込む変更はありません"
      refute has_element?(lv, "#import-commit")
    end

    test "unknown columns are reported as ignored", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      content = CSV.encode(@headers ++ ["メモ"], [row(su, "2026-09-01") ++ ["自由記入"]])

      assert upload_and_preview(lv, content) =~ "メモ"
    end

    test "when the data changed after the preview, the manager confirms again", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = upload_and_preview(lv, csv([row(su, "2026-09-01")]))

      # Meanwhile another staff member records the same day on the grid.
      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-09-01],
          provision_type: :absence
        })

      html = lv |> element("#import-commit") |> render_click()

      assert has_element?(lv, "#import-stale")
      assert html =~ "うち訂正 1 件"
      assert length(Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-01])) == 1

      html = lv |> element("#import-commit") |> render_click()

      assert html =~ "取込が完了しました"
      assert length(Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-01])) == 2
    end

    test "cancel discards the preview", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = upload_and_preview(lv, csv([row(su, "2026-09-01")]))

      lv |> element("#import-cancel") |> render_click()

      refute has_element?(lv, "#import-preview")
      assert Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-01]) == []
    end
  end

  describe "importing the service user master" do
    setup :register_and_log_in_manager

    @master_headers CSV.ServiceUsers.required_headers()

    defp master_csv(rows) do
      CSV.encode(
        @master_headers,
        Enum.map(rows, fn cells ->
          Enum.map(@master_headers, &Map.get(cells, &1, ""))
        end)
      )
    end

    defp choose_master(lv) do
      lv |> form("#import-form", %{"dataset" => "service_users"}) |> render_change()
    end

    test "choosing the master shows its own rules", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/import")
      assert html =~ "訂正として追記"

      html = choose_master(lv)

      assert html =~ "新しい利用者だけを追加"
      assert html =~ "障害者手帳"
      refute html =~ "訂正として追記"
    end

    test "upload → preview → commit adds only new people", %{conn: conn} do
      existing = service_user_fixture(%{name: "既存 花子", birthdate: ~D[1980-01-01]})
      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = choose_master(lv)

      html =
        upload_and_preview(
          lv,
          master_csv([
            %{"氏名" => "既存 花子", "生年月日" => "1980/1/1"},
            %{"氏名" => "新人 一郎", "受給者証番号" => "123456789"},
            %{"氏名" => "新人 二郎", "在籍状態" => "体験利用"}
          ])
        )

      assert html =~ "追加 2 件"
      assert html =~ "既存 1 件"
      assert has_element?(lv, "#import-skipped tr", "ID #{existing.id}")
      assert has_element?(lv, "#import-warnings tr", "10 桁")
      assert length(Plans.list_service_users()) == 1

      html = lv |> element("#import-commit") |> render_click()

      assert html =~ "取込が完了しました"
      assert html =~ "既存 1 件"

      names = Plans.list_service_users() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == Enum.sort(["既存 花子", "新人 一郎", "新人 二郎"])
    end

    test "an attendance file chosen by mistake is rejected as a whole", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = choose_master(lv)

      html = upload_and_preview(lv, csv([row(su, "2026-09-01")]))

      assert has_element?(lv, "#import-file-error")
      assert html =~ "必要な列がありません"
    end

    test "switching the dataset discards a pending preview", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = upload_and_preview(lv, csv([row(su, "2026-09-01")]))
      assert has_element?(lv, "#import-preview")

      _ = choose_master(lv)

      refute has_element?(lv, "#import-preview")
    end
  end

  describe "importing support records" do
    setup :register_and_log_in_manager

    @record_headers CSV.SupportRecords.required_headers()

    defp record_row(service_user, date, content) do
      [Integer.to_string(service_user.id), service_user.name, date, "面談", content]
    end

    test "choosing support records shows their own rules", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/import")

      html = lv |> form("#import-form", %{"dataset" => "support_records"}) |> render_change()

      assert html =~ "新しい記録として追加"
      assert html =~ "支援日"
      refute html =~ "訂正として追記"
    end

    test "upload → preview → commit adds past records under their support date", %{conn: conn} do
      su = service_user_fixture()

      _ =
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: ~D[2026-06-01],
          content: "既にある記録",
          category: :interview
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/import")
      _ = lv |> form("#import-form", %{"dataset" => "support_records"}) |> render_change()

      html =
        upload_and_preview(
          lv,
          CSV.encode(@record_headers, [
            record_row(su, "2026-06-01", "既にある記録"),
            record_row(su, "2026/5/20", "Excel にあった過去の面談")
          ])
        )

      assert html =~ "追加 1 件"
      assert html =~ "変更なし 1 件"

      html = lv |> element("#import-commit") |> render_click()
      assert html =~ "取込が完了しました"

      assert [imported] = Plans.list_support_records_between(~D[2026-05-20], ~D[2026-05-20])
      assert imported.content == "Excel にあった過去の面談"
    end
  end
end
