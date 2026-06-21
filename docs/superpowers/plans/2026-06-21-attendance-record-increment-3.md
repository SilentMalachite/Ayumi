# 実績記録票 増分3 — 印刷ビュー (HTML / A4 最適化) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ある利用者の1か月分を、「サービス提供実績記録票」としてブラウザで印刷できる HTML ページ (`AttendanceLive.Sheet`) を TDD で追加する。算定は増分1の `Plans.build_attendance_sheet/3` をそのまま使い、画面側で数え直さない。同時に繰り越し Minor「`ProvisionType.offsite/0` ヘルパー化」と `Plans.totals_from/1` の参照差し替えを片付け、施設外の定義を一元化する。

**Architecture:** LiveView は `mount/3` と `handle_params/3` だけの薄い表示層に留め、月次集計はすべて context (`Plans.build_attendance_sheet/3` → `%AttendanceSheet{}`) に委譲する。事業所情報はスキーマを増やさず application config (`:ayumi, :facility`) から読み、未設定なら空文字 (手書き欄) で描画する。年月パラメータ解釈 (`parse_year_month/1`, `parse_int/2`) は増分2の `AttendanceLive.Index` と本タスクの `Sheet` の両方で必要なので `AyumiWeb.AttendanceLive.MonthParams` に1つだけ切り出し、Index 側の private を削除して共有版に差し替える (重複を避ける正当な DRY)。印刷最適化は Tailwind の `print:` ユーティリティと小さな `<style>` ブロック内の `@page` のみで完結し、PDF 生成器や外部依存は一切足さない。

**Tech Stack:** Elixir 1.18 / Phoenix / Phoenix LiveView / Ecto + ecto_sqlite3 / Tailwind (`print:` ユーティリティ) / Gettext / ExUnit / Credo / Sobelow / Dialyzer。仕様書: `/Users/hiro/Desktop/ayumi_increment3_attendance_print.md`。前提増分: `docs/superpowers/plans/2026-06-21-attendance-record-increment-1.md` と `docs/superpowers/plans/2026-06-21-attendance-record-increment-2.md` (両方マージ済み)。

## Global Constraints

- **派生値は再計算しない**：合計 (利用日数／施設外／送迎往・復／欠席時対応) は `sheet.totals` をそのまま表示し、view 側で `Enum.count` / `Enum.sum` を呼ばない。
- **append-only 厳守**：本増分は表示のみ。`update`/`delete`/再計算ループを書かない。`build_attendance_sheet/3` の出力をそのまま渡す。
- **PDF 生成器・外部依存を足さない**：HTML + `@media print` で完結させる。`puppeteer` / `wkhtmltopdf` / Chromium 系のサーバ実行は禁止。オフライン/LAN 専用の方針を守る。
- **新規 context 関数を追加しない**：`Plans.get_service_user!/1`, `Plans.build_attendance_sheet/3`, `Ayumi.Plans.ProvisionType` (`label/1`, `billable/0`, **新規 `offsite/0`**) で足りる。
- **既存スキーマを変更しない**：`service_user` 等に列を足さない。事業所名・事業所番号は config で持つ。
- **全認証スタッフ可**：route は `live_session :require_authenticated_user` 内に置く。`:require_manager` にしない (記録系=全スタッフという `CLAUDE.md` の方針)。
- **白黒印刷で成立させる**：色で情報を持たせず ○/× と罫線で表現する。`-webkit-print-color-adjust: exact;` に依存しない。
- **A4 ページサイズ**：ページ内の `<style>` に `@page { size: A4; margin: 12mm; }` を1ブロックだけ置く (Tailwind では `@page` を書けない)。
- **画面操作部は `print:hidden`**：印刷ボタン・前月/翌月リンクは Tailwind の `print:hidden` で印刷時に消す。CSP で inline JS が弾かれる場合のみ `phx-hook` に切り替え、その旨を報告する。
- **ユーザー向け文言は `gettext`**：新規 msgid は `mix gettext.extract` で抽出する。`.pot` は手編集しない。
- **コード識別子・コメントは英語、UI 文言は日本語** (`CLAUDE.md`)。
- **テストの非同期設定**：LiveView テストは DB を触るので `async: false` (SQLite single-writer)。`use AyumiWeb.ConnCase` のデフォルト設定に従う。
- **増分2 Index の入力ロジックを変更しない**：年月パラメータ共有モジュールへの差し替えのみ可。`save_day` ハンドラ、render の入力フォーム、合計セクションには触らない。
- **印刷専用 CSS (`@page` / `print:hidden`) のユニットテストはしない**：ブラウザ印刷プレビューでの目視確認を完了条件のチェックリストに含める。
- **スコープ外**：CSV 出力、サーバ側 PDF 生成・外部依存、日別ロスター入力、月一括入力、報酬単価・加算上限の算定、行ごとインライン・エラー表示、欠席時対応/施設外支援の上限の見せ方、出欠の manager 限定化、README / CLAUDE.md / CHANGELOG の更新 (別パスでまとめて行う運用)。
- **完了条件**：`mix review` (format / warnings-as-errors / Credo / Sobelow / Dialyzer / test) が green、かつ増分1・2の既存テストも green のまま。

## File Structure

