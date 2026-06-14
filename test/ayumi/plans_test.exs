defmodule Ayumi.PlansTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans
  alias Ayumi.Plans.ServiceUser
  alias Ayumi.Plans.SupportPlan
  alias Ayumi.Plans.Goal

  import Ayumi.PlansFixtures

  describe "service users" do
    test "create_service_user/1 with valid data" do
      assert {:ok, %ServiceUser{} = su} = Plans.create_service_user(%{name: "佐藤 花子"})
      assert su.name == "佐藤 花子"
    end

    test "create_service_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Plans.create_service_user(%{})
    end

    test "list_service_users/0 orders by kana then name" do
      service_user_fixture(%{name: "B", name_kana: "い"})
      service_user_fixture(%{name: "A", name_kana: "あ"})
      assert ["あ", "い"] = Plans.list_service_users() |> Enum.map(& &1.name_kana)
    end

    test "get_service_user!/1 returns the record" do
      su = service_user_fixture()
      assert Plans.get_service_user!(su.id).id == su.id
    end

    test "drop_blank_certificates/1 removes an all-blank certificate row" do
      attrs = %{
        "name" => "山田",
        "disability_certificates" => %{
          "0" => %{"kind" => "", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert %{"disability_certificates" => certs} = Plans.drop_blank_certificates(attrs)
      assert certs == %{}
    end

    test "drop_blank_certificates/1 treats whitespace-only fields as blank" do
      attrs = %{
        "disability_certificates" => %{
          "0" => %{"kind" => "  ", "number" => "\t", "disability_name" => " ", "grade" => ""}
        }
      }

      assert %{"disability_certificates" => certs} = Plans.drop_blank_certificates(attrs)
      assert certs == %{}
    end

    test "drop_blank_certificates/1 keeps a row that has any content" do
      attrs = %{
        "name" => "山田",
        "disability_certificates" => %{
          "0" => %{"kind" => "physical", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert %{"disability_certificates" => %{"0" => kept}} = Plans.drop_blank_certificates(attrs)
      assert kept["kind"] == "physical"
    end

    test "drop_blank_certificates/1 passes through attrs without the key" do
      attrs = %{"name" => "山田"}
      assert Plans.drop_blank_certificates(attrs) == attrs
    end

    test "create_service_user/1 persists a nested certificate" do
      assert {:ok, su} =
               Plans.create_service_user(%{
                 name: "手帳 太郎",
                 disability_certificates: [%{kind: :physical, number: "B-1", grade: "2級"}]
               })

      su = Plans.get_service_user!(su.id)

      assert [%Ayumi.Plans.DisabilityCertificate{kind: :physical, number: "B-1"}] =
               su.disability_certificates
    end

    test "create_service_user/1 drops an all-blank certificate row" do
      attrs = %{
        "name" => "空手帳 太郎",
        "disability_certificates" => %{
          "0" => %{"kind" => "", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert {:ok, su} = Plans.create_service_user(attrs)
      assert Plans.get_service_user!(su.id).disability_certificates == []
    end

    test "get_service_user!/1 preloads disability_certificates" do
      su = service_user_with_certificate_fixture()
      loaded = Plans.get_service_user!(su.id)
      assert [%Ayumi.Plans.DisabilityCertificate{}] = loaded.disability_certificates
    end

    test "update_service_user/2 changes flat fields" do
      su = service_user_fixture()
      assert {:ok, updated} = Plans.update_service_user(su, %{phone: "03-1111-2222"})
      assert updated.phone == "03-1111-2222"
    end

    test "update_service_user/2 updates an existing certificate" do
      su = service_user_with_certificate_fixture()
      su = Plans.get_service_user!(su.id)
      [cert] = su.disability_certificates

      params = %{
        "disability_certificates" => %{
          "0" => %{"id" => to_string(cert.id), "kind" => "physical", "grade" => "1級"}
        }
      }

      assert {:ok, _} = Plans.update_service_user(su, params)
      assert [%{grade: "1級"}] = Plans.get_service_user!(su.id).disability_certificates
    end

    test "update_service_user/2 deletes a certificate when its row is blanked" do
      su = service_user_with_certificate_fixture()
      su = Plans.get_service_user!(su.id)
      [cert] = su.disability_certificates

      params = %{
        "disability_certificates" => %{
          "0" => %{
            "id" => to_string(cert.id),
            "kind" => "",
            "number" => "",
            "disability_name" => "",
            "grade" => ""
          }
        }
      }

      assert {:ok, _} = Plans.update_service_user(su, params)
      assert Plans.get_service_user!(su.id).disability_certificates == []
    end
  end

  describe "support plans" do
    test "create_support_plan/1 with valid data" do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()

      assert {:ok, %SupportPlan{} = plan} =
               Plans.create_support_plan(%{
                 service_user_id: su.id,
                 staff_id: staff.id,
                 period_start: ~D[2026-04-01],
                 period_end: ~D[2026-09-30],
                 long_term_goal: "目標",
                 next_monitoring_date: ~D[2026-07-01]
               })

      assert plan.service_user_id == su.id
    end

    test "list_support_plans_for_user/1 returns the user's plans newest-period first" do
      su = service_user_fixture()
      _old = support_plan_fixture(%{service_user_id: su.id, period_start: ~D[2025-04-01]})
      _new = support_plan_fixture(%{service_user_id: su.id, period_start: ~D[2026-04-01]})

      assert [~D[2026-04-01], ~D[2025-04-01]] =
               Plans.list_support_plans_for_user(su) |> Enum.map(& &1.period_start)
    end

    test "get_support_plan!/1 preloads service_user, staff and goals" do
      plan = support_plan_fixture()
      loaded = Plans.get_support_plan!(plan.id)
      assert %Ayumi.Plans.ServiceUser{} = loaded.service_user
      assert %Ayumi.Accounts.User{} = loaded.staff
      assert is_list(loaded.goals)
    end
  end

  describe "goals" do
    test "create_goal/1 attaches a goal to a plan" do
      plan = support_plan_fixture()

      assert {:ok, %Goal{} = goal} =
               Plans.create_goal(%{support_plan_id: plan.id, description: "目標A"})

      assert goal.support_plan_id == plan.id
    end

    test "list_goals/1 returns a plan's goals in insertion order" do
      plan = support_plan_fixture()
      {:ok, _} = Plans.create_goal(%{support_plan_id: plan.id, description: "1番目"})
      {:ok, _} = Plans.create_goal(%{support_plan_id: plan.id, description: "2番目"})
      assert ["1番目", "2番目"] = Plans.list_goals(plan) |> Enum.map(& &1.description)
    end
  end

  describe "optimistic locking" do
    test "new body records start at lock_version 0" do
      assert service_user_fixture().lock_version == 0
      assert support_plan_fixture().lock_version == 0
      assert goal_fixture().lock_version == 0
    end

    test "changeset/2 ignores a lock_version supplied via params (no form tampering)" do
      cs = ServiceUser.changeset(%ServiceUser{}, %{"name" => "X", "lock_version" => "999"})
      refute Map.has_key?(cs.changes, :lock_version)
    end

    test "SupportPlan.changeset/2 ignores a lock_version supplied via params" do
      cs =
        SupportPlan.changeset(%SupportPlan{}, %{"long_term_goal" => "目標", "lock_version" => "999"})

      refute Map.has_key?(cs.changes, :lock_version)
    end

    test "Goal.changeset/2 ignores a lock_version supplied via params" do
      cs = Goal.changeset(%Goal{}, %{"description" => "目標", "lock_version" => "999"})
      refute Map.has_key?(cs.changes, :lock_version)
    end
  end

  describe "referential integrity" do
    test "creating a goal for a non-existent plan is rejected by the database" do
      assert_raise Ecto.ConstraintError, fn ->
        Plans.create_goal(%{support_plan_id: -1, description: "孤児"})
      end
    end
  end
end
