defmodule Ayumi.Imports.SupportRecordsTest do
  use Ayumi.DataCase, async: false

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.Exports
  alias Ayumi.Imports
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans

  @headers CSV.SupportRecords.required_headers() ++ ["記録ID"]

  setup do
    manager = manager_fixture()
    %{manager: manager, scope: Scope.for_user(manager)}
  end

  defp row(service_user, date, overrides \\ %{}) do
    cells =
      Map.merge(
        %{
          "利用者ID" => Integer.to_string(service_user.id),
          "氏名" => service_user.name,
          "支援日" => date,
          "区分" => "作業",
          "内容" => "午前の作業に集中できた",
          "記録ID" => ""
        },
        overrides
      )

    Enum.map(@headers, &Map.fetch!(cells, &1))
  end

  defp csv(rows), do: CSV.encode(@headers, rows)

  defp all_records, do: Plans.list_support_records_between(~D[2000-01-01], ~D[2100-01-01])

  describe "authorization and file-level errors" do
    test "supporters may neither preview nor commit" do
      scope = user_scope_fixture()
      su = service_user_fixture()

      assert {:error, message} =
               Imports.preview_support_records(scope, csv([row(su, "2026-06-01")]))

      assert message =~ "サービス管理責任者"

      assert {:error, ^message} =
               Imports.commit_support_records(scope, %Preview{dataset: :support_records})
    end

    test "a hand-made file needs no 記録ID column, but needs 支援日", %{scope: scope} do
      su = service_user_fixture()
      headers = CSV.SupportRecords.required_headers()
      cells = [Integer.to_string(su.id), su.name, "2026-06-01", "作業", "手作りのファイル"]

      assert {:ok, %{errors: [], to_insert: [_]}} =
               Imports.preview_support_records(scope, CSV.encode(headers, [cells]))

      assert {:error, message} =
               Imports.preview_support_records(
                 scope,
                 CSV.encode(headers -- ["支援日"], [List.delete_at(cells, 2)])
               )

      assert message =~ "支援日"
    end
  end

  describe "preview_support_records/2" do
    test "plans new records without writing", %{scope: scope} do
      su = service_user_fixture()

      file =
        csv([
          row(su, "2026/6/1", %{"区分" => "面談", "内容" => "面談を実施。\r\n次回は来週。"}),
          row(su, "2026-06-01", %{"内容" => "同じ日の別の記録"})
        ])

      assert {:ok, preview} = Imports.preview_support_records(scope, file)

      assert preview.dataset == :support_records
      assert preview.errors == []

      assert [%{row: 2, kind: :new, attrs: first}, %{row: 3, kind: :new}] = preview.to_insert

      assert first == %{
               service_user_id: su.id,
               support_date: ~D[2026-06-01],
               category: :interview,
               content: "面談を実施。\n次回は来週。"
             }

      assert all_records() == []
    end

    test "an exported file re-imports as all unchanged (round trip)", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})

      _ =
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: ~D[2026-06-01],
          content: "- 特になし\n2行目"
        })

      _ = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-02]})

      {:ok, %{content: exported}} =
        Exports.build(scope, %{
          "dataset" => "support_records",
          "unit" => "month",
          "anchor_date" => "2026-06-15"
        })

      assert {:ok, preview} = Imports.preview_support_records(scope, exported)
      assert preview.errors == []
      assert preview.to_insert == []
      assert preview.unchanged == [2, 3]
      assert preview.warnings == []
      assert preview.ignored_headers == []
    end

    test "an edited exported row is a new record, with a warning that the original stays", %{
      scope: scope
    } do
      su = service_user_fixture()

      original =
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: ~D[2026-06-01],
          content: "元の内容"
        })

      edited =
        row(su, "2026-06-01", %{
          "内容" => "書き換えた内容",
          "記録ID" => Integer.to_string(original.id)
        })

      assert {:ok, preview} = Imports.preview_support_records(scope, csv([edited]))

      assert [%{row: 2, kind: :new, attrs: %{content: "書き換えた内容"}}] = preview.to_insert
      assert [%{row: 2, column: "記録ID", message: message}] = preview.warnings
      assert message =~ "#{original.id}"
      assert message =~ "元の記録は残"
    end

    test "trailing whitespace and line-ending differences do not make a row new", %{
      scope: scope
    } do
      su = service_user_fixture()

      _ =
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: ~D[2026-06-01],
          content: "1行目\n2行目"
        })

      file = csv([row(su, "2026-06-01", %{"内容" => "1行目\r\n2行目  "})])

      assert {:ok, %{to_insert: [], unchanged: [2]}} =
               Imports.preview_support_records(scope, file)
    end

    test "the same record twice in one file is an error", %{scope: scope} do
      su = service_user_fixture()

      file =
        csv([
          row(su, "2026-06-01"),
          row(su, "2026-06-01", %{"区分" => "健康"}),
          row(su, "2026/6/1")
        ])

      assert {:ok, preview} = Imports.preview_support_records(scope, file)
      assert [%{row: 4, column: "内容", message: message}] = preview.errors
      assert message =~ "2行目"
      assert Enum.map(preview.to_insert, & &1.row) == [2, 3]
    end

    test "reports cell errors, unknown service users, and future dates by row and column", %{
      scope: scope
    } do
      su = service_user_fixture()
      tomorrow = Ayumi.JST.today() |> Date.add(1) |> Date.to_iso8601()

      file =
        csv([
          row(su, "6月1日", %{"区分" => "その他いろいろ", "内容" => ""}),
          row(su, "2026-06-01", %{"利用者ID" => "999999"}),
          row(su, tomorrow)
        ])

      assert {:ok, preview} = Imports.preview_support_records(scope, file)

      assert [
               {2, "支援日", _},
               {2, "区分", _},
               {2, "内容", _},
               {3, "利用者ID", unknown},
               {4, "支援日", future}
             ] = Enum.map(preview.errors, &{&1.row, &1.column, &1.message})

      assert unknown =~ "999999"
      assert future == "未来の日付は指定できません"
      assert preview.to_insert == []
    end

    test "records for withdrawn service users are row errors (current rule)", %{scope: scope} do
      su = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})

      assert {:ok, preview} = Imports.preview_support_records(scope, csv([row(su, "2026-06-01")]))

      assert [%{row: 2, column: "利用者ID", message: "退所者には支援記録を作成できません"}] =
               preview.errors
    end

    test "resolves the service user by a unique name when the id is blank", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})
      cells = row(su, "2026-06-01", %{"利用者ID" => "", "氏名" => "山田　太郎"})

      assert {:ok, %{errors: [], to_insert: [%{attrs: %{service_user_id: id}}]}} =
               Imports.preview_support_records(scope, csv([cells]))

      assert id == su.id
    end
  end

  describe "commit_support_records/2" do
    test "appends the records with the support date, stamped with the importing manager", %{
      scope: scope,
      manager: manager
    } do
      su = service_user_fixture()
      _ = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-01]})

      file =
        csv([
          row(su, "2026-06-01"),
          row(su, "2026-05-20", %{"区分" => "面談", "内容" => "過去の面談"})
        ])

      {:ok, preview} = Imports.preview_support_records(scope, file)

      assert {:ok, %{inserted: 1, corrections: 0, unchanged: 1}} =
               Imports.commit_support_records(scope, preview)

      assert [imported, _existing] = all_records()
      assert imported.content == "過去の面談"
      assert imported.support_date == ~D[2026-05-20]
      assert imported.category == :interview
      assert imported.recorded_by_id == manager.id
      assert DateTime.diff(DateTime.utc_now(), imported.recorded_at) < 60
    end

    test "importing the same file twice adds nothing the second time", %{scope: scope} do
      su = service_user_fixture()
      file = csv([row(su, "2026-06-01"), row(su, "2026-06-02")])

      {:ok, first} = Imports.preview_support_records(scope, file)
      assert {:ok, %{inserted: 2}} = Imports.commit_support_records(scope, first)

      {:ok, second} = Imports.preview_support_records(scope, file)
      assert {:ok, %{inserted: 0, unchanged: 2}} = Imports.commit_support_records(scope, second)
      assert length(all_records()) == 2
    end

    test "refuses a preview that has errors", %{scope: scope} do
      su = service_user_fixture()
      file = csv([row(su, "2026-06-01"), row(su, "2026-06-02", %{"区分" => "不明"})])

      {:ok, preview} = Imports.preview_support_records(scope, file)

      assert {:error, message} = Imports.commit_support_records(scope, preview)
      assert message =~ "エラー"
      assert all_records() == []
    end

    test "returns a fresh preview when the same record was entered meanwhile", %{scope: scope} do
      su = service_user_fixture()
      {:ok, preview} = Imports.preview_support_records(scope, csv([row(su, "2026-06-01")]))

      _ = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-01]})

      assert {:error, :stale, fresh} = Imports.commit_support_records(scope, preview)
      assert fresh.to_insert == []
      assert fresh.unchanged == [2]
      assert length(all_records()) == 1
    end

    test "Imports.preview/3 and commit/2 dispatch on the dataset", %{scope: scope} do
      su = service_user_fixture()

      assert {:ok, %Preview{dataset: :support_records} = preview} =
               Imports.preview(scope, :support_records, csv([row(su, "2026-06-01")]))

      assert {:ok, %{inserted: 1}} = Imports.commit(scope, preview)
    end
  end
end