| ファイル | 役割 | 新規/編集 |
|---|---|---|
| `lib/ayumi/plans/provision_type.ex` | `offsite/0` ヘルパー追加 (`[:offsite_work, :offsite_support]`) | 編集 |
| `lib/ayumi/plans.ex` | `totals_from/1` 内の `offsite = [...]` リテラルを `ProvisionType.offsite()` に差し替え (数値挙動は不変) | 編集 |
| `lib/ayumi_web/live/attendance_live/month_params.ex` | 出欠系 LiveView 共通の年月パラメータ解釈 (`parse/1`) | 新規 |
| `lib/ayumi_web/live/attendance_live/index.ex` | `parse_year_month/1` / `parse_int/2` を削除し `MonthParams.parse/1` を呼ぶ (最小差分) | 編集 |
| `lib/ayumi_web/live/attendance_live/sheet.ex` | 印刷用 LiveView (mount/handle_params/render)。様式ヘッダ + 明細 + 合計 + 印刷 CSS | 新規 |
| `lib/ayumi_web/router.ex` | `live_session :require_authenticated_user` 内に `/service_users/:service_user_id/attendance/sheet` を追加 | 編集 |
| `config/config.exs` | 事業所情報のひな型コメント (`# config :ayumi, :facility, name: "（事業所名）", number: "（事業所番号）"`) | 編集 |
| `test/ayumi/plans/enumerations_test.exs` | `ProvisionType.offsite/0` のテスト追記 | 編集 |
| `test/ayumi/plans_test.exs` | `offsite_days` が施設外2種の合計になる回帰テスト1件 (既存が green なら追加のみ) | 編集 |
| `test/ayumi_web/live/attendance_sheet_live_test.exs` | アクセス／ヘッダ／明細／欠席時対応／合計一致／訂正反映の 6 系統テスト | 新規 |
| `test/ayumi_web/live/attendance_live_test.exs` | Index → Sheet 印刷リンクの存在テスト1ケース追加 | 編集 |
| `priv/gettext/default.pot` | 新規 msgid を `mix gettext.extract` で反映 (手編集禁止) | 自動編集 |
| `priv/gettext/ja/LC_MESSAGES/default.po` | 日本語訳の追記 (`mix gettext.merge` 後に必要なら手追加) | 編集 |

---

## Task 1: ProvisionType.offsite/0 ヘルパー追加 (繰り越し Minor 1/2)

施設外 (`:offsite_work` + `:offsite_support`) の定義を `ProvisionType` に集約する。テストを先に書いて緑になれば、列挙の責務がモジュールに揃ったことになる。

**Files:**
- Modify: `lib/ayumi/plans/provision_type.ex`
- Modify: `test/ayumi/plans/enumerations_test.exs`

**Interfaces:**
- Consumes: なし (純粋関数の追加)
- Produces:
  - `Ayumi.Plans.ProvisionType.offsite/0 :: [atom()]` returning `[:offsite_work, :offsite_support]`

- [ ] **Step 1: 失敗するテストを追加**

`test/ayumi/plans/enumerations_test.exs` の `describe "ProvisionType"` ブロック内、`billable/0` のテストの直後に追加:

```elixir
    test "offsite/0 lists only offsite_work / offsite_support" do
      assert ProvisionType.offsite() == [:offsite_work, :offsite_support]
    end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/enumerations_test.exs
```
Expected: `UndefinedFunctionError: function Ayumi.Plans.ProvisionType.offsite/0 is undefined` で失敗。

- [ ] **Step 3: `offsite/0` を追加**

`lib/ayumi/plans/provision_type.ex` の `billable/0` の直後に追加:

```elixir
  @doc "施設外 (就労・支援) の提供形態。記録票で別掲・集計の定義を一元化する。"
  def offsite, do: [:offsite_work, :offsite_support]
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/enumerations_test.exs
```
Expected: 全 pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans/provision_type.ex test/ayumi/plans/enumerations_test.exs
git commit -m "feat: add ProvisionType.offsite/0 helper"
```

---

## Task 2: Plans.totals_from/1 を offsite/0 経由に差し替え (繰り越し Minor 2/2)

`Plans.totals_from/1` 内のローカル `offsite = [:offsite_work, :offsite_support]` を `ProvisionType.offsite()` 呼び出しに置き換える。**数値挙動は不変**、増分1の既存テストが green のままであることをもって回帰確認とする。

**Files:**
- Modify: `lib/ayumi/plans.ex` (`totals_from/1` 内 1 行のみ)
- Modify: `test/ayumi/plans_test.exs` (`offsite_days` の回帰テスト1件を追加)

**Interfaces:**
- Consumes: Task 1 の `ProvisionType.offsite/0`
- Produces: なし (挙動互換)

- [ ] **Step 1: 回帰用の失敗するテストを追加 (既存にない場合)**

まず `test/ayumi/plans_test.exs` を開き、`offsite_days` が施設外2種の合計になることを直接アサートするテストが既にあるかを `grep`:

```bash
grep -n "offsite_days" test/ayumi/plans_test.exs
```

存在しなければ、`describe "build_attendance_sheet/3"` (既存ブロック名は実ファイルで確認して合わせる) に追加:

```elixir
    test "totals.offsite_days counts offsite_work + offsite_support via ProvisionType.offsite/0" do
      su = service_user_fixture()
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-02], provision_type: :offsite_work})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-03], provision_type: :offsite_support})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-04], provision_type: :commute})

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)

      assert sheet.totals.offsite_days == 2
      # commute は施設外には数えないが billable には数える
      assert sheet.totals.billable_days == 3
    end
```

> NOTE: 既存に同等のテストがあるなら本 Step はスキップして良い。その旨を Step 5 のコミットメッセージに残す。

- [ ] **Step 2: テスト実行 — 既存実装 (リテラル `[:offsite_work, :offsite_support]`) で既に green になるはず**

```bash
mix test test/ayumi/plans_test.exs
```
Expected: 全 pass。既存実装でも数値は同じなので、まずここで回帰の基準線を取る。

- [ ] **Step 3: `totals_from/1` を差し替え**

`lib/ayumi/plans.ex` の `totals_from/1` 内、ローカル変数 `offsite = [:offsite_work, :offsite_support]` の行を以下に置換:

```elixir
    offsite = ProvisionType.offsite()
