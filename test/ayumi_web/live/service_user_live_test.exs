defmodule AyumiWeb.ServiceUserLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  describe "supporter access" do
    setup :register_and_log_in_user

    test "lists existing service users", %{conn: conn} do
      service_user_fixture(%{name: "既存 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      assert html =~ "既存 利用者"
    end

    test "supporter cannot access new service user form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/service_users/new")
    end

    test "supporter cannot access edit service user form", %{conn: conn} do
      su = service_user_fixture()
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/service_users/#{su.id}/edit")
    end

    test "supporter cannot access new support plan form", %{conn: conn} do
      su = service_user_fixture()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/service_users/#{su.id}/support_plans/new")
    end

    test "supporter can view service user details", %{conn: conn} do
      su = service_user_fixture(%{name: "閲覧 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "閲覧 利用者"
    end

    test "supporter does not see 新規登録 button on index", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      refute html =~ "新規登録"
    end

    test "supporter does not see 編集 or 支援計画を作成 buttons on show", %{conn: conn} do
      su = service_user_fixture(%{name: "閲覧テスト"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      refute html =~ "編集"
      refute html =~ "支援計画を作成"
    end
  end

  describe "manager access" do
    setup :register_and_log_in_manager

    test "lists existing service users", %{conn: conn} do
      service_user_fixture(%{name: "既存 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      assert html =~ "既存 利用者"
    end

    test "shows a 新規登録 link to the new form", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/service_users")
      assert html =~ "新規登録"

      {:ok, _form_lv, form_html} =
        lv |> element("a", "新規登録") |> render_click() |> follow_redirect(conn)

      assert form_html =~ "利用者の新規登録"
    end

    test "requires login", %{conn: _conn} do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/service_users")
    end

    test "退所者のまとめ画面には支援計画作成ボタンを出さない", %{conn: conn} do
      su = service_user_fixture(enrollment_status: :withdrawn)
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      refute html =~ "支援計画を作成"
    end

    test "在籍者のまとめ画面には支援計画作成ボタンを出す", %{conn: conn} do
      su = service_user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "支援計画を作成"
    end

    test "shows a service user with their support plans", %{conn: conn} do
      su = service_user_fixture(%{name: "表示 利用者"})
      support_plan_fixture(%{service_user_id: su.id, long_term_goal: "長期目標テキスト"})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "表示 利用者"
      assert html =~ "長期目標テキスト"
    end

    test "shows basic info and certificates on the detail page", %{conn: conn} do
      {:ok, su} =
        Ayumi.Plans.create_service_user(%{
          name: "詳細 太郎",
          name_kana: "しょうさい たろう",
          gender: :male,
          phone: "03-1234-5678",
          recipient_cert_number: "R-777",
          disability_certificates: [%{kind: :physical, number: "B-55", grade: "2級"}]
        })

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

      assert html =~ "詳細 太郎"
      assert html =~ "男性"
      assert html =~ "03-1234-5678"
      assert html =~ "R-777"
      assert html =~ "身体障害者手帳"
      assert html =~ "B-55"
      assert html =~ "編集"
    end

    test "detail page shows a fallback when the user has no certificates", %{conn: conn} do
      su = service_user_fixture(%{name: "手帳なし"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

      assert html =~ "手帳なし"
      assert html =~ "登録なし"
      refute html =~ ~s(id="disability-certificates")
    end

    test "navigates to the new support plan form", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}")

      {:ok, _form_lv, html} =
        lv |> element("a", "支援計画を作成") |> render_click() |> follow_redirect(conn)

      assert html =~ "支援計画の作成"
    end

    test "creates a service user with a certificate via the new form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/service_users/new")

      params = %{
        "name" => "新規 太郎",
        "name_kana" => "しんき たろう",
        "disability_certificates" => %{
          "0" => %{"kind" => "physical", "number" => "B-9", "grade" => "2級"}
        }
      }

      {:ok, _show_lv, html} =
        lv
        |> form("#service-user-form", service_user: params)
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "新規 太郎"
      assert html =~ "B-9"
    end

    test "edits a service user via the edit form", %{conn: conn} do
      su = service_user_fixture(%{name: "編集前"})
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

      {:ok, _show_lv, html} =
        lv
        |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "03-9999-0000"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "編集後"
      assert html =~ "03-9999-0000"
    end

    test "saving after a concurrent update shows a stale warning and reloads the latest", %{
      conn: conn
    } do
      su = service_user_fixture(%{name: "編集前", phone: "000"})
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

      # Another staff member updates the same row behind this LiveView's back.
      {:ok, _} = Ayumi.Plans.update_service_user(su, %{phone: "111-concurrent"})

      html =
        lv
        |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "222-mine"})
        |> render_submit()

      # Stayed on the edit form (no redirect), with a stale warning and the latest data.
      assert html =~ "他のスタッフが先にこの利用者を更新しました"
      assert html =~ "service-user-form"
      assert html =~ "111-concurrent"
      refute html =~ "222-mine"
    end

    test "edit form warns when another staff member is editing the same user", %{conn: conn} do
      su = service_user_fixture()
      topic = AyumiWeb.Presence.editing_topic(:service_user, su.id)

      # Subscribe the test process to synchronize on presence broadcasts.
      Phoenix.PubSub.subscribe(Ayumi.PubSub, topic)

      {:ok, lv1, _html} = live(conn, ~p"/service_users/#{su.id}/edit")
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 500
      refute render(lv1) =~ "編集中"

      # A different manager opens the same edit form in a separate session.
      other = manager_fixture(%{name: "別 職員"})
      conn2 = log_in_user(build_conn(), other)
      {:ok, _lv2, _html} = live(conn2, ~p"/service_users/#{su.id}/edit")

      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 500
      assert render(lv1) =~ "別 職員"
      assert render(lv1) =~ "編集中"
    end
  end

  describe "summary sections on show page" do
    setup :register_and_log_in_user

    test "displays deadline section with cert and monitoring status", %{conn: conn} do
      su =
        service_user_fixture(%{
          name: "期限テスト",
          recipient_cert_expiry: Date.add(Date.utc_today(), 10)
        })

      staff = Ayumi.AccountsFixtures.user_fixture()

      support_plan_fixture(%{
        service_user_id: su.id,
        staff_id: staff.id,
        next_monitoring_date: Date.add(Date.utc_today(), -5)
      })

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "期限"
      assert html =~ "超過"
      assert html =~ "近接"
    end

    test "displays current plan goals with latest progress", %{conn: conn} do
      su = service_user_fixture(%{name: "計画テスト"})
      staff = Ayumi.AccountsFixtures.user_fixture()
      plan = support_plan_fixture(%{service_user_id: su.id, staff_id: staff.id})
      goal = goal_fixture(%{support_plan_id: plan.id, description: "毎日出席する"})
      goal_progress_fixture(%{goal_id: goal.id, recorded_by_id: staff.id, stage: :working})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "毎日出席する"
      assert html =~ "取組中"
    end

    test "displays recent goal progress history", %{conn: conn} do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      plan = support_plan_fixture(%{service_user_id: su.id, staff_id: staff.id})
      goal = goal_fixture(%{support_plan_id: plan.id})

      goal_progress_fixture(%{
        goal_id: goal.id,
        recorded_by_id: staff.id,
        stage: :met,
        note: "達成所見"
      })

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "進捗・フェーズ履歴"
      assert html =~ "達成"
      assert html =~ "達成所見"
    end

    test "displays recent support records", %{conn: conn} do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      support_record_fixture(%{service_user_id: su.id, recorded_by: staff, content: "テスト支援記録"})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "支援記録"
      assert html =~ "テスト支援記録"
    end

    test "does not show other service user's data", %{conn: conn} do
      su1 = service_user_fixture(%{name: "利用者A"})
      su2 = service_user_fixture(%{name: "利用者B"})
      staff = Ayumi.AccountsFixtures.user_fixture()
      support_record_fixture(%{service_user_id: su2.id, recorded_by: staff, content: "Bの記録"})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su1.id}")
      refute html =~ "Bの記録"
    end

    test "withdrawn user can still view show page", %{conn: conn} do
      su = service_user_fixture(%{name: "退所テスト", enrollment_status: :withdrawn})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "退所テスト"
    end

    test "shows links to plan details and support records", %{conn: conn} do
      su = service_user_fixture()
      staff = Ayumi.AccountsFixtures.user_fixture()
      plan = support_plan_fixture(%{service_user_id: su.id, staff_id: staff.id})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ ~p"/support_plans/#{plan.id}"
      assert html =~ ~p"/support_records"
    end

    test "show page includes link to attendance record sheet", %{conn: conn} do
      su = service_user_fixture()
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ ~p"/service_users/#{su.id}/attendance"
      assert html =~ "出欠・実績記録票"
    end
  end
end
