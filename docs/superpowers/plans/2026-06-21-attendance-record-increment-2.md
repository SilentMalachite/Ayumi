# 実績記録票 増分2 — 出欠入力 LiveView（利用者別 月グリッド）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ある利用者の1か月分の出欠・サービス提供を1画面で表示・入力・訂正できる LiveView を TDD で追加する。表示は増分1の `build_attendance_sheet/3` をそのまま使い、入力・訂正は1日1フォームで `attendance_record` を1行 append する。

**Architecture:** 参照実装は `AyumiWeb.SupportRecordLive.Index` と `AyumiWeb.ServiceUserLive.Show`。LiveView は assign と event handler だけの薄い層に留め、月次の畳み込みは context の `Plans.build_attendance_sheet/3`、検証は `AttendanceRecord.changeset/2` がそれぞれ担当する（既に増分1で実装済み）。保存は `Plans.create_attendance_record/2` を `current_scope` 付きで呼び、`recorded_by_id` / `recorded_at` は context 側の `put_audit` が確定させる（フォームから来た監査値は無視）。

**Tech Stack:** Elixir 1.18 / Phoenix / Phoenix LiveView / Ecto + ecto_sqlite3 / Gettext / ExUnit / Credo / Sobelow / Dialyzer。仕様書: `/Users/hiro/Desktop/ayumi_increment2_attendance_ui.md`。前提増分: `docs/superpowers/plans/2026-06-21-attendance-record-increment-1.md`（マージ済み）。

## Global Constraints

- **Append-only 厳守**：保存は常に 1行 insert。`update`/`delete` を呼ばない。訂正も同日にもう1行追加する。
- **派生値は再計算しない**：合計（利用日数／施設外／送迎／欠席時対応）は `sheet.totals` をそのまま表示し、view 側で数え直さない。
- **検証は changeset 側**：LiveView に独自バリデーションを書かない。エラーは flash で見せ、`AttendanceRecord` 行は増やさない。
- **監査値はサーバ側で確定**：`recorded_by_id` / `recorded_at` は `create_attendance_record/2` 内の `put_audit` が付ける。フォームに混ざってきても無視されること（テストで担保）。
- **`service_user_id` / `service_date` もサーバ側で確定**：クライアント JS に決めさせない。`service_user_id` は URL から、`service_date` は `<input type="hidden" name="date">` から取り、event handler で上書きセットする。
- **全認証スタッフ可**：`live_session :require_authenticated_user` に置く。`:require_manager` にしない（記録系は全スタッフという `CLAUDE.md` の方針）。
- **ユーザー向け文言は `gettext`**：新規 msgid は `mix gettext.extract` で抽出。`.pot` は手編集しない。
- **コード識別子・コメントは英語、UI 文言は日本語**（`CLAUDE.md`）。
- **テストの非同期設定**：LiveView テストは DB を触るので `async: false`（SQLite single-writer）。`use AyumiWeb.ConnCase` がデフォルトで合わせている設定に従う。
- **新規 context 関数を追加しない**：増分1の既存関数（`get_service_user!/1`, `create_attendance_record/2`, `build_attendance_sheet/3`, `ProvisionType.options/0`）で足りる。
- **既存スキーマ・既存集約表示の変更は禁止**：`ServiceUserLive.Show` には導線リンク1本だけを足し、本体集約表示には触らない。
- **スコープ外**：印刷／PDF／CSV、日別ロスター方式（全員×1日）、月一括入力、施設外支援の上限算定。
- **完了条件**：`mix review`（format / warnings-as-errors / Credo / Sobelow / Dialyzer / test）が green。

## File Structure

| ファイル | 役割 | 新規/編集 |
|---|---|---|
| `lib/ayumi_web/live/attendance_live/index.ex` | 月グリッド LiveView（mount / handle_params / `save_day` event / `render`） | 新規 |
| `lib/ayumi_web/router.ex` | `live_session :require_authenticated_user` 内に `/service_users/:service_user_id/attendance` を追加 | 編集 |
| `lib/ayumi_web/live/service_user_live/show.ex` | 「出欠・実績記録票」への導線リンクを1本追加（本体集約表示は無変更） | 編集 |
| `priv/gettext/default.pot` | 新規 msgid を `mix gettext.extract` で反映（手編集禁止） | 自動編集 |
| `priv/gettext/ja/LC_MESSAGES/default.po` | 日本語訳の追記（`mix gettext.merge` 後に必要なら手追加） | 編集 |
| `test/ayumi_web/live/attendance_live_test.exs` | アクセス／表示／ナビ／保存／訂正／送迎／欠席時対応／不正入力／監査改ざんの 9 系統テスト | 新規 |

