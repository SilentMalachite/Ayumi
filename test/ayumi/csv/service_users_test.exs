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
end