```

> NOTE: `ProvisionType` の alias は既に `Plans` モジュール冒頭で `alias Ayumi.Plans.ProvisionType` 済み (増分1)。確認しておくこと。なければ追加する (1行の差分)。

- [ ] **Step 4: テスト再実行で green を維持**

```bash
mix test test/ayumi/plans_test.exs
```
Expected: 数値が変わらず全 pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans_test.exs
git commit -m "refactor: route totals_from offsite_days through ProvisionType.offsite/0"
```

---

## Task 3: AttendanceLive.MonthParams 共通モジュール抽出と Index 側の差し替え

増分2 Index の private な `parse_year_month/1` / `parse_int/2` を、本増分の `Sheet` でも使うために `AyumiWeb.AttendanceLive.MonthParams` に1つだけ切り出す。Index の挙動は不変 (リファクタのみ)。

**Files:**
- Create: `lib/ayumi_web/live/attendance_live/month_params.ex`
- Modify: `lib/ayumi_web/live/attendance_live/index.ex`

**Interfaces:**
- Consumes: なし
- Produces:
  - `AyumiWeb.AttendanceLive.MonthParams.parse/1 :: (map()) -> {integer(), integer()}` — `params["year"]` / `params["month"]` を整数化、`month` が 1..12 でなければ今日の年月にフォールバック

- [ ] **Step 1: 共通モジュールを新規作成**

新規ファイル `lib/ayumi_web/live/attendance_live/month_params.ex`:

```elixir
defmodule AyumiWeb.AttendanceLive.MonthParams do
  @moduledoc "出欠系 LiveView 共通の年月パラメータ解釈。"

  @doc """
  Parses `params["year"]` and `params["month"]` (string or nil) into a
  `{year, month}` tuple. Falls back to today's year/month when missing or
  invalid; `month` is always within 1..12.
  """
  @spec parse(map()) :: {integer(), integer()}
  def parse(params) do
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
end
```

- [ ] **Step 2: Index 側を共通版に差し替える**

`lib/ayumi_web/live/attendance_live/index.ex`:

(a) `alias` ブロックに以下を追加 (`alias Ayumi.Plans.ProvisionType` の直後):

```elixir
  alias AyumiWeb.AttendanceLive.MonthParams
```

(b) `handle_params/3` 冒頭の以下の行:

```elixir
    {year, month} = parse_year_month(params)
```

を次に置換:

```elixir
    {year, month} = MonthParams.parse(params)
```

(c) ファイル下部の `parse_year_month/1` と `parse_int/2` の3 clause をすべて削除する (private のため呼び出し元は同ファイル内のみ。`handle_params/3` 以外から呼んでいないことを `grep` で確認すること):

```bash
grep -n "parse_year_month\|parse_int" lib/ayumi_web/live/attendance_live/index.ex
```

- [ ] **Step 3: 既存 Index テストが green のままを確認 (リファクタ回帰)**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 既存 9 テストが全 pass。1 つでも落ちたら共有版の挙動が違う可能性が高いので、Step 1 のロジックを Index の旧 private と完全一致させる。

- [ ] **Step 4: コミット**

```bash
git add lib/ayumi_web/live/attendance_live/month_params.ex lib/ayumi_web/live/attendance_live/index.ex
git commit -m "refactor: extract MonthParams from AttendanceLive.Index"
```

---

## Task 4: AttendanceLive.Sheet 骨格 + route + アクセステスト

URL を踏むと「ヘッダに利用者氏名・指定年月」「明細テーブル (末日数ぶんの行)」「合計欄」が描画されるまでを通す (内容のアサートは Task 5 以降)。一般スタッフでアクセスできることをここで担保する。

**Files:**
- Modify: `lib/ayumi_web/router.ex`
- Create: `lib/ayumi_web/live/attendance_live/sheet.ex`
- Create: `test/ayumi_web/live/attendance_sheet_live_test.exs`

**Interfaces:**
- Consumes:
  - `Ayumi.Plans.get_service_user!/1` (既存)
  - `Ayumi.Plans.build_attendance_sheet/3` (増分1)
  - `Ayumi.Plans.AttendanceSheet` (増分1)
  - `Ayumi.Plans.ProvisionType.label/1` / `billable/0` / `offsite/0` (増分1 + 本増分 Task 1)
  - `AyumiWeb.AttendanceLive.MonthParams.parse/1` (本増分 Task 3)
  - `AyumiWeb.ConnCase` ヘルパ `register_and_log_in_user/1` (既存 setup)
  - `Ayumi.PlansFixtures.service_user_fixture/0|1` (既存)
- Produces:
  - Route: `live "/service_users/:service_user_id/attendance/sheet", AttendanceLive.Sheet, :index` — `live_session :require_authenticated_user` 内
  - Module: `AyumiWeb.AttendanceLive.Sheet` (`use AyumiWeb, :live_view`)
  - `mount/3` で `socket.assigns` に `:service_user` を入れる
  - `handle_params/3` で `:year`, `:month`, `:sheet`, `:facility`, `:page_title` を入れる
  - `facility_info/0` private: `Application.get_env(:ayumi, :facility, [])` から `%{name: binary(), number: binary()}` を返す (未設定なら空文字)
  - View helper: `weekday_label/1`, `billable?/1`, `offsite?/1` (素朴な private)

- [ ] **Step 1: 失敗するテストを書く (アクセス可・末日数ぶんの行)**

新規作成 `test/ayumi_web/live/attendance_sheet_live_test.exs`:

```elixir
defmodule AyumiWeb.AttendanceSheetLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures

  setup :register_and_log_in_user

  describe "GET /service_users/:id/attendance/sheet (general staff)" do
    test "renders the service user name and a row per day of the given month", %{conn: conn} do
      su = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "山田 太郎"
      assert html =~ "2026"
      assert html =~ "6月"

      # 6月は30日 — 明細テーブルの行数 (data-day 属性を付与してカウント)
      row_count =
        html |> String.split(~s|data-day=|) |> length() |> Kernel.-(1)

      assert row_count == 30
    end
  end
end
```

