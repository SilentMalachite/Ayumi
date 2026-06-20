defmodule Ayumi.PlansTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans
  alias Ayumi.Plans.GoalProgress
  alias Ayumi.Plans.PlanPhaseEvent
  alias Ayumi.Plans.SupportRecord
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

    test "create_service_user/1 persists enrollment_status and enrollment_start_date" do
      assert {:ok, su} =
               Plans.create_service_user(%{
                 name: "登録 太郎",
                 enrollment_status: :trial,
                 enrollment_start_date: ~D[2026-04-01]
               })

      assert su.enrollment_status == :trial
      assert su.enrollment_start_date == ~D[2026-04-01]
    end

    test "create_service_user/1 defaults enrollment_status to :enrolled" do
      assert {:ok, su} = Plans.create_service_user(%{name: "既定 太郎"})
      assert su.enrollment_status == :enrolled
    end

    test "list_service_users/0 excludes withdrawn users by default" do
      _active = service_user_fixture(%{name: "在籍 太郎", name_kana: "ざいせき たろう"})

      _withdrawn =
        service_user_fixture(%{
          name: "退所 花子",
          name_kana: "たいしょ はなこ",
          enrollment_status: :withdrawn
        })

      names = Plans.list_service_users() |> Enum.map(& &1.name)
      assert "在籍 太郎" in names
      refute "退所 花子" in names
    end

    test "list_service_users(include_withdrawn: true) includes withdrawn users" do
      _active = service_user_fixture(%{name: "在籍 太郎", name_kana: "ざいせき たろう"})

      _withdrawn =
        service_user_fixture(%{
          name: "退所 花子",
          name_kana: "たいしょ はなこ",
          enrollment_status: :withdrawn
        })

      names = Plans.list_service_users(include_withdrawn: true) |> Enum.map(& &1.name)
      assert "在籍 太郎" in names
      assert "退所 花子" in names
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

  describe "goal progress" do
    test "record_goal_progress/1 appends a progress row" do
      goal = goal_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      recorded_at = ~U[2026-06-17 01:02:03Z]

      assert {:ok, %GoalProgress{} = progress} =
               Plans.record_goal_progress(%{
                 goal_id: goal.id,
                 stage: :working,
                 note: "午前の作業に参加できた",
                 recorded_by_id: staff.id,
                 recorded_at: recorded_at
               })

      assert progress.goal_id == goal.id
      assert progress.stage == :working
      assert progress.note == "午前の作業に参加できた"
      assert progress.recorded_by_id == staff.id
      assert progress.recorded_at == recorded_at
    end

    test "record_goal_progress/1 returns a changeset error for an invalid goal" do
      staff = Ayumi.AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Plans.record_goal_progress(%{
                 goal_id: -1,
                 stage: :working,
                 recorded_by_id: staff.id,
                 recorded_at: ~U[2026-06-17 01:02:03Z]
               })

      assert errors_on(changeset)[:goal_id]
      refute errors_on(changeset)[:recorded_by_id]
    end

    test "record_goal_progress/1 returns a changeset error for an invalid recording staff" do
      goal = goal_fixture()

      assert {:error, changeset} =
               Plans.record_goal_progress(%{
                 goal_id: goal.id,
                 stage: :working,
                 recorded_by_id: -1,
                 recorded_at: ~U[2026-06-17 01:02:03Z]
               })

      assert errors_on(changeset)[:recorded_by_id]
      refute errors_on(changeset)[:goal_id]
    end

    test "record_goal_progress/1 never updates previous progress rows" do
      goal = goal_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()

      {:ok, first} =
        Plans.record_goal_progress(%{
          goal_id: goal.id,
          stage: :working,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 01:00:00Z]
        })

      {:ok, second} =
        Plans.record_goal_progress(%{
          goal_id: goal.id,
          stage: :met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 02:00:00Z]
        })

      history = Plans.list_goal_progress(goal)

      assert first.id != second.id
      assert Enum.map(history, & &1.id) == [first.id, second.id]
      assert Enum.map(history, & &1.stage) == [:working, :met]
    end

    test "record_goal_progress_for_plan/2 records when the goal belongs to the plan" do
      plan = support_plan_fixture()
      goal = goal_fixture(%{support_plan_id: plan.id})
      staff = Ayumi.AccountsFixtures.user_fixture()
      recorded_at = ~U[2026-06-17 01:02:03Z]

      assert {:ok, %GoalProgress{} = progress} =
               Plans.record_goal_progress_for_plan(plan, %{
                 "goal_id" => to_string(goal.id),
                 "stage" => "working",
                 "note" => "午前の作業に参加できた",
                 "recorded_by_id" => staff.id,
                 "recorded_at" => recorded_at
               })

      assert progress.goal_id == goal.id
      assert progress.stage == :working
      assert progress.note == "午前の作業に参加できた"
      assert progress.recorded_by_id == staff.id
      assert progress.recorded_at == recorded_at
    end

    test "record_goal_progress_for_plan/2 rejects a goal from a different plan" do
      plan = support_plan_fixture()
      other_plan = support_plan_fixture()
      other_goal = goal_fixture(%{support_plan_id: other_plan.id})
      staff = Ayumi.AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Plans.record_goal_progress_for_plan(plan, %{
                 goal_id: other_goal.id,
                 stage: :working,
                 recorded_by_id: staff.id,
                 recorded_at: ~U[2026-06-17 01:02:03Z]
               })

      assert errors_on(changeset)[:goal_id]
      assert Plans.list_goal_progress(other_goal) == []
    end

    test "record_goal_progress_for_plan/2 rejects a malformed goal_id without raising" do
      plan = support_plan_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Plans.record_goal_progress_for_plan(plan, %{
                 "goal_id" => "not-a-goal-id",
                 "stage" => "working",
                 "recorded_by_id" => staff.id,
                 "recorded_at" => ~U[2026-06-17 01:02:03Z]
               })

      assert errors_on(changeset)[:goal_id]
    end

    test "record_goal_progress_for_plan/2 rejects a missing goal_id without inserting progress" do
      plan = support_plan_fixture()
      goal = goal_fixture(%{support_plan_id: plan.id})
      staff = Ayumi.AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Plans.record_goal_progress_for_plan(plan, %{
                 stage: :working,
                 recorded_by_id: staff.id,
                 recorded_at: ~U[2026-06-17 01:00:00Z]
               })

      assert errors_on(changeset)[:goal_id]
      assert Plans.list_goal_progress(goal) == []
    end

    test "list_goal_progress/1 returns one goal's history in insertion order with staff preloaded" do
      goal = goal_fixture()
      staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "記録 職員"})

      {:ok, _} =
        Plans.record_goal_progress(%{
          goal_id: goal.id,
          stage: :working,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 01:00:00Z]
        })

      {:ok, _} =
        Plans.record_goal_progress(%{
          goal_id: goal.id,
          stage: :mostly_met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 02:00:00Z]
        })

      assert [:working, :mostly_met] = Plans.list_goal_progress(goal) |> Enum.map(& &1.stage)
      assert [%{recorded_by: %{name: "記録 職員"}} | _] = Plans.list_goal_progress(goal)
    end

    test "list_goal_progress_for_goals/1 returns grouped histories and empty lists" do
      plan = support_plan_fixture()
      first_goal = goal_fixture(%{support_plan_id: plan.id, description: "1番目"})
      second_goal = goal_fixture(%{support_plan_id: plan.id, description: "2番目"})
      empty_goal = goal_fixture(%{support_plan_id: plan.id, description: "未記録"})
      staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "記録 職員"})

      first_progress =
        goal_progress_fixture(%{
          goal_id: first_goal.id,
          stage: :working,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 01:00:00Z]
        })

      second_progress =
        goal_progress_fixture(%{
          goal_id: first_goal.id,
          stage: :met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 02:00:00Z]
        })

      third_progress =
        goal_progress_fixture(%{
          goal_id: second_goal.id,
          stage: :partially_met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 03:00:00Z]
        })

      histories = Plans.list_goal_progress_for_goals([first_goal, second_goal, empty_goal])

      assert Enum.map(histories[first_goal.id], & &1.id) == [
               first_progress.id,
               second_progress.id
             ]

      assert Enum.map(histories[second_goal.id], & &1.id) == [third_progress.id]
      assert histories[empty_goal.id] == []
      assert [%{recorded_by: %{name: "記録 職員"}} | _] = histories[first_goal.id]
    end

    test "list_goal_progress_for_goals/1 returns an empty map for an empty goal list" do
      assert Plans.list_goal_progress_for_goals([]) == %{}
    end

    test "current_goal_progress/1 returns nil for an empty history" do
      assert Plans.current_goal_progress([]) == nil
    end

    test "current_goal_progress/1 returns the latest inserted progress row" do
      older = %GoalProgress{id: 1, stage: :working}
      newer = %GoalProgress{id: 2, stage: :met}

      assert Plans.current_goal_progress([newer, older]) == newer
    end

    test "latest_goal_progress_by_goal/1 returns an empty map for an empty goal list" do
      assert Plans.latest_goal_progress_by_goal([]) == %{}
    end

    test "latest_goal_progress_by_goal/1 returns latest progress for multiple goals without losing empty goals" do
      plan = support_plan_fixture()
      first_goal = goal_fixture(%{support_plan_id: plan.id, description: "1番目"})
      second_goal = goal_fixture(%{support_plan_id: plan.id, description: "2番目"})
      empty_goal = goal_fixture(%{support_plan_id: plan.id, description: "未記録"})
      staff = Ayumi.AccountsFixtures.user_fixture()

      {:ok, _} =
        Plans.record_goal_progress(%{
          goal_id: first_goal.id,
          stage: :working,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 01:00:00Z]
        })

      {:ok, latest_first} =
        Plans.record_goal_progress(%{
          goal_id: first_goal.id,
          stage: :met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 02:00:00Z]
        })

      {:ok, latest_second} =
        Plans.record_goal_progress(%{
          goal_id: second_goal.id,
          stage: :partially_met,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-17 03:00:00Z]
        })

      latest_by_goal = Plans.latest_goal_progress_by_goal([first_goal, second_goal, empty_goal])

      assert latest_by_goal[first_goal.id].id == latest_first.id
      assert latest_by_goal[second_goal.id].id == latest_second.id
      assert latest_by_goal[empty_goal.id] == nil
    end
  end

  describe "plan phase events" do
    test "record_plan_phase_event/1 appends a phase event row" do
      plan = support_plan_fixture()
      staff = Ayumi.AccountsFixtures.staff_fixture()
      recorded_at = ~U[2026-06-18 01:02:03Z]

      assert {:ok, %PlanPhaseEvent{} = event} =
               Plans.record_plan_phase_event(%{
                 support_plan_id: plan.id,
                 stage: :support_meeting,
                 note: "会議で支援内容を確認した",
                 recorded_by_id: staff.id,
                 recorded_at: recorded_at
               })

      assert event.support_plan_id == plan.id
      assert event.stage == :support_meeting
      assert event.note == "会議で支援内容を確認した"
      assert event.recorded_by_id == staff.id
      assert event.recorded_at == recorded_at
    end

    test "record_plan_phase_event/1 returns a changeset error for an invalid support plan" do
      staff = Ayumi.AccountsFixtures.staff_fixture()

      assert {:error, changeset} =
               Plans.record_plan_phase_event(%{
                 support_plan_id: -1,
                 stage: :assessment,
                 recorded_by_id: staff.id,
                 recorded_at: ~U[2026-06-18 01:02:03Z]
               })

      assert errors_on(changeset)[:support_plan_id]
      refute errors_on(changeset)[:recorded_by_id]
    end

    test "record_plan_phase_event/1 returns a changeset error for an invalid recording staff" do
      plan = support_plan_fixture()

      assert {:error, changeset} =
               Plans.record_plan_phase_event(%{
                 support_plan_id: plan.id,
                 stage: :assessment,
                 recorded_by_id: -1,
                 recorded_at: ~U[2026-06-18 01:02:03Z]
               })

      assert errors_on(changeset)[:recorded_by_id]
      refute errors_on(changeset)[:support_plan_id]
    end

    test "record_plan_phase_event/1 never updates previous phase rows" do
      plan = support_plan_fixture()
      staff = Ayumi.AccountsFixtures.staff_fixture()

      {:ok, first} =
        Plans.record_plan_phase_event(%{
          support_plan_id: plan.id,
          stage: :assessment,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-18 01:00:00Z]
        })

      {:ok, second} =
        Plans.record_plan_phase_event(%{
          support_plan_id: plan.id,
          stage: :draft,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-18 02:00:00Z]
        })

      history = Plans.list_plan_phase_events(plan)

      assert first.id != second.id
      assert Enum.map(history, & &1.id) == [first.id, second.id]
      assert Enum.map(history, & &1.stage) == [:assessment, :draft]
    end

    test "list_plan_phase_events/1 returns one plan's history in insertion order with staff preloaded" do
      plan = support_plan_fixture()
      staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "記録 職員"})

      {:ok, _} =
        Plans.record_plan_phase_event(%{
          support_plan_id: plan.id,
          stage: :assessment,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-18 01:00:00Z]
        })

      {:ok, _} =
        Plans.record_plan_phase_event(%{
          support_plan_id: plan.id,
          stage: :consent,
          recorded_by_id: staff.id,
          recorded_at: ~U[2026-06-18 02:00:00Z]
        })

      assert [:assessment, :consent] =
               Plans.list_plan_phase_events(plan) |> Enum.map(& &1.stage)

      assert [%{recorded_by: %{name: "記録 職員"}} | _] = Plans.list_plan_phase_events(plan)
    end

    test "current_plan_stage/1 returns nil for an empty history" do
      assert Plans.current_plan_stage([]) == nil
    end

    test "current_plan_stage/1 returns the latest inserted phase event" do
      older = %PlanPhaseEvent{id: 1, stage: :assessment}
      newer = %PlanPhaseEvent{id: 2, stage: :in_progress}

      assert Plans.current_plan_stage([newer, older]) == newer
    end
  end

  describe "monitoring deadline alerts" do
    test "monitoring_deadline_status/3 classifies overdue, near, and ok" do
      today = ~D[2026-06-18]

      assert Plans.monitoring_deadline_status(~D[2026-06-17], today, 30) == :overdue
      assert Plans.monitoring_deadline_status(~D[2026-06-18], today, 30) == :near
      assert Plans.monitoring_deadline_status(~D[2026-07-18], today, 30) == :near
      assert Plans.monitoring_deadline_status(~D[2026-07-19], today, 30) == :ok
    end

    test "list_monitoring_deadline_alerts/3 ignores older plans for the same service user" do
      today = ~D[2026-06-18]
      staff = Ayumi.AccountsFixtures.staff_fixture()
      service_user = service_user_fixture(%{name: "期またぎ 太郎", name_kana: "きまたぎ たろう"})

      _old_overdue =
        support_plan_fixture(%{
          service_user_id: service_user.id,
          staff_id: staff.id,
          period_start: ~D[2025-04-01],
          period_end: ~D[2025-09-30],
          next_monitoring_date: ~D[2025-05-01]
        })

      current_ok =
        support_plan_fixture(%{
          service_user_id: service_user.id,
          staff_id: staff.id,
          period_start: ~D[2026-04-01],
          period_end: ~D[2026-09-30],
          next_monitoring_date: ~D[2026-08-01]
        })

      alerts =
        Plans.list_monitoring_deadline_alerts(Ayumi.Accounts.Scope.for_user(staff), today, 30)

      refute Enum.any?(alerts, &(&1.support_plan.id == current_ok.id))
      assert alerts == []
    end

    test "list_monitoring_deadline_alerts/3 includes all users and sorts current staff first, then urgent" do
      today = ~D[2026-06-18]
      current_staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "担当 職員"})
      other_staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "別 職員"})

      own_user = service_user_fixture(%{name: "自分 担当", name_kana: "じぶん たんとう"})
      other_overdue_user = service_user_fixture(%{name: "他 超過", name_kana: "た ちょうか"})
      other_near_user = service_user_fixture(%{name: "他 近接", name_kana: "た きんせつ"})

      own_near =
        support_plan_fixture(%{
          service_user_id: own_user.id,
          staff_id: current_staff.id,
          next_monitoring_date: ~D[2026-06-25]
        })

      other_overdue =
        support_plan_fixture(%{
          service_user_id: other_overdue_user.id,
          staff_id: other_staff.id,
          next_monitoring_date: ~D[2026-06-01]
        })

      other_near =
        support_plan_fixture(%{
          service_user_id: other_near_user.id,
          staff_id: other_staff.id,
          next_monitoring_date: ~D[2026-06-20]
        })

      alerts =
        current_staff
        |> Ayumi.Accounts.Scope.for_user()
        |> Plans.list_monitoring_deadline_alerts(today, 30)

      assert Enum.map(alerts, & &1.support_plan.id) == [
               own_near.id,
               other_overdue.id,
               other_near.id
             ]

      assert [%{status: :near, assigned_to_current_user?: true} | _] = alerts
      assert Enum.map(alerts, & &1.days_until) == [7, -17, 2]
    end

    test "list_monitoring_deadline_alerts/3 excludes withdrawn service users" do
      today = ~D[2026-06-18]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      withdrawn_user =
        service_user_fixture(%{
          name: "退所 太郎",
          name_kana: "たいしょ たろう",
          enrollment_status: :withdrawn
        })

      _overdue_plan =
        support_plan_fixture(%{
          service_user_id: withdrawn_user.id,
          staff_id: staff.id,
          next_monitoring_date: ~D[2026-06-01]
        })

      alerts =
        Plans.list_monitoring_deadline_alerts(Ayumi.Accounts.Scope.for_user(staff), today, 30)

      refute Enum.any?(alerts, &(&1.support_plan.service_user.id == withdrawn_user.id))
    end
  end

  describe "certificate expiry alerts" do
    test "overdue when recipient_cert_expiry is in the past" do
      today = ~D[2026-06-20]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      su =
        service_user_fixture(%{
          name: "期限切れ 太郎",
          name_kana: "きげんぎれ たろう",
          recipient_cert_expiry: ~D[2026-06-10]
        })

      alerts =
        Plans.list_certificate_expiry_alerts(
          Ayumi.Accounts.Scope.for_user(staff),
          today,
          60
        )

      assert [%{service_user: ^su, status: :overdue, days_until: -10}] = alerts
    end

    test "near when recipient_cert_expiry is within near_days" do
      today = ~D[2026-06-20]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      su =
        service_user_fixture(%{
          name: "近接 花子",
          name_kana: "きんせつ はなこ",
          recipient_cert_expiry: ~D[2026-08-01]
        })

      alerts =
        Plans.list_certificate_expiry_alerts(
          Ayumi.Accounts.Scope.for_user(staff),
          today,
          60
        )

      assert [%{service_user: ^su, status: :near, days_until: 42}] = alerts
    end

    test "excludes ok status and nil recipient_cert_expiry" do
      today = ~D[2026-06-20]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      _far_away =
        service_user_fixture(%{
          name: "遠い 太郎",
          recipient_cert_expiry: ~D[2026-12-31]
        })

      _nil_expiry =
        service_user_fixture(%{
          name: "未設定 花子",
          recipient_cert_expiry: nil
        })

      alerts =
        Plans.list_certificate_expiry_alerts(
          Ayumi.Accounts.Scope.for_user(staff),
          today,
          60
        )

      assert alerts == []
    end

    test "sorts by days_until ascending, then name_kana, name, id" do
      today = ~D[2026-06-20]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      su_later =
        service_user_fixture(%{
          name: "後 太郎",
          name_kana: "あと たろう",
          recipient_cert_expiry: ~D[2026-07-10]
        })

      su_sooner =
        service_user_fixture(%{
          name: "先 花子",
          name_kana: "さき はなこ",
          recipient_cert_expiry: ~D[2026-06-15]
        })

      su_same_day =
        service_user_fixture(%{
          name: "同日 次郎",
          name_kana: "あと じろう",
          recipient_cert_expiry: ~D[2026-07-10]
        })

      alerts =
        Plans.list_certificate_expiry_alerts(
          Ayumi.Accounts.Scope.for_user(staff),
          today,
          60
        )

      assert Enum.map(alerts, & &1.service_user.id) == [
               su_sooner.id,
               su_same_day.id,
               su_later.id
             ]
    end

    test "list_certificate_expiry_alerts/3 excludes withdrawn service users" do
      today = ~D[2026-06-20]
      staff = Ayumi.AccountsFixtures.staff_fixture()

      _withdrawn =
        service_user_fixture(%{
          name: "退所 花子",
          name_kana: "たいしょ はなこ",
          enrollment_status: :withdrawn,
          recipient_cert_expiry: ~D[2026-06-10]
        })

      alerts =
        Plans.list_certificate_expiry_alerts(
          Ayumi.Accounts.Scope.for_user(staff),
          today,
          60
        )

      assert alerts == []
    end
  end

  describe "support records" do
    test "create_support_record/2 inserts a record with scope-derived fields" do
      service_user = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      assert {:ok, %SupportRecord{} = record} =
               Plans.create_support_record(scope, %{
                 service_user_id: service_user.id,
                 content: "午前の作業に集中できた",
                 category: :work
               })

      assert record.service_user_id == service_user.id
      assert record.content == "午前の作業に集中できた"
      assert record.category == :work
      assert record.recorded_by_id == staff.id
      assert %DateTime{} = record.recorded_at
    end

    test "create_support_record/2 rejects empty content" do
      service_user = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      assert {:error, changeset} =
               Plans.create_support_record(scope, %{
                 service_user_id: service_user.id,
                 content: "",
                 category: :work
               })

      assert errors_on(changeset)[:content]
    end

    test "create_support_record/2 rejects invalid category" do
      service_user = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      assert {:error, changeset} =
               Plans.create_support_record(scope, %{
                 service_user_id: service_user.id,
                 content: "テスト",
                 category: :invalid
               })

      assert errors_on(changeset)[:category]
    end

    test "create_support_record/2 rejects invalid service_user_id" do
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      assert {:error, changeset} =
               Plans.create_support_record(scope, %{
                 service_user_id: -1,
                 content: "テスト",
                 category: :work
               })

      assert errors_on(changeset)[:service_user_id]
    end

    test "list_support_records/2 filters by service_user_id" do
      su1 = service_user_fixture()
      su2 = service_user_fixture(%{name: "鈴木 花子"})
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      {:ok, _} =
        Plans.create_support_record(scope, %{
          service_user_id: su1.id,
          content: "記録1",
          category: :work
        })

      {:ok, _} =
        Plans.create_support_record(scope, %{
          service_user_id: su2.id,
          content: "記録2",
          category: :health
        })

      records = Plans.list_support_records(scope, service_user_id: su1.id)
      assert length(records) == 1
      assert hd(records).content == "記録1"
    end

    test "list_support_records/2 filters by date range" do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      {:ok, early} =
        Plans.create_support_record(scope, %{
          service_user_id: su.id,
          content: "早い記録",
          category: :work
        })

      # Manually update recorded_at to a known date for testing
      Ayumi.Repo.update_all(
        from(r in SupportRecord, where: r.id == ^early.id),
        set: [recorded_at: ~U[2026-06-01 10:00:00Z]]
      )

      {:ok, late} =
        Plans.create_support_record(scope, %{
          service_user_id: su.id,
          content: "遅い記録",
          category: :health
        })

      Ayumi.Repo.update_all(
        from(r in SupportRecord, where: r.id == ^late.id),
        set: [recorded_at: ~U[2026-06-15 10:00:00Z]]
      )

      records =
        Plans.list_support_records(scope, from: ~D[2026-06-10], to: ~D[2026-06-20])

      assert length(records) == 1
      assert hd(records).content == "遅い記録"
    end

    test "list_support_records/2 returns descending order with preloads" do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      scope = Ayumi.Accounts.Scope.for_user(staff)

      {:ok, first} =
        Plans.create_support_record(scope, %{
          service_user_id: su.id,
          content: "最初の記録",
          category: :work
        })

      Ayumi.Repo.update_all(
        from(r in SupportRecord, where: r.id == ^first.id),
        set: [recorded_at: ~U[2026-06-01 10:00:00Z]]
      )

      {:ok, second} =
        Plans.create_support_record(scope, %{
          service_user_id: su.id,
          content: "二番目の記録",
          category: :daily_living
        })

      Ayumi.Repo.update_all(
        from(r in SupportRecord, where: r.id == ^second.id),
        set: [recorded_at: ~U[2026-06-02 10:00:00Z]]
      )

      records = Plans.list_support_records(scope)

      assert [r2, r1] = records
      assert r2.content == "二番目の記録"
      assert r1.content == "最初の記録"
      assert %Ayumi.Plans.ServiceUser{} = r2.service_user
      assert %Ayumi.Accounts.User{} = r2.recorded_by
    end
  end

  describe "referential integrity" do
    test "creating a goal for a non-existent plan returns an error changeset" do
      assert {:error, changeset} =
               Plans.create_goal(%{support_plan_id: -1, description: "孤児"})

      assert errors_on(changeset)[:support_plan_id]
    end
  end
end
