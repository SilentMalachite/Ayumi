defmodule Ayumi.Plans.EnumerationsTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.{CertificateKind, Gender, GoalProgressStage, PlanPhaseStage, SupportCategory}

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

  describe "GoalProgressStage" do
    test "all/0 lists stages in display order" do
      assert GoalProgressStage.all() == [
               :not_started,
               :working,
               :partially_met,
               :mostly_met,
               :met
             ]
    end

    test "label/1 maps values to Japanese" do
      assert GoalProgressStage.label(:not_started) == "未着手"
      assert GoalProgressStage.label(:working) == "取組中"
      assert GoalProgressStage.label(:partially_met) == "一部達成"
      assert GoalProgressStage.label(:mostly_met) == "概ね達成"
      assert GoalProgressStage.label(:met) == "達成"
    end

    test "label/1 returns nil for unknown or nil" do
      assert GoalProgressStage.label(nil) == nil
      assert GoalProgressStage.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"未着手", :not_started} in GoalProgressStage.options()
      assert length(GoalProgressStage.options()) == 5
    end
  end

  describe "PlanPhaseStage" do
    test "all/0 lists stages in lifecycle order" do
      assert PlanPhaseStage.all() == [
               :assessment,
               :draft,
               :support_meeting,
               :consent,
               :in_progress,
               :monitoring,
               :review
             ]
    end

    test "label/1 maps values to Japanese" do
      assert PlanPhaseStage.label(:assessment) == "アセスメント"
      assert PlanPhaseStage.label(:draft) == "計画原案"
      assert PlanPhaseStage.label(:support_meeting) == "個別支援会議"
      assert PlanPhaseStage.label(:consent) == "説明・同意・交付"
      assert PlanPhaseStage.label(:in_progress) == "支援の実施"
      assert PlanPhaseStage.label(:monitoring) == "モニタリング"
      assert PlanPhaseStage.label(:review) == "見直し"
    end

    test "label/1 returns nil for unknown or nil" do
      assert PlanPhaseStage.label(nil) == nil
      assert PlanPhaseStage.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"アセスメント", :assessment} in PlanPhaseStage.options()
      assert length(PlanPhaseStage.options()) == 7
    end
  end
end