> NOTE: 末日数の数え方は `data-day="…"` を行 `<tr>` に付ける前提でカウントする。後続の Step 3 で render に `data-day={line.date.day}` を含める。これで「フォームの数」のような実装詳細に依存せず、行数をテスト可能になる。

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: `no route found for GET /service_users/.../attendance/sheet` などで失敗。

- [ ] **Step 3: ルート追加**

`lib/ayumi_web/router.ex` の `live_session :require_authenticated_user` ブロック内、増分2 の `/service_users/:service_user_id/attendance` の直後に1行追加:

```elixir
      live "/service_users/:service_user_id/attendance/sheet", AttendanceLive.Sheet, :index
```

> NOTE: `/attendance` と末尾セグメントで区別される (衝突しない)。manager 限定ブロックに置かないこと。

- [ ] **Step 4: 骨格 LiveView を作成**

新規作成 `lib/ayumi_web/live/attendance_live/sheet.ex`:

```elixir
defmodule AyumiWeb.AttendanceLive.Sheet do
  @moduledoc "利用者別・1か月分の実績記録票 (印刷向けHTML)。"
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.ProvisionType
  alias AyumiWeb.AttendanceLive.MonthParams

  @impl true
  def mount(%{"service_user_id" => id}, _session, socket) do
    {:ok, assign(socket, :service_user, Plans.get_service_user!(id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {year, month} = MonthParams.parse(params)
    sheet = Plans.build_attendance_sheet(socket.assigns.service_user.id, year, month)

    {:noreply,
     socket
     |> assign(:year, year)
     |> assign(:month, month)
     |> assign(:sheet, sheet)
     |> assign(:facility, facility_info())
     |> assign(:page_title, gettext("実績記録票 %{y}年%{m}月", y: year, m: month))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- 印刷時の用紙サイズ・余白。Tailwind では @page を表現できないためここに置く。 --%>
      <style>
        @page { size: A4; margin: 12mm; }
      </style>

      <div class="print:hidden mb-3 flex gap-2">
        <button type="button" onclick="window.print()" class="btn btn-primary btn-sm">
          {gettext("印刷")}
        </button>
        <.link
          patch={~p"/service_users/#{@service_user.id}/attendance/sheet?#{[year: prev_year(@year, @month), month: prev_month(@year, @month)]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("← 前月")}
        </.link>
        <.link
          patch={~p"/service_users/#{@service_user.id}/attendance/sheet?#{[year: next_year(@year, @month), month: next_month(@year, @month)]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("翌月 →")}
        </.link>
        <.link
          navigate={~p"/service_users/#{@service_user.id}/attendance?#{[year: @year, month: @month]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("入力画面へ戻る")}
        </.link>
      </div>

      <header class="mb-3 text-sm">
        <h1 class="text-lg font-bold border-b border-black">
          {gettext("サービス提供実績記録票")}
        </h1>
        <div class="grid grid-cols-2 gap-2 mt-2">
          <div>
            {gettext("事業所名")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@facility.name}</span>
          </div>
          <div>
            {gettext("事業所番号")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@facility.number}</span>
          </div>
          <div>
            {gettext("受給者証番号")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@service_user.recipient_cert_number}</span>
          </div>
          <div>
            {gettext("市町村")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@service_user.recipient_cert_municipality}</span>
          </div>
          <div class="col-span-2">
            {gettext("利用者氏名")}:
            <span class="inline-block min-w-48 border-b border-black px-1">{@service_user.name}</span>
            <span class="text-xs ml-2">({@service_user.name_kana})</span>
          </div>
          <div class="col-span-2">
            {gettext("対象年月")}: <strong>{gettext("%{y}年%{m}月", y: @year, m: @month)}</strong>
          </div>
        </div>
      </header>

      <table class="w-full text-xs border-collapse border border-black">
        <thead>
          <tr>
            <th class="border border-black px-1">{gettext("日")}</th>
            <th class="border border-black px-1">{gettext("曜")}</th>
            <th class="border border-black px-1">{gettext("提供形態")}</th>
            <th class="border border-black px-1">{gettext("開始")}</th>
            <th class="border border-black px-1">{gettext("終了")}</th>
            <th class="border border-black px-1">{gettext("送迎 往")}</th>
            <th class="border border-black px-1">{gettext("送迎 復")}</th>
            <th class="border border-black px-1">{gettext("欠席時対応")}</th>
            <th class="border border-black px-1">{gettext("備考")}</th>
            <th class="border border-black px-1">{gettext("利用者確認印")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @sheet.lines} data-day={line.date.day} class={row_class(line.date)}>
            <td class="border border-black px-1 text-right">{line.date.day}</td>
            <td class="border border-black px-1">{weekday_label(line.date)}</td>
            <td class="border border-black px-1">{provision_label(line)}</td>
            <td class="border border-black px-1">{time_text(line, :start_time)}</td>
            <td class="border border-black px-1">{time_text(line, :end_time)}</td>
            <td class="border border-black px-1 text-center">{pickup_mark(line)}</td>
            <td class="border border-black px-1 text-center">{dropoff_mark(line)}</td>
            <td class="border border-black px-1 text-center">{absence_support_mark(line)}</td>
            <td class="border border-black px-1">{note_text(line)}</td>
            <td class="border border-black px-1"></td>
          </tr>
        </tbody>
      </table>

      <section class="mt-3 grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs">
        <div class="border border-black px-2 py-1">{gettext("利用日数")}: <strong>{@sheet.totals.billable_days}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("うち施設外")}: <strong>{@sheet.totals.offsite_days}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("送迎 往")}: <strong>{@sheet.totals.pickup_count}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("送迎 復")}: <strong>{@sheet.totals.dropoff_count}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("欠席時対応")}: <strong>{@sheet.totals.absence_support_count}</strong></div>
      </section>
    </Layouts.app>
    """
  end

  # --- helpers ---

  # 事業所名・事業所番号は DB を増やさず application config から読む。
  # 未設定なら空文字 (= 手書き欄として印刷される)。
  defp facility_info do
    cfg = Application.get_env(:ayumi, :facility, [])
    %{name: Keyword.get(cfg, :name, ""), number: Keyword.get(cfg, :number, "")}
  end

  defp prev_month(_year, 1), do: 12
  defp prev_month(_year, month), do: month - 1
  defp prev_year(year, 1), do: year - 1
  defp prev_year(year, _month), do: year
  defp next_month(_year, 12), do: 1
  defp next_month(_year, month), do: month + 1
  defp next_year(year, 12), do: year + 1
  defp next_year(year, _month), do: year

  # Sunday=1 … Saturday=7 (Index と同じロジック)
  defp weekday_label(%Date{} = d) do
    elem({"日", "月", "火", "水", "木", "金", "土"}, Date.day_of_week(d, :sunday) - 1)
  end

  defp row_class(%Date{} = d) do
    # 白黒前提のため網掛けではなく罫線/空白のみ。土日もここでは強調しない。
    case Date.day_of_week(d, :sunday) do
      _ -> ""
    end
  end

  defp provision_label(%{record: nil}), do: ""
  defp provision_label(%{record: rec}), do: ProvisionType.label(rec.provision_type) || ""

  defp time_text(%{record: nil}, _field), do: ""

  defp time_text(%{record: rec}, field) do
    case Map.get(rec, field) do
      %Time{} = t -> Time.to_iso8601(t)
      _ -> ""
    end
  end

  defp pickup_mark(%{record: %{pickup: true}}), do: "○"
  defp pickup_mark(_), do: ""

  defp dropoff_mark(%{record: %{dropoff: true}}), do: "○"
  defp dropoff_mark(_), do: ""

  defp absence_support_mark(%{record: %{provision_type: :absence_support}}), do: "○"
  defp absence_support_mark(_), do: ""

  defp note_text(%{record: nil}), do: ""
  defp note_text(%{record: rec}), do: rec.note || ""

  # 将来 billable?/offsite? を行装飾に使うときのために残しておく (本タスクでは未使用)
  defp _billable?(type), do: type in ProvisionType.billable()
  defp _offsite?(type), do: type in ProvisionType.offsite()
end
```

