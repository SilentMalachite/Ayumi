defmodule AyumiWeb.AttendanceLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures
  alias Ayumi.Plans.AttendanceRecord
  alias Ayumi.Repo

  setup :register_and_log_in_user

  describe "GET /service_users/:id/attendance (general staff)" do
    test "renders the service user name and a row per day of the current month", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      today = Date.utc_today()
      days = Date.days_in_month(Date.new!(today.year, today.month, 1))

      {:ok, view, html} = live(conn, ~p"/service_users/#{su.id}/attendance")

      assert html =~ "山田 太郎"
      assert html =~ "#{today.year}"
      assert html =~ "#{today.month}"

      # one form per day, identified by `phx-submit="save_day"`
      rendered = render(view)

      submit_form_count =
        rendered
        |> String.split(~s|phx-submit="save_day"|)
        |> length()
        |> Kernel.-(1)

      assert submit_form_count == days
    end

    test "renders 28 rows for February 2026 when year/month is given", %{conn: conn} do
      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 2]}")

      assert html =~ "2026"
      assert html =~ "2月"

      form_count =
        html |> String.split(~s|phx-submit="save_day"|) |> length() |> Kernel.-(1)

      assert form_count == 28
    end

    test "prev/next month links cross year boundaries", %{conn: conn} do
      su = service_user_fixture()

      # 2026-01 → prev → 2025-12
      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 1]}")

      view |> element("a", "← 前月") |> render_click()
      assert render(view) =~ "2025"
      assert render(view) =~ "12月"

      # 2026-12 → next → 2027-01
      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 12]}")

      view |> element("a", "翌月 →") |> render_click()
      assert render(view) =~ "2027"
      assert render(view) =~ "1月"
    end

    test "不正な year/month は当月にフォールバックする", %{conn: conn} do
      su = service_user_fixture()
      today = Date.utc_today()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: "bad", month: "13"]}")

      assert html =~ "#{today.year}年#{today.month}月"
    end

    test "renders a print sheet link that preserves year/month", %{conn: conn} do
      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      # current 年月を引き継いだ印刷ページへの遷移リンク
      assert html =~ "/attendance/sheet?"
      assert html =~ "year=2026"
      assert html =~ "month=6"
      assert html =~ "印刷"
    end
  end

  describe "saving a day's record" do
    test "saving as :commute appends a row and increments billable_days", %{conn: conn} do
      su = service_user_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      assert render(view) =~ "利用日数: <strong>0</strong>"

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-10'])", %{
        "date" => "2026-06-10",
        "attendance_record" => %{"provision_type" => "commute"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "保存しました"
      assert html =~ "利用日数: <strong>1</strong>"
    end

    test "second save on the same day supersedes the first (no double count)", %{conn: conn} do
      su = service_user_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-10'])", %{
        "date" => "2026-06-10",
        "attendance_record" => %{"provision_type" => "commute"}
      })
      |> render_submit()

      assert render(view) =~ "利用日数: <strong>1</strong>"

      # correction: same day, absence
      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-10'])", %{
        "date" => "2026-06-10",
        "attendance_record" => %{"provision_type" => "absence"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "利用日数: <strong>0</strong>"
      # the row's select reflects the latest record
      assert html =~ ~s|<option value="absence" selected|
    end

    test "pickup checked is counted; unchecked day stays false", %{conn: conn} do
      su = service_user_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-03'])", %{
        "date" => "2026-06-03",
        "attendance_record" => %{
          "provision_type" => "commute",
          "pickup" => "true"
        }
      })
      |> render_submit()

      assert render(view) =~ "送迎 往: <strong>1</strong>"

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-04'])", %{
        "date" => "2026-06-04",
        "attendance_record" => %{"provision_type" => "commute"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "送迎 往: <strong>1</strong>"
      assert html =~ "送迎 復: <strong>0</strong>"
    end

    test "absence_support increments its own counter, not billable_days", %{conn: conn} do
      su = service_user_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-05'])", %{
        "date" => "2026-06-05",
        "attendance_record" => %{"provision_type" => "absence_support"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "欠席時対応: <strong>1</strong>"
      assert html =~ "利用日数: <strong>0</strong>"
    end

    test "end_time <= start_time shows error flash and does not append a row", %{conn: conn} do
      su = service_user_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      before_count = Repo.aggregate(AttendanceRecord, :count, :id)

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-07'])", %{
        "date" => "2026-06-07",
        "attendance_record" => %{
          "provision_type" => "commute",
          "start_time" => "10:00",
          "end_time" => "10:00"
        }
      })
      |> render_submit()

      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
    end

    test "audit fields submitted by the client are ignored", %{conn: conn, user: user} do
      su = service_user_fixture()
      other = Ayumi.AccountsFixtures.user_fixture()
      injected_at = ~U[2000-01-01 00:00:00Z]

      {:ok, view, _html} =
        live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      # Fire the event directly, simulating a crafted client payload that includes
      # audit fields the server should ignore.
      render_submit(view, "save_day", %{
        "date" => "2026-06-09",
        "attendance_record" => %{
          "provision_type" => "commute",
          "recorded_by_id" => Integer.to_string(other.id),
          "recorded_at" => DateTime.to_iso8601(injected_at)
        }
      })

      [row] = Ayumi.Plans.list_attendance_records(su.id, 2026, 6)
      assert row.recorded_by_id == user.id
      refute row.recorded_at == injected_at
      assert DateTime.diff(DateTime.utc_now(), row.recorded_at, :second) < 30
    end
  end
end