---

## Task 1: ルート＋骨格 LiveView（アクセス・当月グリッド表示）

このタスクは「URL を踏むと当月の月グリッドが描画される」までを通す。保存はまだ実装しない。

**Files:**
- Modify: `lib/ayumi_web/router.ex`
- Create: `lib/ayumi_web/live/attendance_live/index.ex`
- Create: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes:
  - `Ayumi.Plans.get_service_user!/1`(既存)
  - `Ayumi.Plans.build_attendance_sheet/3`(増分1)
  - `Ayumi.Plans.AttendanceSheet`(増分1)
  - `Ayumi.Plans.ProvisionType.options/0`(増分1)
  - `AyumiWeb.ConnCase` ヘルパ `register_and_log_in_user/1`(既存 setup)
  - `Ayumi.PlansFixtures.service_user_fixture/0|1`(既存)
- Produces:
  - Route: `live "/service_users/:service_user_id/attendance", AttendanceLive.Index, :index` — `live_session :require_authenticated_user` 内
  - Module: `AyumiWeb.AttendanceLive.Index`(`use AyumiWeb, :live_view`)
  - Mount は `socket.assigns` に `:service_user`, `:provision_options` を入れる
  - `handle_params/3` は `:year`, `:month`, `:sheet`, `:page_title` を入れる

- [ ] **Step 1: 失敗するテストを書く(アクセス可・当月表示・末日数一致)**

新規作成 `test/ayumi_web/live/attendance_live_test.exs`:

```elixir
defmodule AyumiWeb.AttendanceLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

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
  end
end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: `(UndefinedFunctionError) function AyumiWeb.Router.Helpers...` か `no route found for GET /service_users/...` で失敗。

- [ ] **Step 3: ルート追加**

`lib/ayumi_web/router.ex` の `live_session :require_authenticated_user` ブロック内(`/support_records` などと同じ並び)に1行追加:

```elixir
      live "/service_users/:service_user_id/attendance", AttendanceLive.Index, :index