> NOTE: `_billable?/1` と `_offsite?/1` は仕様書で「行の見せ方に使う」と書かれているが、白黒・最小視認補助の方針では今は使わない。アンダースコア先頭にして「意図的な未使用」を明示しておく (Credo は通る)。**未使用警告が出るならこの2行は削除して構わない**。指示書の指針との関係を Task 11 の報告で1行記す。

- [ ] **Step 5: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: 1 test, 0 failures。

- [ ] **Step 6: コミット**

```bash
git add lib/ayumi_web/router.ex lib/ayumi_web/live/attendance_live/sheet.ex test/ayumi_web/live/attendance_sheet_live_test.exs
git commit -m "feat: add AttendanceLive.Sheet skeleton for print view"
```

---

## Task 5: 様式ヘッダ — 受給者証番号・事業所情報 (config 設定時/未設定時)

ヘッダの可変要素 (受給者証番号・事業所情報) が「config 設定時には出る／未設定でも 500 にならない」ことを担保する。

**Files:**
- Modify: `test/ayumi_web/live/attendance_sheet_live_test.exs`

**Interfaces:**
- Consumes: Task 4 のすべて
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加 (受給者証番号と未設定時の安定性)**

`describe "GET /service_users/:id/attendance/sheet (general staff)"` の末尾 `end` の直前に追加:

```elixir
    test "renders recipient cert number and municipality when present", %{conn: conn} do
      su = service_user_fixture(%{
        recipient_cert_number: "1234567890",
        recipient_cert_municipality: "渋谷区"
      })

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "1234567890"
      assert html =~ "渋谷区"
    end

    test "renders without crashing when :ayumi, :facility is unset", %{conn: conn} do
      Application.delete_env(:ayumi, :facility)
      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      # ヘッダのラベルは出る (値は空)
      assert html =~ "事業所名"
      assert html =~ "事業所番号"
    end

    test "renders facility name and number when :ayumi, :facility is set", %{conn: conn} do
      Application.put_env(:ayumi, :facility, name: "歩みワークス", number: "1311234567")
      on_exit(fn -> Application.delete_env(:ayumi, :facility) end)

      su = service_user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "歩みワークス"
      assert html =~ "1311234567"
    end
  end
```

> NOTE: 最後の `end` はその直前にあった `describe` ブロックの閉じであることに注意。`on_exit/1` で env を片付けることで他テストへ漏れさせない。`async: false` 前提なので env 操作も安全。

- [ ] **Step 2: テスト実行で green を確認 (Task 4 の render が既に満たすはず)**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: 4 tests, 0 failures。

> NOTE: 落ちる場合: ① ヘッダのテキストが render に出ていない → render 側に gettext で文字列が含まれているか確認。② config 未設定で落ちる → `facility_info/0` の `Keyword.get/3` のデフォルトが効いていない可能性あり。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_sheet_live_test.exs
git commit -m "test: assert facility header renders with/without :ayumi, :facility"
```

---

## Task 6: 明細 — 提供形態ラベル・送迎マーク・欠席時対応マーク

`commute` の日に「通所」ラベル、`pickup: true` の日に「○」、`absence_support` の日に「欠席時対応」列の「○」が描画されることを担保する。

**Files:**
- Modify: `test/ayumi_web/live/attendance_sheet_live_test.exs`

**Interfaces:**
- Consumes: Task 4 のすべて、`Ayumi.PlansFixtures.attendance_record_fixture/1` (既存)
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "GET /service_users/:id/attendance/sheet (general staff)"` の末尾 `end` の直前に追加:

