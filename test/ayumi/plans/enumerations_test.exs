defmodule Ayumi.Plans.EnumerationsTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.{CertificateKind, Gender, SupportCategory}

  describe "Gender" do
    test "all/0 lists values in display order" do
      assert Gender.all() == [:male, :female, :other]
    end

    test "label/1 returns the Japanese label" do
      assert Gender.label(:male) == "男性"
      assert Gender.label(:other) == "その他"
    end

    test "label/1 returns nil for unknown or nil" do
      assert Gender.label(nil) == nil
      assert Gender.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"男性", :male} in Gender.options()
      assert length(Gender.options()) == 3
    end
  end

  describe "SupportCategory" do
    test "all/0 covers not_applicable and category_1..6" do
      assert SupportCategory.all() ==
               [
                 :not_applicable,
                 :category_1,
                 :category_2,
                 :category_3,
                 :category_4,
                 :category_5,
                 :category_6
               ]
    end

    test "label/1 maps values to Japanese" do
      assert SupportCategory.label(:not_applicable) == "非該当"
      assert SupportCategory.label(:category_3) == "区分3"
    end

    test "label/1 returns nil for unknown or nil" do
      assert SupportCategory.label(nil) == nil
      assert SupportCategory.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"非該当", :not_applicable} in SupportCategory.options()
      assert length(SupportCategory.options()) == 7
    end
  end

  describe "CertificateKind" do
    test "all/0 lists the three certificate kinds" do
      assert CertificateKind.all() == [:physical, :intellectual, :mental]
    end

    test "label/1 maps values to Japanese" do
      assert CertificateKind.label(:physical) == "身体障害者手帳"
      assert CertificateKind.label(:intellectual) == "療育手帳"
      assert CertificateKind.label(:mental) == "精神障害者保健福祉手帳"
    end

    test "label/1 returns nil for unknown or nil" do
      assert CertificateKind.label(nil) == nil
      assert CertificateKind.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"身体障害者手帳", :physical} in CertificateKind.options()
      assert length(CertificateKind.options()) == 3
    end
  end
end