```

> NOTE: `/service_users/:id` とは末尾セグメント `/attendance` で区別されるため衝突しない。manager 限定ブロックに置かないこと。

- [ ] **Step 4: 骨格 LiveView を作成**

新規作成 `lib/ayumi_web/live/attendance_live/index.ex`:

```elixir
defmodule AyumiWeb.AttendanceLive.Index do
  @moduledoc "利用者別・1か月分の出欠/実績記録票(表示・入力・訂正)。"
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.ProvisionType

  @impl true
  def mount(%{"service_user_id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)

    {:ok,
     socket
     |> assign(:service_user, service_user)
     |> assign(:provision_options, [{gettext("（未選択）"), ""} | ProvisionType.options()])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {year, month} = parse_year_month(params)
    sheet = Plans.build_attendance_sheet(socket.assigns.service_user.id, year, month)

    {:noreply,
     socket
     |> assign(:year, year)
     |> assign(:month, month)
     |> assign(:sheet, sheet)
     |> assign(:page_title, gettext("実績記録票 %{y}年%{m}月", y: year, m: month))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("実績記録票")}
        <:subtitle>
          {@service_user.name} — {gettext("%{y}年%{m}月", y: @year, m: @month)}
        </:subtitle>
        <:actions>
          <.link patch={month_path(@service_user, prev_month(@year, @month))} class="btn btn-ghost btn-sm">
            {gettext("← 前月")}
          </.link>
          <.link patch={month_path(@service_user, next_month(@year, @month))} class="btn btn-ghost btn-sm">
            {gettext("翌月 →")}
          </.link>
          <.link navigate={~p"/service_users/#{@service_user.id}"} class="btn btn-ghost btn-sm">
            {gettext("利用者詳細へ戻る")}
          </.link>
        </:actions>
      </.header>

      <section class="my-4 grid grid-cols-2 sm:grid-cols-5 gap-2 text-sm">
        <div>{gettext("利用日数")}: <strong>{@sheet.totals.billable_days}</strong></div>
        <div>{gettext("うち施設外")}: <strong>{@sheet.totals.offsite_days}</strong></div>
        <div>{gettext("送迎 往")}: <strong>{@sheet.totals.pickup_count}</strong></div>
        <div>{gettext("送迎 復")}: <strong>{@sheet.totals.dropoff_count}</strong></div>
        <div>{gettext("欠席時対応")}: <strong>{@sheet.totals.absence_support_count}</strong></div>
      </section>

      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th>{gettext("日")}</th>
            <th>{gettext("曜")}</th>
            <th>{gettext("提供形態")}</th>
            <th>{gettext("送迎 往")}</th>
            <th>{gettext("送迎 復")}</th>
            <th>{gettext("開始")}</th>
            <th>{gettext("終了")}</th>
            <th>{gettext("備考")}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @sheet.lines} class={row_class(line.date)}>
            <td>{line.date.day}</td>
            <td>{weekday_label(line.date)}</td>
            <td colspan="7">
              <form phx-submit="save_day" class="flex flex-wrap gap-2 items-center">
                <input type="hidden" name="date" value={Date.to_iso8601(line.date)} />
                <select name="attendance_record[provision_type]" class="select select-bordered select-sm">
                  <%= for {label, value} <- @provision_options do %>
                    <option value={value} selected={selected_provision?(line, value)}>{label}</option>
                  <% end %>
                </select>
                <label class="label cursor-pointer gap-1">
                  <input type="hidden" name="attendance_record[pickup]" value="false" />
                  <input type="checkbox" name="attendance_record[pickup]" value="true" checked={checked?(line, :pickup)} class="checkbox checkbox-sm" />
                  <span class="label-text">{gettext("往")}</span>
                </label>
                <label class="label cursor-pointer gap-1">
                  <input type="hidden" name="attendance_record[dropoff]" value="false" />
                  <input type="checkbox" name="attendance_record[dropoff]" value="true" checked={checked?(line, :dropoff)} class="checkbox checkbox-sm" />
                  <span class="label-text">{gettext("復")}</span>
                </label>
                <input type="time" name="attendance_record[start_time]" value={time_value(line, :start_time)} class="input input-bordered input-sm w-28" />
                <input type="time" name="attendance_record[end_time]" value={time_value(line, :end_time)} class="input input-bordered input-sm w-28" />
                <input type="text" name="attendance_record[note]" value={note_value(line)} placeholder={gettext("備考")} class="input input-bordered input-sm flex-1 min-w-32" />
                <button type="submit" class="btn btn-primary btn-sm">{gettext("保存")}</button>
              </form>
            </td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_day", _params, socket) do
    # Implemented in Task 3; for now, simply ignore the event so the page renders.
    {:noreply, socket}
  end

  # --- helpers ---

  defp parse_year_month(params) do
    today = Date.utc_today()
    year = parse_int(params["year"], today.year)
    month = parse_int(params["month"], today.month)
    if month in 1..12, do: {year, month}, else: {today.year, today.month}
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}
  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp month_path(service_user, {year, month}) do
    ~p"/service_users/#{service_user.id}/attendance?#{[year: year, month: month]}"
  end

  # Sunday=1 … Saturday=7
  defp weekday_label(%Date{} = d) do
    elem({"日", "月", "火", "水", "木", "金", "土"}, Date.day_of_week(d, :sunday) - 1)
  end

  defp row_class(%Date{} = d) do
    case Date.day_of_week(d, :sunday) do
      1 -> "bg-base-200/50"
      7 -> "bg-base-200/50"
      _ -> ""
    end
  end

  defp selected_provision?(%{record: nil}, value), do: value == ""
  defp selected_provision?(%{record: rec}, value), do: to_string(rec.provision_type) == to_string(value)

  defp checked?(%{record: nil}, _field), do: false
  defp checked?(%{record: rec}, field), do: Map.get(rec, field) == true

  defp time_value(%{record: nil}, _field), do: ""
  defp time_value(%{record: rec}, field) do
    case Map.get(rec, field) do
      %Time{} = t -> Time.to_iso8601(t)
      _ -> ""
    end
  end

  defp note_value(%{record: nil}), do: ""
  defp note_value(%{record: rec}), do: rec.note || ""
end
```

> NOTE: `Date.day_of_week/2` の `:sunday` 起点が使えない古い Elixir なら `Date.day_of_week/1`(月曜=1)に切り替え、`weekday_label/1` のタプル順を「月火水木金土日」にする。`CLAUDE.md` の必要 Elixir 版(1.18)では `:sunday` が使えるのでこのままで良い。

- [ ] **Step 5: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 1 test, 0 failures。

- [ ] **Step 6: コミット**

```bash
git add lib/ayumi_web/router.ex lib/ayumi_web/live/attendance_live/index.ex test/ayumi_web/live/attendance_live_test.exs
git commit -m "feat: add AttendanceLive.Index skeleton with monthly grid"
```

---

## Task 2: 指定年月の表示と前月・翌月ナビ(年跨ぎ含む)

`?year=YYYY&month=MM` を踏むとその月になり、前月リンク／翌月リンクの patch でも年跨ぎ込みで遷移できることを担保する。

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes: Task 1 のすべて
- Produces: なし(仕様の確定のみ)

- [ ] **Step 1: 失敗するテストを追加**

`attendance_live_test.exs` の `describe "GET /service_users/:id/attendance (general staff)"` の末尾 `end` の直前に追加:

```elixir
    test "renders 28 rows for February 2026 when year/month is given", %{conn: conn} do
      su = service_user_fixture()
      {:ok, _view, html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 2]}")

      assert html =~ "2026"
      assert html =~ "2月"
      form_count =
        html |> String.split(~s|phx-submit="save_day"|) |> length() |> Kernel.-(1)

      assert form_count == 28
    end

    test "prev/next month links cross year boundaries", %{conn: conn} do
      su = service_user_fixture()

      # 2026-01 → prev → 2025-12
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 1]}")
      view |> element("a", "← 前月") |> render_click()
      assert render(view) =~ "2025"
      assert render(view) =~ "12月"

      # 2026-12 → next → 2027-01
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 12]}")
      view |> element("a", "翌月 →") |> render_click()
      assert render(view) =~ "2027"
      assert render(view) =~ "1月"
    end