```elixir
    test "renders provision label and pickup/dropoff marks for recorded days", %{conn: conn} do
      su = service_user_fixture()

      _ = attendance_record_fixture(%{
        service_user_id: su.id,
        service_date: ~D[2026-06-03],
        provision_type: :commute,
        pickup: true,
        dropoff: false,
        start_time: ~T[09:00:00],
        end_time: ~T[15:00:00],
        note: "通所"
      })

      _ = attendance_record_fixture(%{
        service_user_id: su.id,
        service_date: ~D[2026-06-04],
        provision_type: :offsite_work,
        pickup: false,
        dropoff: true
      })

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      # 提供形態ラベルが出ている
      assert html =~ "通所"
      assert html =~ "施設外就労"

      # 送迎マーク (○) が描画される
      assert html =~ "○"
    end
```

> NOTE: ここでは「○ が少なくとも1つ出る」ところまで担保し、列ごとの厳密一致は Task 7 の合計欄一致テストで間接的に確認する。

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: 5 tests, 0 failures。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_sheet_live_test.exs
git commit -m "test: assert provision label and pickup marks render"
```

---

## Task 7: 合計欄が `sheet.totals` と一致 (再計算しない)

合計欄に表示される 5 つの値が `Plans.build_attendance_sheet/3` の `totals` と一致することを直接アサートする。「画面側で数え直さない」を担保する回帰テスト。`absence_support` が利用日数に入らないことも同時に確認する。

**Files:**
- Modify: `test/ayumi_web/live/attendance_sheet_live_test.exs`

**Interfaces:**
- Consumes: Task 4 のすべて
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "GET /service_users/:id/attendance/sheet (general staff)"` の末尾 `end` の直前に追加:

```elixir
    test "totals row matches Plans.build_attendance_sheet/3 (no recount in view)", %{conn: conn} do
      su = service_user_fixture()

      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-01], provision_type: :commute, pickup: true})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-02], provision_type: :offsite_work, dropoff: true})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-03], provision_type: :absence_support})
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-04], provision_type: :commute, pickup: true, dropoff: true})

      sheet = Ayumi.Plans.build_attendance_sheet(su.id, 2026, 6)

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      assert html =~ "利用日数: <strong>#{sheet.totals.billable_days}</strong>"
      assert html =~ "うち施設外: <strong>#{sheet.totals.offsite_days}</strong>"
      assert html =~ "送迎 往: <strong>#{sheet.totals.pickup_count}</strong>"
      assert html =~ "送迎 復: <strong>#{sheet.totals.dropoff_count}</strong>"
      assert html =~ "欠席時対応: <strong>#{sheet.totals.absence_support_count}</strong>"

      # absence_support は欠席時対応にだけ入り、利用日数には入らない
      assert sheet.totals.billable_days == 3
      assert sheet.totals.offsite_days == 1
      assert sheet.totals.absence_support_count == 1
    end
```

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: 6 tests, 0 failures。落ちたら render の `<strong>…</strong>` の囲い方が一致していないか、ラベルが gettext で別文字列になっている可能性が高い。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_sheet_live_test.exs
git commit -m "test: totals row matches sheet.totals (no recount in view)"
```

---

## Task 8: 訂正＝最新採用 (印刷ビュー側の回帰)

同日2行 (訂正) があるとき、印刷ビューには最新行 (id 最大) の提供形態が反映されることを確認する。`build_attendance_sheet/3` 経由のため新規実装は不要、純粋な統合テスト。

**Files:**
- Modify: `test/ayumi_web/live/attendance_sheet_live_test.exs`

**Interfaces:**
- Consumes: Task 4 のすべて
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`describe "GET /service_users/:id/attendance/sheet (general staff)"` の末尾 `end` の直前に追加:

```elixir
    test "the latest correction wins for the same day", %{conn: conn} do
      su = service_user_fixture()

      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-05], provision_type: :commute})
      # correction
      _ = attendance_record_fixture(%{service_user_id: su.id, service_date: ~D[2026-06-05], provision_type: :absence})

      {:ok, _view, html} =
        live(conn, ~p"/service_users/#{su.id}/attendance/sheet?#{[year: 2026, month: 6]}")

      # その日の行に「欠席」が出ていて「通所」は出ていないこと
      # data-day="5" の <tr> の内側を取り出して限定検査する
      row =
        html
        |> String.split(~s|data-day="5"|)
        |> Enum.at(1)
        |> String.split("</tr>")
        |> List.first()

      assert row =~ "欠席"
      refute row =~ "通所"
    end
```

> NOTE: `String.split` の手芸的な抽出は LiveView の HTML 文字列が固定構造なら十分。Floki を使うほどの複雑さはない。

- [ ] **Step 2: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_sheet_live_test.exs
```
Expected: 7 tests, 0 failures。

- [ ] **Step 3: コミット**

```bash
git add test/ayumi_web/live/attendance_sheet_live_test.exs
git commit -m "test: latest correction wins on the printed sheet"
```

---

## Task 9: AttendanceLive.Index から Sheet への印刷導線リンク

入力画面 (`AttendanceLive.Index`) から印刷ページへ、**現在の年月を引き継いで** 1リンクで遷移できるようにする。Index の他の挙動は変えない。

**Files:**
- Modify: `lib/ayumi_web/live/attendance_live/index.ex` (`render/1` の `:actions` 内に1リンク追加)
- Modify: `test/ayumi_web/live/attendance_live_test.exs` (リンク存在を1ケース追加)

**Interfaces:**
- Consumes: Task 4 で定義した route
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`test/ayumi_web/live/attendance_live_test.exs` の `describe "GET /service_users/:id/attendance (general staff)"` の末尾 `end` の直前に追加:

