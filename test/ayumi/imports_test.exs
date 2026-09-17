defmodule Ayumi.ImportsTest do
  use Ayumi.DataCase, async: false

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.Exports
  alias Ayumi.Imports
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans

  @headers CSV.Attendance.required_headers()

  setup do
    manager = manager_fixture()
    %{manager: manager, scope: Scope.for_user(manager)}
  end

  # A row in @headers order: 利用者ID 氏名 利用日 提供形態 開始 終了 送迎(往) 送迎(復) 備考
  defp row(service_user, date, overrides \\ %{}) do
    cells =
      Map.merge(
        %{
          "利用者ID" => Integer.to_string(service_user.id),
          "氏名" => service_user.name,
          "利用日" => date,
          "提供形態" => "通所",
          "開始" => "09:00",
          "終了" => "15:00",
          "送迎(往)" => "",
          "送迎(復)" => "",
          "備考" => ""
        },
        overrides
      )

    Enum.map(@headers, &Map.fetch!(cells, &1))
  end

  defp csv(rows), do: CSV.encode(@headers, rows)

  defp messages(%Preview{errors: errors}) do
    Enum.map(errors, &{&1.row, &1.column, &1.message})
  end

  describe "authorization" do
    test "supporters may neither preview nor commit" do
      scope = user_scope_fixture()
      su = service_user_fixture()

      assert {:error, message} = Imports.preview_attendance(scope, csv([row(su, "2026-09-01")]))
      assert message =~ "サービス管理責任者"

      assert {:error, ^message} =
               Imports.commit_attendance(scope, %Preview{dataset: :attendance})
    end
  end

  describe "preview_attendance/2 — file-level errors" do
    test "rejects Shift_JIS with advice on how to save from Excel", %{scope: scope} do
      assert {:error, message} = Imports.preview_attendance(scope, <<0x8E, 0x81, 0x96, 0xBC>>)
      assert message =~ "CSV UTF-8"
    end

    test "rejects a file missing a column the import reads", %{scope: scope} do
      su = service_user_fixture()
      headers = @headers -- ["備考", "終了"]
      rows = [[Integer.to_string(su.id), su.name, "2026-09-01", "通所", "09:00", "", ""]]

      assert {:error, message} = Imports.preview_attendance(scope, CSV.encode(headers, rows))
      assert message =~ "終了"
      assert message =~ "備考"
    end

    test "rejects files over the size limit", %{scope: scope} do
      too_big = String.duplicate("a", Imports.max_bytes() + 1)

      assert {:error, message} = Imports.preview_attendance(scope, too_big)
      assert message =~ "大きすぎ"
    end

    test "rejects files over the row limit", %{scope: scope} do
      su = service_user_fixture()
      rows = List.duplicate(row(su, "2026-09-01"), Imports.max_rows() + 1)

      assert {:error, message} = Imports.preview_attendance(scope, csv(rows))
      assert message =~ "#{Imports.max_rows()}"
    end
  end

  describe "preview_attendance/2 — planning" do
    test "new dates are additions; nothing is written yet", %{scope: scope} do
      su = service_user_fixture()

      assert {:ok, preview} =
               Imports.preview_attendance(
                 scope,
                 csv([row(su, "2026-09-01"), row(su, "2026-09-02", %{"送迎(往)" => "○"})])
               )

      assert preview.errors == []
      assert preview.total_rows == 2

      assert [%{row: 2, kind: :new, attrs: first}, %{row: 3, kind: :new, attrs: second}] =
               preview.to_insert

      assert first.service_user_id == su.id
      assert first.service_date == ~D[2026-09-01]
      assert second.pickup == true
      assert %{new: 2, corrections: 0, unchanged: 0, errors: 0} = Preview.counts(preview)

      assert Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-30]) == []
    end

    test "an exported file re-imports as all unchanged (round trip)", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          start_time: ~T[09:00:00],
          end_time: ~T[15:30:00],
          pickup: true,
          note: "- 特になし"
        })

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-06-02],
          provision_type: :absence
        })

      {:ok, %{content: exported}} =
        Exports.build(scope, %{
          "dataset" => "attendance",
          "unit" => "month",
          "anchor_date" => "2026-06-15"
        })

      assert {:ok, preview} = Imports.preview_attendance(scope, exported)
      assert preview.errors == []
      assert preview.to_insert == []
      assert preview.unchanged == [2, 3]
      assert preview.ignored_headers == []
    end

    test "an edited cell is a correction against the latest row", %{scope: scope} do
      su = service_user_fixture()
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-01]})

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          start_time: ~T[09:00:00],
          end_time: ~T[15:00:00]
        })

      same = row(su, "2026-06-01")
      edited = row(su, "2026-06-01", %{"終了" => "16:00"})

      assert {:ok, %{to_insert: [], unchanged: [2]}} =
               Imports.preview_attendance(scope, csv([same]))

      assert {:ok, preview} = Imports.preview_attendance(scope, csv([edited]))
      assert [%{row: 2, kind: :correction, attrs: %{end_time: ~T[16:00:00]}}] = preview.to_insert
      assert %{new: 0, corrections: 1, unchanged: 0, errors: 0} = Preview.counts(preview)
    end

    test "a blank note equals a missing note, and trailing whitespace is ignored", %{
      scope: scope
    } do
      su = service_user_fixture()

      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          start_time: ~T[09:00:00],
          end_time: ~T[15:00:00],
          note: "良好"
        })

      assert {:ok, %{unchanged: [2]}} =
               Imports.preview_attendance(scope, csv([row(su, "2026-06-01", %{"備考" => "良好 "})]))
    end

    test "accepts the variants Excel produces", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})

      # No BOM, LF line endings, slash dates, H:MM times, full-width header
      # parentheses, an extra unknown column, and trailing empty columns.
      mangled =
        "利用者ID,氏名,利用日,曜,提供形態,開始,終了,送迎（往）,送迎（復）,備考,メモ,,\n" <>
          "#{su.id},山田 太郎,2026/9/1,火,通所,9:00,15:30,○,,良好,自由記入,,\n" <>
          ",,,,,,,,,,,,\n"

      assert {:ok, preview} = Imports.preview_attendance(scope, mangled)
      assert preview.errors == []
      assert preview.ignored_headers == ["メモ"]

      assert [%{row: 2, kind: :new, attrs: attrs}] = preview.to_insert
      assert attrs.service_date == ~D[2026-09-01]
      assert {attrs.start_time, attrs.end_time} == {~T[09:00:00], ~T[15:30:00]}
      assert {attrs.pickup, attrs.dropoff, attrs.note} == {true, false, "良好"}
    end

    test "withdrawn service users can still be imported", %{scope: scope} do
      su = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})

      assert {:ok, %{errors: [], to_insert: [_]}} =
               Imports.preview_attendance(scope, csv([row(su, "2026-09-01")]))
    end
  end

  describe "preview_attendance/2 — resolving the service user" do
    test "by name alone when the id is blank and the name is unique", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})

      # Full-width space instead of the registered half-width one.
      cells = row(su, "2026-09-01", %{"利用者ID" => "", "氏名" => "山田　太郎"})

      assert {:ok, %{errors: [], to_insert: [%{attrs: %{service_user_id: id}}]}} =
               Imports.preview_attendance(scope, csv([cells]))

      assert id == su.id
    end

    test "reports unknown, mismatched, ambiguous, and missing service users", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})
      _twin_a = service_user_fixture(%{name: "同姓 同名"})
      twin_b = service_user_fixture(%{name: "同姓 同名"})

      rows = [
        row(su, "2026-09-01", %{"利用者ID" => "999999"}),
        row(su, "2026-09-02", %{"氏名" => "別人"}),
        row(twin_b, "2026-09-03", %{"利用者ID" => ""}),
        row(su, "2026-09-04", %{"利用者ID" => "", "氏名" => "いない人"}),
        row(su, "2026-09-05", %{"利用者ID" => "", "氏名" => ""}),
        # The id disambiguates people who share a name.
        row(twin_b, "2026-09-06")
      ]

      assert {:ok, preview} = Imports.preview_attendance(scope, csv(rows))

      assert [
               {2, "利用者ID", unknown},
               {3, "氏名", mismatch},
               {4, "氏名", ambiguous},
               {5, "氏名", not_found},
               {6, "利用者ID", blank}
             ] = messages(preview)

      assert unknown =~ "999999"
      assert mismatch =~ "山田 太郎"
      assert ambiguous =~ "複数"
      assert not_found =~ "見つかりません"
      assert blank =~ "利用者ID か氏名"

      assert [%{row: 7}] = preview.to_insert
    end
  end

  describe "preview_attendance/2 — row errors" do
    test "reports unreadable cells with the Excel row number and column", %{scope: scope} do
      su = service_user_fixture()

      rows = [
        row(su, "2026-09-01"),
        row(su, "9月2日", %{"提供形態" => "出席"}),
        row(su, "2026-09-03", %{"開始" => "15:00", "終了" => "09:00"})
      ]

      assert {:ok, preview} = Imports.preview_attendance(scope, csv(rows))

      assert [{3, "利用日", date}, {3, "提供形態", enum}, {4, "終了", order}] = messages(preview)
      assert date =~ "日付"
      assert enum =~ "通所"
      assert order =~ "開始時刻より後"

      # Valid rows are still planned so the preview is informative.
      assert [%{row: 2}] = preview.to_insert
      assert Preview.counts(preview).errors == 3
    end

    test "the same service user and date twice in one file is an error, not last-wins", %{
      scope: scope
    } do
      su = service_user_fixture()
      rows = [row(su, "2026-09-01"), row(su, "2026-09-02"), row(su, "2026/9/1", %{"備考" => "後"})]

      assert {:ok, preview} = Imports.preview_attendance(scope, csv(rows))
      assert [{4, "利用日", message}] = messages(preview)
      assert message =~ "2行目"
      assert Enum.map(preview.to_insert, & &1.row) == [2, 3]
    end
  end

  describe "commit_attendance/2" do
    test "appends the planned rows, stamped with the importing manager", %{
      scope: scope,
      manager: manager
    } do
      su = service_user_fixture()
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-09-01]})

      rows = [
        row(su, "2026-09-01", %{"提供形態" => "欠席", "開始" => "", "終了" => "", "備考" => "訂正"}),
        row(su, "2026-09-02")
      ]

      {:ok, preview} = Imports.preview_attendance(scope, csv(rows))

      assert {:ok, %{inserted: 2, corrections: 1, unchanged: 0}} =
               Imports.commit_attendance(scope, preview)

      records = Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-02])

      # Append-only: the original row is still there, plus the two imported rows.
      assert length(records) == 3
      latest = Plans.latest_attendance_by_user_date(records)
      assert latest[{su.id, ~D[2026-09-01]}].provision_type == :absence
      assert latest[{su.id, ~D[2026-09-01]}].note == "訂正"
      assert latest[{su.id, ~D[2026-09-01]}].recorded_by_id == manager.id
      assert latest[{su.id, ~D[2026-09-02]}].recorded_by_id == manager.id
    end

    test "importing the same file twice adds nothing the second time", %{scope: scope} do
      su = service_user_fixture()
      file = csv([row(su, "2026-09-01"), row(su, "2026-09-02")])

      {:ok, first} = Imports.preview_attendance(scope, file)
      assert {:ok, %{inserted: 2}} = Imports.commit_attendance(scope, first)

      {:ok, second} = Imports.preview_attendance(scope, file)

      assert {:ok, %{inserted: 0, corrections: 0, unchanged: 2}} =
               Imports.commit_attendance(scope, second)

      assert length(Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-02])) == 2
    end

    test "refuses a preview that has errors; nothing is written", %{scope: scope} do
      su = service_user_fixture()
      file = csv([row(su, "2026-09-01"), row(su, "2026-09-02", %{"提供形態" => "出席"})])

      {:ok, preview} = Imports.preview_attendance(scope, file)

      assert {:error, message} = Imports.commit_attendance(scope, preview)
      assert message =~ "エラー"
      assert Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-02]) == []
    end

    test "returns a fresh preview when the data changed after the preview", %{scope: scope} do
      su = service_user_fixture()
      {:ok, preview} = Imports.preview_attendance(scope, csv([row(su, "2026-09-01")]))
      assert [%{kind: :new}] = preview.to_insert

      # Meanwhile another staff member records the same day on the grid.
      _ =
        attendance_record_fixture(%{
          service_user_id: su.id,
          service_date: ~D[2026-09-01],
          provision_type: :absence
        })

      assert {:error, :stale, fresh} = Imports.commit_attendance(scope, preview)
      assert [%{kind: :correction}] = fresh.to_insert

      # Nothing was imported; only the other staff member's row exists.
      assert [_only] = Plans.list_attendance_records_between(~D[2026-09-01], ~D[2026-09-01])

      # Confirming the fresh preview goes through.
      assert {:ok, %{inserted: 1, corrections: 1}} = Imports.commit_attendance(scope, fresh)
    end
  end
end
