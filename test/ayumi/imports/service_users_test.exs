defmodule Ayumi.Imports.ServiceUsersTest do
  use Ayumi.DataCase, async: false

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.Exports
  alias Ayumi.Imports
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans

  @headers CSV.ServiceUsers.required_headers()

  setup do
    %{scope: Scope.for_user(manager_fixture())}
  end

  defp row(cells) do
    Enum.map(@headers, &Map.get(cells, &1, ""))
  end

  defp csv(rows), do: CSV.encode(@headers, Enum.map(rows, &row/1))

  defp names, do: Plans.list_service_users(include_withdrawn: true) |> Enum.map(& &1.name)

  describe "authorization and file-level errors" do
    test "supporters may neither preview nor commit" do
      scope = user_scope_fixture()

      assert {:error, message} = Imports.preview_service_users(scope, csv([%{"氏名" => "新人"}]))
      assert message =~ "サービス管理責任者"

      assert {:error, ^message} =
               Imports.commit_service_users(scope, %Preview{dataset: :service_users})
    end

    test "rejects a file missing a column the import reads", %{scope: scope} do
      assert {:error, message} =
               Imports.preview_service_users(scope, CSV.encode(["氏名"], [["新人"]]))

      assert message =~ "必要な列がありません"
      assert message =~ "生年月日"
    end
  end

  describe "preview_service_users/2" do
    test "plans new service users without writing; blank cells are left out", %{scope: scope} do
      file =
        csv([
          %{"氏名" => "新人 一郎", "ふりがな" => "しんじん いちろう", "生年月日" => "1990/4/1", "性別" => "男性"},
          %{"氏名" => "名前だけ"}
        ])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)

      assert preview.dataset == :service_users
      assert preview.errors == []

      assert [%{row: 2, kind: :new, attrs: first}, %{row: 3, kind: :new, attrs: second}] =
               preview.to_insert

      assert first == %{
               name: "新人 一郎",
               name_kana: "しんじん いちろう",
               birthdate: ~D[1990-04-01],
               gender: :male
             }

      # No :id, and no nil for enrollment_status that would override its default.
      assert second == %{name: "名前だけ"}
      assert %{new: 2, skipped: 0, errors: 0, warnings: 0} = Preview.counts(preview)
      assert names() == []
    end

    test "an existing 利用者ID is skipped; an unknown one is an error", %{scope: scope} do
      su = service_user_fixture(%{name: "山田 太郎"})

      file =
        csv([
          %{"利用者ID" => Integer.to_string(su.id), "氏名" => "山田 太郎"},
          %{"利用者ID" => "999999", "氏名" => "謎の人"}
        ])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)
      assert preview.to_insert == []
      assert [%{row: 2, reason: reason}] = preview.skipped
      assert reason =~ "山田 太郎"
      assert [%{row: 3, column: "利用者ID", message: message}] = preview.errors
      assert message =~ "999999"
    end

    test "the same 受給者証番号 is skipped even when Excel dropped its leading zero", %{
      scope: scope
    } do
      su = service_user_fixture(%{name: "山田 太郎", recipient_cert_number: "0123456789"})

      file = csv([%{"氏名" => "やまだ", "受給者証番号" => "123456789"}])

      assert {:ok, %{to_insert: [], skipped: [%{row: 2, reason: reason}]}} =
               Imports.preview_service_users(scope, file)

      assert reason =~ "受給者証番号"
      assert reason =~ "#{su.id}"
    end

    test "the same name and birthdate is skipped, ignoring width and spacing", %{scope: scope} do
      _ = service_user_fixture(%{name: "山田 太郎", birthdate: ~D[1990-04-01]})

      file =
        csv([
          %{"氏名" => "山田　太郎", "生年月日" => "1990-04-01"},
          # Same name, different birthdate: a different person.
          %{"氏名" => "山田 太郎", "生年月日" => "1985-01-01"}
        ])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)
      assert [%{row: 2, reason: reason}] = preview.skipped
      assert reason =~ "生年月日"
      assert [%{row: 3}] = preview.to_insert
      assert preview.warnings == []
    end

    test "a same-name row that cannot be checked by birthdate is added with a warning", %{
      scope: scope
    } do
      su = service_user_fixture(%{name: "山田 太郎"})

      assert {:ok, preview} = Imports.preview_service_users(scope, csv([%{"氏名" => "山田 太郎"}]))

      assert [%{row: 2}] = preview.to_insert
      assert [%{row: 2, column: "氏名", message: message}] = preview.warnings
      assert message =~ "#{su.id}"
      assert message =~ "生年月日"
    end

    test "a 受給者証番号 that is not 10 digits is added with a warning", %{scope: scope} do
      file = csv([%{"氏名" => "新人", "受給者証番号" => "123456789"}])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)
      assert [%{row: 2}] = preview.to_insert
      assert [%{row: 2, column: "受給者証番号", message: message}] = preview.warnings
      assert message =~ "10 桁"
    end

    test "the same person twice in one file is an error", %{scope: scope} do
      file =
        csv([
          %{"氏名" => "新人 一郎", "生年月日" => "1990-04-01"},
          %{"氏名" => "別人", "受給者証番号" => "1111111111"},
          %{"氏名" => "新人一郎", "生年月日" => "1990/4/1"},
          %{"氏名" => "別名", "受給者証番号" => "1111111111"}
        ])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)

      assert [
               %{row: 4, column: "氏名", message: by_name},
               %{row: 5, column: "受給者証番号", message: by_cert}
             ] = preview.errors

      assert by_name =~ "2行目"
      assert by_cert =~ "3行目"
      assert Enum.map(preview.to_insert, & &1.row) == [2, 3]
    end

    test "reports unreadable cells by row and column", %{scope: scope} do
      file = csv([%{"氏名" => "", "性別" => "男"}, %{"氏名" => "新人", "生年月日" => "平成2年"}])

      assert {:ok, preview} = Imports.preview_service_users(scope, file)

      assert Enum.map(preview.errors, &{&1.row, &1.column}) ==
               [{2, "氏名"}, {2, "性別"}, {3, "生年月日"}]
    end

    test "an exported master re-imports as all existing (round trip)", %{scope: scope} do
      _ = service_user_fixture(%{name: "佐藤", recipient_cert_number: "0123456789"})
      _ = service_user_with_certificate_fixture()
      _ = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})

      {:ok, %{content: exported}} = Exports.build(scope, %{"dataset" => "service_users"})

      assert {:ok, preview} = Imports.preview_service_users(scope, exported)
      assert preview.errors == []
      assert preview.to_insert == []
      assert length(preview.skipped) == 3
      # 障害者手帳 is a known export-only column, not an unknown one.
      assert preview.ignored_headers == []
    end
  end

  describe "commit_service_users/2" do
    test "creates the planned service users with the schema defaults", %{scope: scope} do
      _ = service_user_fixture(%{name: "既存", birthdate: ~D[1980-01-01]})

      file =
        csv([
          %{"氏名" => "既存", "生年月日" => "1980-01-01"},
          %{"氏名" => "新人 一郎", "在籍状態" => "体験利用", "受給者証番号" => "0123456789"},
          %{"氏名" => "新人 二郎"}
        ])

      {:ok, preview} = Imports.preview_service_users(scope, file)

      assert {:ok, %{inserted: 2, skipped: 1}} = Imports.commit_service_users(scope, preview)

      users = Plans.list_service_users(include_withdrawn: true)
      assert length(users) == 3

      ichiro = Enum.find(users, &(&1.name == "新人 一郎"))
      assert ichiro.enrollment_status == :trial
      assert ichiro.recipient_cert_number == "0123456789"
      assert Enum.find(users, &(&1.name == "新人 二郎")).enrollment_status == :enrolled
    end

    test "importing the same file twice adds nobody the second time", %{scope: scope} do
      file = csv([%{"氏名" => "新人 一郎", "生年月日" => "1990-04-01"}])

      {:ok, first} = Imports.preview_service_users(scope, file)
      assert {:ok, %{inserted: 1}} = Imports.commit_service_users(scope, first)

      {:ok, second} = Imports.preview_service_users(scope, file)
      assert {:ok, %{inserted: 0, skipped: 1}} = Imports.commit_service_users(scope, second)
      assert names() == ["新人 一郎"]
    end

    test "refuses a preview that has errors", %{scope: scope} do
      {:ok, preview} =
        Imports.preview_service_users(
          scope,
          csv([%{"氏名" => "新人"}, %{"氏名" => "", "性別" => "男性"}])
        )

      assert {:error, message} = Imports.commit_service_users(scope, preview)
      assert message =~ "エラー"
      assert names() == []
    end

    test "returns a fresh preview when the same person was registered meanwhile", %{
      scope: scope
    } do
      file = csv([%{"氏名" => "新人 一郎", "生年月日" => "1990-04-01"}])
      {:ok, preview} = Imports.preview_service_users(scope, file)

      _ = service_user_fixture(%{name: "新人 一郎", birthdate: ~D[1990-04-01]})

      assert {:error, :stale, fresh} = Imports.commit_service_users(scope, preview)
      assert fresh.to_insert == []
      assert [%{row: 2}] = fresh.skipped
      assert names() == ["新人 一郎"]
    end
  end
end