```elixir
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
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: `/attendance/sheet?` が含まれず失敗。

- [ ] **Step 3: Index の `:actions` 内にリンクを1本追加**

`lib/ayumi_web/live/attendance_live/index.ex` の `render/1` 内、`<:actions>` ブロック内 (「翌月 →」リンクと「利用者詳細へ戻る」リンクの間など) に挿入:

```elixir
          <.link
            navigate={~p"/service_users/#{@service_user.id}/attendance/sheet?#{[year: @year, month: @month]}"}
            class="btn btn-ghost btn-sm"
          >
            {gettext("印刷")}
          </.link>
```

> NOTE: 既存の月送りや戻るリンクと同じ並び・スタイルにする。`save_day` ハンドラ、合計セクション、明細フォームの構造には触らない。

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```
Expected: 増分2 の全 9 + 本 1 = 10 ケースが pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi_web/live/attendance_live/index.ex test/ayumi_web/live/attendance_live_test.exs
git commit -m "feat: add print sheet link on attendance input page"
```

---

## Task 10: 事業所情報ひな型を config/config.exs にコメントで置く

実値は環境ごとに入れる前提。**数値・名前を勝手に埋めない。** コメントで例示するだけ。

**Files:**
- Modify: `config/config.exs`

**Interfaces:** なし

- [ ] **Step 1: ひな型コメントを追加**

`config/config.exs` の末尾近く、`config :ayumi, :backup_dir, …` の直後 (もしくは「Import environment specific config」コメントの直前) に追加:

```elixir
# 実績記録票ヘッダ用の事業所情報。未設定なら印刷時は空欄 (= 手書き欄)。
# 本番値は config/runtime.exs で System.get_env/1 経由にしてもよい (運用方針による)。
# config :ayumi, :facility,
#   name: "（事業所名）",
#   number: "（事業所番号）"
```

> NOTE: コメントのみのため `mix test` に影響なし。`mix format` で整形のみされる可能性あり。

- [ ] **Step 2: フォーマットして確認**

```bash
mix format
git diff config/config.exs
```
Expected: 追加した4行のコメントだけが差分。

- [ ] **Step 3: コミット**

```bash
git add config/config.exs
git commit -m "docs: add :ayumi, :facility config template (commented)"
```

---

## Task 11: gettext 抽出と `mix review` 完走、完了報告

新規 msgid を `.pot` / `.po` に反映し、品質ゲートを通す。最後に変更ファイル一覧と「なぜ」を1行ずつ報告する。

**Files:**
- Modify: `priv/gettext/default.pot` (`mix gettext.extract` で自動更新)
- Modify: `priv/gettext/ja/LC_MESSAGES/default.po` (`mix gettext.merge` 後、必要なら手で日本語訳を埋める)

**Interfaces:** なし

- [ ] **Step 1: msgid を抽出してマージ**

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```
Expected: `default.pot` と `ja/LC_MESSAGES/default.po` に新規 msgid (例: `"印刷"`, `"サービス提供実績記録票"`, `"事業所名"`, `"事業所番号"`, `"対象年月"`, `"受給者証番号"`, `"市町村"`, `"利用者氏名"`, `"利用者確認印"`, `"入力画面へ戻る"`, `"欠席時対応"`, `"開始"`, `"終了"` など) が追加される。`.pot` を手編集しないこと。

- [ ] **Step 2: `ja/LC_MESSAGES/default.po` の空 `msgstr ""` を埋める**

新規 msgid の `msgstr` がそのまま日本語で良ければ msgid と同じ文字列を入れる (msgid が日本語のため)。既存運用に合わせる (既存テストが green になっていれば OK)。

- [ ] **Step 3: 全テストを実行**

```bash
mix test
```
Expected: 全 green (本増分 + 増分1・2 の既存全テスト)。

- [ ] **Step 4: `mix review` を通す**

```bash
mix review
```
Expected: format check OK / compile warnings-as-errors OK / Credo OK / Sobelow OK / Dialyzer OK / `mix test` 全 green。

- [ ] **Step 5: 失敗があれば最小差分で fix (専用の小さなコミットに分ける)**

例:
- format: `mix format` → `git commit -m "chore: format attendance sheet live files"`
- credo: 該当箇所を最小差分で修正 → `git commit -m "chore: appease credo for attendance sheet live"`
- 未使用警告 (`_billable?/1` / `_offsite?/1`): 該当2行を削除 → `git commit -m "chore: drop unused helpers from attendance sheet live"`
- dialyzer: `@spec` 不足や型不整合を解消 → `git commit -m "chore: tighten attendance sheet typespecs"`

- [ ] **Step 6: ブラウザ印刷プレビューで目視確認 (実装者がローカルで)**

開発サーバを起動:
```bash
mix phx.server
```

以下を確認:
1. `/service_users/<id>/attendance/sheet?year=2026&month=6` を開く。
2. ブラウザの「印刷」または `⌘P` / `Ctrl+P` で印刷プレビューを開く。
3. A4 1枚 (または妥当な枚数。30日なら 1〜2 枚) に様式が収まる。
4. 白黒モードで各列が読める (色に依存していない)。
5. 「印刷」「← 前月」「翌月 →」「入力画面へ戻る」のボタン群がプレビュー上では消えている (`print:hidden` が効いている)。
6. `:ayumi, :facility` 未設定の状態でも 500 にならず、事業所名/番号欄は空欄 (罫線のみ)。`Application.put_env(:ayumi, :facility, name: "歩みワークス", number: "1311234567")` を `iex -S mix phx.server` で打ってリロードすると、値が反映される。

> NOTE: 目視チェックの結果は最終報告に「○/×」で残す (テストでは担保していないため)。

- [ ] **Step 7: 変更ファイル一覧と「なぜ」を1行ずつ報告**