```

- [ ] **Step 2: テスト実行で green を確認(実装は Task 1 で完成済み)**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 3 tests, 0 failures。

> NOTE: Task 1 の `parse_year_month/1` + `prev_month/2` + `next_month/2` + `month_path/2` がそのまま満たすため、新規実装は不要。万一落ちたら Task 1 の helpers を見直す。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_live_test.exs
git commit -m "test: assert specific month rendering and year-boundary navigation"
```

---

## Task 3: 1日分の保存ハンドラ(append-only insert)

「ある日を `commute` で保存 → その日の行に反映、利用日数が +1」を通す。`handle_event("save_day", …)` を本実装に差し替える。

**Files:**
- Modify: `lib/ayumi_web/live/attendance_live/index.ex`
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes:
  - `Ayumi.Plans.create_attendance_record/2`(増分1)
  - `Ayumi.Plans.build_attendance_sheet/3`(増分1)
- Produces:
  - `handle_event("save_day", %{"date" => String.t(), "attendance_record" => map()}, socket)` — `{:ok, _}` で flash + sheet 再集計、`{:error, cs}` で flash のみ

- [ ] **Step 1: 失敗するテストを追加**

`describe "GET /service_users/:id/attendance (general staff)"` の末尾の直後(`describe "saving a day's record"` を新設)に追加:

```elixir
  describe "saving a day's record" do
    test "saving as :commute appends a row and increments billable_days", %{conn: conn} do
      su = service_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

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
  end
```

> NOTE: `form/3` の selector はその日のフォームを一意に指す。複数の `form[phx-submit='save_day']` があるので `:has(input[value='2026-06-10'])` で限定する。

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 「`利用日数: <strong>0</strong>`」のままで失敗(Task 1 の handler が `{:noreply, socket}` を返すだけのため)。

- [ ] **Step 3: `handle_event("save_day", …)` を本実装に差し替える**

`lib/ayumi_web/live/attendance_live/index.ex` の `handle_event("save_day", _params, socket)` を以下に置換:

```elixir
  @impl true
  def handle_event("save_day", %{"date" => date_str, "attendance_record" => attrs}, socket) do
    su = socket.assigns.service_user

    attrs =
      attrs
      |> Map.put("service_user_id", su.id)
      |> Map.put("service_date", date_str)

    case Plans.create_attendance_record(socket.assigns.current_scope, attrs) do
      {:ok, _record} ->
        sheet = Plans.build_attendance_sheet(su.id, socket.assigns.year, socket.assigns.month)

        {:noreply,
         socket
         |> put_flash(:info, gettext("%{d} の記録を保存しました", d: date_str))
         |> assign(:sheet, sheet)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, first_error_message(changeset))}
    end
  end

  defp first_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
    |> List.first()
    |> Kernel.||(gettext("保存できませんでした"))
  end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 4 tests, 0 failures。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi_web/live/attendance_live/index.ex test/ayumi_web/live/attendance_live_test.exs
git commit -m "feat: append attendance record on save_day event"
```

---

## Task 4: 訂正＝最新採用・二重計上しない

「同じ日をもう一度 `absence` で保存 → 表示は `absence`、利用日数は元に戻る」。増分1の「同日は最新行(id 最大)」が効くことの統合確認。

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes: Task 3 のすべて
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "saving a day's record"` の中、最初のテストの直後に追加:

```elixir
    test "second save on the same day supersedes the first (no double count)", %{conn: conn} do
      su = service_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

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
```

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 5 tests, 0 failures(増分1の最新行採用ロジックが既に効くため、追加実装は不要)。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_live_test.exs
git commit -m "test: assert correction supersedes prior row on the same day"
```

---

## Task 5: 送迎・欠席時対応のチェックボックス計上

「`pickup` にチェック → 送迎往 +1」「未チェックは false が入る」「`absence_support` で保存 → 欠席時対応 +1、利用日数には入らない」。

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes: Task 3 のすべて
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "saving a day's record"` の末尾 `end` の直前に追加:

```elixir
    test "pickup checked is counted; unchecked day stays false", %{conn: conn} do
      su = service_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

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
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

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
```

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 7 tests, 0 failures。

> NOTE: render 側で `<input type="hidden" name="attendance_record[pickup]" value="false" />` を checkbox の前に置いてあるため、未チェック時も `false` が POST される。changeset の `:boolean` cast がこれを処理する。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_live_test.exs
git commit -m "test: assert pickup/dropoff and absence_support are counted independently"
```

---

## Task 6: 不正入力でエラー flash・行が増えない

「終了 ≦ 開始 で保存 → エラー flash、`AttendanceRecord` 件数不変」。

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes: Task 3 のすべて、`Ayumi.Plans.AttendanceRecord`(件数計測のため)、`Ayumi.Repo`
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

ファイル冒頭 `import Ayumi.PlansFixtures` の直後に以下を追加:

```elixir
  alias Ayumi.Plans.AttendanceRecord
  alias Ayumi.Repo
  import Ecto.Query, only: [from: 2]
```

`describe "saving a day's record"` の末尾 `end` の直前に追加:

```elixir
    test "end_time <= start_time shows error flash and does not append a row", %{conn: conn} do
      su = service_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      before_count = Repo.aggregate(from(r in AttendanceRecord), :count, :id)

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
      assert Repo.aggregate(from(r in AttendanceRecord), :count, :id) == before_count
    end
```

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 8 tests, 0 failures。`first_error_message/1` が `end_time` の changeset エラーを flash 化する。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_live_test.exs
git commit -m "test: end_time <= start_time triggers error flash, no row appended"
```

---

## Task 7: 監査フィールドの改ざんは無視される

「フォームに `recorded_by_id` / `recorded_at` を混ぜても、保存後の行はログイン中ユーザの id と現在時刻になる」。`SupportRecordLiveTest` と同型。

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs`

**Interfaces:**
- Consumes: Task 3 のすべて、`Ayumi.Plans.list_attendance_records/3`、`Ayumi.AccountsFixtures.user_fixture/0`(または同等のヘルパ)
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "saving a day's record"` の末尾 `end` の直前に追加:

```elixir
    test "audit fields submitted by the client are ignored", %{conn: conn, user: user} do
      su = service_user_fixture()
      other = Ayumi.AccountsFixtures.user_fixture()
      injected_at = ~U[2000-01-01 00:00:00Z]

      {:ok, view, _html} = live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-09'])", %{
        "date" => "2026-06-09",
        "attendance_record" => %{
          "provision_type" => "commute",
          "recorded_by_id" => Integer.to_string(other.id),
          "recorded_at" => DateTime.to_iso8601(injected_at)
        }
      })
      |> render_submit()

      [row] = Ayumi.Plans.list_attendance_records(su.id, 2026, 6)
      assert row.recorded_by_id == user.id
      refute row.recorded_at == injected_at
      assert DateTime.diff(DateTime.utc_now(), row.recorded_at, :second) < 30
    end
