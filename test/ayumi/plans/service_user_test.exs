defmodule Ayumi.Plans.ServiceUserTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.ServiceUser

  @full_attrs %{
    name: "山田 太郎",
    name_kana: "やまだ たろう",
    birthdate: ~D[1990-05-20],
    gender: :male,
    postal_code: "100-0001",
    address: "東京都千代田区1-1",
    phone: "03-0000-0000",
    emergency_contact_name: "山田 花子",
    emergency_contact_relation: "母",
    emergency_contact_phone: "090-0000-0000",
    recipient_cert_number: "R-12345",
    recipient_cert_municipality: "千代田区",
    disability_support_category: :category_3,
    benefit_amount: "週5日",
    recipient_cert_expiry: ~D[2027-03-31],
    clinic_name: "千代田クリニック",
    attending_physician: "田中 医師",
    medication_notes: "毎朝1錠",
    consultation_office: "ちよだ相談支援",
    consultation_staff: "鈴木 相談員",
    notes: "備考テキスト"
  }

  test "requires name" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{})
    refute changeset.valid?
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "name_kana is optional" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{name: "山田 太郎"})
    assert changeset.valid?
  end

  test "accepts a full set of basic-info attributes" do
    changeset = ServiceUser.changeset(%ServiceUser{}, @full_attrs)
    assert changeset.valid?
    assert get_change(changeset, :gender) == :male
    assert get_change(changeset, :disability_support_category) == :category_3
  end

  test "rejects an invalid gender" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{name: "山田", gender: "bogus"})
    refute changeset.valid?
    assert %{gender: ["is invalid"]} = errors_on(changeset)
  end

  test "rejects an invalid disability_support_category" do
    changeset =
      ServiceUser.changeset(%ServiceUser{}, %{name: "山田", disability_support_category: "bogus"})

    refute changeset.valid?
    assert %{disability_support_category: ["is invalid"]} = errors_on(changeset)
  end

  describe "age/2" do
    test "returns nil when birthdate is nil" do
      assert ServiceUser.age(%ServiceUser{birthdate: nil}, ~D[2026-06-14]) == nil
    end

    test "counts a birthday that already passed this year" do
      su = %ServiceUser{birthdate: ~D[1990-05-20]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 36
    end

    test "does not count a birthday that has not arrived yet" do
      su = %ServiceUser{birthdate: ~D[1990-07-20]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 35
    end

    test "counts the birthday itself" do
      su = %ServiceUser{birthdate: ~D[1990-06-14]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 36
    end
  end

  test "casts a nested disability certificate" do
    attrs = %{
      name: "山田 太郎",
      disability_certificates: [%{kind: :physical, number: "B-1", grade: "2級"}]
    }

    changeset = ServiceUser.changeset(%ServiceUser{}, attrs)
    assert changeset.valid?
    assert [cert_cs] = get_change(changeset, :disability_certificates)
    assert get_change(cert_cs, :kind) == :physical
  end
end