報告フォーマット:
- `lib/ayumi/plans/provision_type.ex` — `offsite/0` 追加 (繰り越し Minor 解消、施設外の定義を一元化)
- `lib/ayumi/plans.ex` — `totals_from/1` の offsite リテラルを `ProvisionType.offsite()` に差し替え (一元化、挙動互換)
- `lib/ayumi_web/live/attendance_live/month_params.ex` — 年月パラメータ解釈を共通化 (Index と Sheet で重複を避ける正当な DRY)
- `lib/ayumi_web/live/attendance_live/index.ex` — `MonthParams.parse/1` に差し替え (private 重複を削除)。`<:actions>` に「印刷」リンクを1本追加 (印刷ページへの導線、年月を引き継ぐ)
- `lib/ayumi_web/live/attendance_live/sheet.ex` — 印刷向け LiveView (様式ヘッダ + 明細 + 合計 + `@page` / `print:hidden`)。表示は `build_attendance_sheet/3` 再利用、画面で再計算しない
- `lib/ayumi_web/router.ex` — `/service_users/:service_user_id/attendance/sheet` を全認証スタッフ向けに追加 (記録系=全スタッフの方針)
- `config/config.exs` — `:ayumi, :facility` のひな型コメント (実値は環境ごと、未設定なら印刷時は空欄)
- `test/ayumi/plans/enumerations_test.exs` — `ProvisionType.offsite/0` 単体テスト
- `test/ayumi/plans_test.exs` — `offsite_days` が施設外2種の合計になる回帰テスト1件 (既存なら追加スキップ)
- `test/ayumi_web/live/attendance_sheet_live_test.exs` — 6系統 (アクセス／受給者証ヘッダ／facility 未設定で落ちない／facility 設定時に出る／提供形態ラベル・送迎マーク／合計一致／訂正最新採用)
- `test/ayumi_web/live/attendance_live_test.exs` — Index → Sheet 印刷リンク 1 ケース追加
- `priv/gettext/default.pot` / `priv/gettext/ja/LC_MESSAGES/default.po` — 新規 msgid を抽出・マージ

「気づいた将来課題 (実装しない／列挙のみ)」も合わせて報告:
- CSV 出力 (月別実績の機械可読エクスポート)
- 日別ロスター入力 (全員×1日)・月一括入力
- 行ごとのインライン・エラー表示 (現状は flash 単一メッセージ)
- 欠席時対応・施設外支援の上限の見せ方 (注意喚起のみ、強制しない)
- 出欠の manager 限定化 (運用判断、route 移動のみで実現可能)
- 印刷プレビューの自動テスト (Playwright/Wallaby など) — 現状は目視
- README / CLAUDE.md / CHANGELOG の更新 (別パスで運用)

- [ ] **Step 8: スコープ外チェック**

以下が**入っていない**ことを確認:
- CSV／サーバ側 PDF 生成・外部依存なし (例: `:puppeteer`, `:wkhtmltopdf`, `:chrome` 系の依存追加なし)
- 日別ロスター方式・月一括入力なし
- 報酬単価・加算上限のロジックなし
- 既存スキーマ (`service_user` 等) の列追加なし
- 増分2 Index の入力ロジックの変更なし (年月パラメータ共有差し替え + リンク1本追加のみ)
- README / CLAUDE.md / CHANGELOG の更新なし

---

## Self-Review チェックリスト (実装者が最後に通す)

- [ ] 仕様書「ゴール」「権限・配置」「既存パターンに合わせる」「作る／触るファイル」「書くテスト」「完了条件」がすべて File Structure / Tasks に対応している
- [ ] 仕様書「書くテスト」の各 bullet が以下のいずれかでカバーされている
  - アクセス (一般スタッフ) → Task 4
  - ヘッダ (利用者氏名・受給者証番号) → Task 4 + Task 5
  - ヘッダ (事業所名 config 設定時／未設定でも落ちない) → Task 5
  - 明細 (末日数ぶんの行) → Task 4
  - 明細 (commute → 提供形態ラベル、pickup → 送迎(往)○) → Task 6
  - 欠席時対応 (○ が出る／利用日数に入らない) → Task 6 + Task 7
  - 合計一致 → Task 7
  - 訂正の反映 (最新採用) → Task 8
  - `ProvisionType.offsite/0` 追記 → Task 1
  - 集計リファクタ回帰 (`offsite_days` 不変) → Task 2
- [ ] 仕様書「同時に片付ける繰り越し Minor」(`ProvisionType.offsite/0` ヘルパー化 + `build_attendance_sheet/3` の `offsite_days` の置き換え) が Task 1 + Task 2 で実装されている
- [ ] 仕様書「年月パラメータの共有」の小リファクタが Task 3 で実装されている (Index 側 private を削除して共有版に差し替え)
- [ ] LiveView は assign と `handle_params` だけ、ロジックは context 委譲
- [ ] 派生値 (合計) を view で再計算していない (`Enum.count` / `Enum.sum` を render で呼んでいない)
- [ ] route が `:require_authenticated_user` ブロックにあり、`:require_manager` にない
- [ ] 印刷ボタンは `print:hidden` で印刷プレビューから消える
- [ ] `@page { size: A4; margin: 12mm; }` がページ内 `<style>` に1ブロックだけ置かれている
- [ ] 罫線は `border border-black` などで明示し、色や網掛けに依存していない
- [ ] PDF 生成器・外部依存を一切追加していない
- [ ] gettext は `extract` / `merge` で反映し、`.pot` を手編集していない
- [ ] 事業所情報は config から読み、未設定でも 500 にならない (`Keyword.get(cfg, :name, "")` で空文字フォールバック)
- [ ] CSV／日別ロスター／月一括入力の実装が**ない**

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-21-attendance-record-increment-3.md`. 実装に進む際の選択肢:

1. **Subagent-Driven (推奨)** — Task ごとに新しい subagent を起動し、間にレビューを挟む。`superpowers:subagent-driven-development` を使う。
2. **Inline Execution** — このセッションで `superpowers:executing-plans` を使い、チェックポイントで止めながらバッチ実行する。

どちらで進めますか？