```

> NOTE: `Ayumi.AccountsFixtures.user_fixture/0` が「別ユーザを作る」のに使える。なければ `test/support/fixtures/accounts_fixtures.ex` を確認して同等のヘルパに置き換えること。

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 9 tests, 0 failures。`AttendanceRecord.changeset/2` の `cast` 対象が `@user_fields` に限定されていて `recorded_by_id` / `recorded_at` を弾くため、また `put_audit` が確定値で上書きするため。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_live_test.exs
git commit -m "test: audit fields from the form are ignored"
```

---

## Task 8: 利用者詳細からの導線リンク(最小追加)

`ServiceUserLive.Show` に「出欠・実績記録票」へのリンクを1つ足す。**既存集約表示は変更しない。**

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/show.ex`
- Modify: `test/ayumi_web/live/service_user_live_test.exs`(既存)

**Interfaces:**
- Consumes: Task 1 で定義した route `~p"/service_users/#{su.id}/attendance"`
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加(show に導線があること)**

`test/ayumi_web/live/service_user_live_test.exs` 内の `describe "Show"`(既存名は実ファイルで確認して合わせる)に追加:

```elixir
    test "renders a link to the attendance sheet", %{conn: conn} do
      su = service_user_fixture()
      {:ok, _view, html} = live(conn, ~p"/service_users/#{su.id}")

      assert html =~ ~s|href="/service_users/#{su.id}/attendance"|
      assert html =~ "出欠・実績記録票"
    end
```

> NOTE: 既存ファイルの setup ヘルパ(`register_and_log_in_user` 等)と alias / import 構成に合わせる。

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi_web/live/service_user_live_test.exs
```
Expected: `href="/service_users/.../attendance"` が見つからずに失敗。

- [ ] **Step 3: 導線リンクを追加(最小差分)**

`lib/ayumi_web/live/service_user_live/show.ex` の `render/1` 内、ヘッダの `:actions` か近い既存リンク群の中に、1行だけ追加:

```elixir
      <.link navigate={~p"/service_users/#{@service_user.id}/attendance"} class="btn btn-ghost btn-sm">
        {gettext("出欠・実績記録票")}
      </.link>
```

> 既存の他リンク(編集／詳細など)と同じ並びに置く。本体集約表示(バッジ・進捗・記録一覧)は変更しない。

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/service_user_live_test.exs
```
Expected: 既存 + 1 で全部 pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi_web/live/service_user_live/show.ex test/ayumi_web/live/service_user_live_test.exs
git commit -m "feat: link to attendance sheet from service user show page"
```

---

## Task 9: gettext 抽出と `mix review` 完走

新規 msgid を `.pot` / `.po` に反映し、品質ゲートを通す。

**Files:**
- Modify: `priv/gettext/default.pot`(`mix gettext.extract` で自動更新)
- Modify: `priv/gettext/ja/LC_MESSAGES/default.po`(`mix gettext.merge` 後、必要なら手で日本語訳を埋める)

**Interfaces:** なし

