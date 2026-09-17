defmodule Ayumi.CSV.ServiceUsersTest do
  use ExUnit.Case, async: true

  alias Ayumi.CSV.ServiceUsers
  alias Ayumi.Plans.{DisabilityCertificate, ServiceUser}

  @headers ~w[
    利用者ID 氏名 ふりがな 生年月日 性別 在籍状態 利用開始日
    郵便番号 住所 電話番号 緊急連絡先氏名 緊急連絡先続柄 緊急連絡先電話
    受給者証番号 支給市町村 障害支援区分 支給量 受給者証有効期限
    通院先 主治医 服薬・特記 相談支援事業所 担当相談員 備考 障害者手帳
  ]

  test "headers/0 follows the registration form, top to bottom" do
    assert ServiceUsers.headers() == @headers
  end

  test "dump/1 renders every flat field and summarizes the certificates" do
    service_user = %ServiceUser{
      id: 3,
      name: "山田 太郎",
      name_kana: "やまだ たろう",
      birthdate: ~D[1990-04-01],
      gender: :male,
      enrollment_status: :enrolled,
      enrollment_start_date: ~D[2025-04-01],
      postal_code: "060-0001",
      address: "札幌市中央区1-1",
      phone: "090-1234-5678",
      emergency_contact_name: "山田 花子",
      emergency_contact_relation: "母",
      emergency_contact_phone: "011-123-4567",
      recipient_cert_number: "0123456789",
      recipient_cert_municipality: "札幌市",
      disability_support_category: :category_3,
      benefit_amount: "当該月の日数-8日",
      recipient_cert_expiry: ~D[2027-03-31],
      clinic_name: "中央病院",
      attending_physician: "佐藤",
      medication_notes: "朝夕\n服薬あり",
      consultation_office: "相談センター",
      consultation_staff: "鈴木",
      notes: "特になし",
      disability_certificates: [
        %DisabilityCertificate{
          kind: :physical,
          number: "第123号",
          disability_name: "下肢機能障害",
          grade: "3級"
        },
        %DisabilityCertificate{kind: :intellectual, number: nil, disability_name: "", grade: "B2"}
      ]
    }

    assert ServiceUsers.dump([service_user]) == [
             [
               "3",
               "山田 太郎",
               "やまだ たろう",
               "1990-04-01",
               "男性",
               "在籍",
               "2025-04-01",
               "060-0001",
               "札幌市中央区1-1",
               "090-1234-5678",
               "山田 花子",
               "母",
               "011-123-4567",
               "0123456789",
               "札幌市",
               "区分3",
               "当該月の日数-8日",
               "2027-03-31",
               "中央病院",
               "佐藤",
               "朝夕\n服薬あり",
               "相談センター",
               "鈴木",
               "特になし",
               "身体障害者手帳 第123号 下肢機能障害 3級 / 療育手帳 B2"
             ]
           ]
  end

  test "dump/1 leaves every optional field blank for a name-only service user" do
    [row] = ServiceUsers.dump([%ServiceUser{id: 9, name: "名前のみ", disability_certificates: []}])

    assert length(row) == length(@headers)
    assert Enum.take(row, 2) == ["9", "名前のみ"]
    # 在籍状態 defaults to 在籍; everything else is blank.
    assert Enum.at(row, 5) == "在籍"
    assert row |> List.delete_at(5) |> Enum.drop(2) |> Enum.uniq() == [""]
  end

  describe "required_headers/0" do
    test "is every column except the certificate summary, which is export-only" do
      assert ServiceUsers.required_headers() == @headers -- ["障害者手帳"]
    end
  end

  describe "parse/1" do
    defp cells(overrides) do
      @headers |> Map.new(&{&1, ""}) |> Map.merge(overrides)
    end

    test "reads every flat field" do
      cells =
        cells(%{
          "利用者ID" => "3",
          "氏名" => "山田 太郎",
          "ふりがな" => "やまだ たろう",
          "生年月日" => "1990/4/1",
          "性別" => "男性",
          "在籍状態" => "体験利用",
          "利用開始日" => "2025-04-01",
          "郵便番号" => "060-0001",
          "受給者証番号" => "0123456789",
          "障害支援区分" => "区分3",
          "受給者証有効期限" => "2027-03-31",
          "服薬・特記" => "朝夕\r\n服薬あり",
          "障害者手帳" => "無視される"
        })

      assert {:ok, attrs} = ServiceUsers.parse(cells)
      assert attrs.id == 3
      assert attrs.name == "山田 太郎"
      assert attrs.birthdate == ~D[1990-04-01]
      assert attrs.gender == :male
      assert attrs.enrollment_status == :trial
      assert attrs.recipient_cert_number == "0123456789"
      assert attrs.disability_support_category == :category_3
      assert attrs.recipient_cert_expiry == ~D[2027-03-31]
      assert attrs.medication_notes == "朝夕\n服薬あり"
      assert attrs.address == nil
      refute Map.has_key?(attrs, :disability_certificates)
    end

    test "reads back what dump/1 wrote" do
      service_user = %ServiceUser{
        id: 3,
        name: "山田 太郎",
        gender: :female,
        enrollment_status: :suspended,
        birthdate: ~D[1990-04-01],
        disability_certificates: []
      }

      [row] = ServiceUsers.dump([service_user])
      assert {:ok, attrs} = @headers |> Enum.zip(row) |> Map.new() |> ServiceUsers.parse()

      assert {attrs.id, attrs.name, attrs.gender, attrs.enrollment_status, attrs.birthdate} ==
               {3, "山田 太郎", :female, :suspended, ~D[1990-04-01]}
    end

    test "requires the name and reports unreadable cells by column" do
      assert {:error, errors} =
               ServiceUsers.parse(cells(%{"氏名" => "", "生年月日" => "平成2年", "性別" => "男"}))

      assert Enum.map(errors, & &1.column) == ["氏名", "生年月日", "性別"]
    end
  end

  test "header_for/1 maps a schema field back to its column header" do
    assert ServiceUsers.header_for(:name) == "氏名"
    assert ServiceUsers.header_for(:recipient_cert_expiry) == "受給者証有効期限"
  end
end