- [ ] **Step 1: msgid を抽出してマージ**

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```
Expected: `default.pot` と `ja/LC_MESSAGES/default.po` に新規 msgid が追加される。`.pot` を手編集しないこと。

- [ ] **Step 2: `ja/LC_MESSAGES/default.po` の空 `msgstr ""` を埋める**

新規追加された msgid(例: `"実績記録票"`, `"出欠・実績記録票"`, `"%{y}年%{m}月"` など)の `msgstr` がそのまま日本語で良ければ msgid と同じ文字列を入れる(msgid が日本語のため)。既存運用に合わせること。

- [ ] **Step 3: 全テストを実行**

```bash
mix test
```
Expected: 全 green。

- [ ] **Step 4: `mix review` を通す**

```bash
mix review
```
Expected: format check OK / compile warnings-as-errors OK / Credo OK / Sobelow OK / Dialyzer OK / `mix test` 全 green。

- [ ] **Step 5: 失敗があれば最小差分で修正(fix 専用の小さなコミットに分ける)**

例:
- format: `mix format` → `git commit -m "chore: format attendance live files"`
- credo: 該当箇所を最小差分で修正 → `git commit -m "chore: appease credo for attendance live"`
- dialyzer: `@spec` 不足や型不整合を解消 → `git commit -m "chore: tighten attendance live typespecs"`

- [ ] **Step 6: 変更ファイル一覧と「なぜ」を1行ずつ報告**

報告フォーマット:
- `lib/ayumi_web/router.ex` — `/service_users/:service_user_id/attendance` を全認証スタッフ向けに追加(記録系=全スタッフの方針)
- `lib/ayumi_web/live/attendance_live/index.ex` — 月グリッド LiveView(表示は `build_attendance_sheet/3` 再利用、保存は `create_attendance_record/2` で append、検証は changeset 任せ)
- `lib/ayumi_web/live/service_user_live/show.ex` — 出欠画面への導線リンクを1つ追加(本体は無変更)
- `test/ayumi_web/live/attendance_live_test.exs` — 9系統(アクセス／表示／指定年月／ナビ／保存／訂正／送迎・欠席時対応／不正入力／監査改ざん無視)
- `test/ayumi_web/live/service_user_live_test.exs` — 導線リンク存在 1 ケース追加
- `priv/gettext/default.pot` / `priv/gettext/ja/LC_MESSAGES/default.po` — 新規 msgid を抽出・マージ

「気づいた将来課題(実装しない／列挙のみ)」も合わせて報告:
- 増分3: 印刷／PDF／CSV 出力
- 日別ロスター方式(全員×1日)・月一括入力
- 行ごとのインライン・エラー表示(現状は flash 単一メッセージ)
- 施設外支援の日数上限の見せ方(強制しない／注意喚起)
- 削除や時刻入力 UX の整備
- 出欠を manager 限定にする運用判断(その場合は `:require_manager` ブロックへルートを移すだけ)

- [ ] **Step 7: スコープ外チェック**

以下が**入っていない**ことを確認:
- 印刷／PDF／CSV 出力なし
- 日別ロスター方式・月一括入力なし
- `Plans` context への新規関数追加なし
- 既存スキーマの変更なし
- `ServiceUserLive.Show` の本体集約表示の変更なし
- 報酬単価・加算上限のロジックなし

---

## Self-Review チェックリスト(実装者が最後に通す)

- [ ] 仕様書「ゴール」「権限・配置」「既存パターンに合わせる」「作る／触るファイル」「書くテスト」「完了条件」がすべて File Structure / Tasks に対応している
- [ ] 仕様書「書くテスト」の各 bullet が以下のいずれかでカバーされている
  - アクセス → Task 1
  - 当月表示・末日数一致 → Task 1
  - 指定年月(2月=28/29日) → Task 2
  - 前月・翌月(年跨ぎ) → Task 2
  - 保存＝追記(commute → 利用日数+1) → Task 3
  - 訂正＝最新採用・二重計上しない → Task 4
  - 送迎(pickup チェックで送迎往+1／未チェックは false) → Task 5
  - 欠席時対応(+1、利用日数には入らない) → Task 5
  - 不正入力(終了≦開始でエラー flash、行が増えない) → Task 6
  - 監査の改ざん無視 → Task 7
- [ ] LiveView は assign と event handler だけ、ロジックは context 委譲
- [ ] 派生値(合計)を view で再計算していない
- [ ] route が `:require_authenticated_user` ブロックにあり、`:require_manager` にない
- [ ] `service_user_id` / `service_date` をサーバ側で確定している(クライアントから来た値を信用していない)
- [ ] checkbox 未チェック時に false が POST される構造になっている(hidden companion)
- [ ] gettext は `extract`/`merge` で反映し、`.pot` を手編集していない
- [ ] `ServiceUserLive.Show` の本体集約表示を変更していない(リンク1本のみ)
- [ ] 印刷・PDF・CSV・日別ロスター・月一括入力の実装が**ない**

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-21-attendance-record-increment-2.md`. 実装に進む際の選択肢:

1. **Subagent-Driven(推奨)** — Task ごとに新しい subagent を起動し、間にレビューを挟む。`superpowers:subagent-driven-development` を使う。
2. **Inline Execution** — このセッションで `superpowers:executing-plans` を使い、チェックポイントで止めながらバッチ実行する。

どちらで進めますか？
