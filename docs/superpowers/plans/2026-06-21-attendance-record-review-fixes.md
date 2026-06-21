# 実績記録票 — Codex レビュー指摘の修正計画

**指示書**: `/Users/hiro/Desktop/ayumi_review_fixes_attendance.md`
**Codex 判定**: With fixes（Important 1件＋Minor 3件）
**スコープ**: 既存・実装済みの実績記録票機能（`AttendanceLive.Index` / `AttendanceRecord` / `AttendanceSheet` / `AGENTS.md`）。既存挙動とテストは壊さない。
**ガード条件**: 最小差分・TDD（再現テスト先行）・`mix review` green。

---

## 概要（結論先）

4件の修正を、**TDD で再現テスト先行**で1ファイル＝1コミット相当の小さな単位に分けて入れる。順序は重要度順:

1. **Fix 1（Important）** `save_day` の `service_date` をサーバ側で表示中シートの実在日に検証
2. **Fix 2（Minor）** うるう年2月の網羅テストを追加
3. **Fix 3（Minor）** 不正な `year/month` の当月フォールバックを LiveView レベルでテスト
4. **Fix 4（Minor）** `AGENTS.md` の `:require_authenticated_user` 例に attendance 2ルートを明示

Important の本質: `<input type="hidden" name="date">` を信頼しているため、crafted な LiveView event で**表示月外の任意日**に追記できる。請求根拠データなので塞ぐ。

---

## 現状把握（コード読解の結果）

### `lib/ayumi_web/live/attendance_live/index.ex`

- `handle_event("save_day", %{"date" => date_str, "attendance_record" => attrs}, socket)` が
  `attrs |> Map.put("service_date", date_str)` をそのまま changeset に渡している（158–164行付近）。
- changeset は `cast(attrs, @user_fields)` で `service_date` を素直に受ける（`lib/ayumi/plans/attendance_record.ex:37` 周辺）。crafted な `2026-07-15` のような表示月外文字列も `Date.from_iso8601!` 相当でキャストされて成立してしまう。
- 結果: 6月のシートを開いたまま `date` を `2026-07-15` で送ると、**7月の行として `attendance_record` が追記され**、別の月のシートで履歴に現れる。

### `lib/ayumi_web/live/attendance_live/month_params.ex`

- `MonthParams.parse(params)` が `Date.utc_today/0` 基準で `{year, month}` を返す。`year` が `"bad"` でも `today.year` に落ちる。`month` が `13` でも `1..12` 外なので `{today.year, today.month}` に落ちる。**フォールバックロジックは既にある**。LiveView 経由でこの挙動が破れていない（クラッシュしない・当月の表が出る）ことを確認するテストを追加するのが Fix 3。

### `test/ayumi_web/live/attendance_live_test.exs`

- `use AyumiWeb.ConnCase, async: false` で `setup :register_and_log_in_user`。
- 既存の `save_day` 提出は次のセレクタ形式で書かれている:

      view
      |> form("form[phx-submit='save_day']:has(input[value='2026-06-10'])", %{...})
      |> render_submit()

  `form/2` の第2引数は hidden を含むフォーム値にマージされる。これで crafted 入力を再現できる。

### `test/ayumi/plans/attendance_record_test.exs`

- 月境界の網羅は `lines cover every day of a 30-day month` / `31-day` / `非うるう年 2月 (2026=28日)` がある（235–252行）。
- うるう年（2028=29日）の test が**抜けている**のが Fix 2 で埋める穴。

### `AGENTS.md`

- 79行付近の `:require_authenticated_user` ブロックに `# show/index routes` コメントがあり、attendance 2ルートが例示されていない。manager-only に誤読されないよう、全職員ルートの例として追加するのが Fix 4。

---

## Fix 1（Important）: `save_day` の `service_date` をサーバ側で検証

### 失敗テスト先行（RED）

`test/ayumi_web/live/attendance_live_test.exs` の `describe "saving a day's record"` 末尾に追加:

```elixir
test "表示月外の日付は crafted でも保存できない", %{conn: conn} do
  su = service_user_fixture()

  {:ok, view, _html} =
    live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: 2026, month: 6]}")

  before_count = Repo.aggregate(AttendanceRecord, :count, :id)

  # 6月10日の実フォームを掴み、render_submit で hidden の `date` を当月外に上書き
  view
  |> form("form[phx-submit='save_day']:has(input[value='2026-06-10'])", %{
    "date" => "2026-07-15",
    "attendance_record" => %{"provision_type" => "commute"}
  })
  |> render_submit()

  assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
  assert render(view) =~ "表示中の月の日付のみ"
end
```

要点:

- DB 件数が**前後で不変**（追記されないこと）
- フラッシュ文言 `"表示中の月の日付のみ"` が表示される
- 正常系（6月の hidden は当月の実在日）の既存テストはそのまま green を維持

### 実装（GREEN）

`lib/ayumi_web/live/attendance_live/index.ex` の `handle_event("save_day", ...)` を**シートに実在する日付のみ通す**形に置き換える。

```elixir
@impl true
def handle_event("save_day", %{"date" => date_str, "attendance_record" => attrs}, socket) do
  su = socket.assigns.service_user

  case parse_sheet_date(socket.assigns.sheet, date_str) do
    {:ok, date} ->
      attrs =
        attrs
        |> Map.put("service_user_id", su.id)
        |> Map.put("service_date", date)

      case Plans.create_attendance_record(socket.assigns.current_scope, attrs) do
        {:ok, _record} ->
          sheet = Plans.build_attendance_sheet(su.id, socket.assigns.year, socket.assigns.month)

          {:noreply,
           socket
           |> put_flash(:info, gettext("%{d} の記録を保存しました", d: Date.to_iso8601(date)))
           |> assign(:sheet, sheet)}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, first_error_message(changeset))}
      end

    :error ->
      {:noreply, put_flash(socket, :error, gettext("表示中の月の日付のみ保存できます"))}
  end
end

# 表示中シートに存在する日付だけ許可する（= @year/@month の実在日であることの保証）
defp parse_sheet_date(sheet, date_str) do
  with {:ok, date} <- Date.from_iso8601(date_str),
       true <- Enum.any?(sheet.lines, &(&1.date == date)) do
    {:ok, date}
  else
    _ -> :error
  end
end
```

### 設計上の理由

- **「シートに存在する日」**で判定する＝そのまま `@year/@month` の実在日であることの保証（うるう年・月末の境界も同じロジックで網羅される）。年月だけの素朴比較より頑強。
- `service_date` を**文字列でなく `Date` 構造体**で changeset に渡す。`:date` cast はそのまま受けるので、changeset 側の変更は不要。
- `gettext` 文言は新規キー1個のみ追加。既存の `"%{d} の記録を保存しました"` を維持しつつ、保存時の表示は `Date.to_iso8601(date)` で従来同等。
- `parse_sheet_date/2` は私的ヘルパ。`lines` を線形走査するが、月内最大31件なのでコストは無視できる。

### 正常系への影響

- 画面に描画された `<input hidden name="date">` の値は必ず `@sheet.lines` に含まれる。よって既存の正常系テスト（`commute` 追加・訂正・送迎カウントなど）は全て通る。
- 弾かれるのは crafted な当月外日付のみ。

---

## Fix 2（Minor）: うるう年2月の網羅テスト

### 失敗テスト先行（RED）

`test/ayumi/plans/attendance_record_test.exs` の `describe "build_attendance_sheet/3"`、`"non-leap 2026"` テストの直後（252行付近）に追加:

```elixir
test "lines cover every day of February (leap 2028)", %{su: su} do
  sheet = Plans.build_attendance_sheet(su.id, 2028, 2)

  assert length(sheet.lines) == 29
  assert List.last(sheet.lines).date == ~D[2028-02-29]
end
```

- `%{su: su}` は既存 setup（230行 `setup do ... %{su: su, scope: scope} end`）に揃える。
- 既存テストの命名（英語、`"lines cover every day of ..."` 形式）に揃えるため指示書の日本語タイトルから英語化。挙動の主張は同じ。

### 実装（GREEN）

実装変更は**不要**。既に `Date.days_in_month/1` 系で月日数を算出している（2026/2=28 のテストが通っている事実）。RED → そのまま GREEN になる想定。

> 万一 GREEN にならない場合は `build_attendance_sheet/3` のうるう年処理を確認するが、現テストの整合性から実装は健全と推定。

---

## Fix 3（Minor）: 不正 `year/month` の当月フォールバックを LiveView でテスト

### 失敗テスト先行（RED）

`test/ayumi_web/live/attendance_live_test.exs` の `describe "GET /service_users/:id/attendance (general staff)"` 内、現在の月遷移リンクテストの近く（line 35 付近）に追加:

```elixir
test "不正な year/month は当月にフォールバックする", %{conn: conn} do
  su = service_user_fixture()
  today = Date.utc_today()

  {:ok, _view, html} =
    live(conn, ~p"/service_users/#{su.id}/attendance?#{[year: "bad", month: "13"]}")

  # 実レンダリングの月表記書式（"%{y}年%{m}月"）に合わせる
  assert html =~ "#{today.year}年#{today.month}月"
end
```

- 期待月は `Date.utc_today/0` から導出（ハードコードしない）。
- ページタイトル `"実績記録票 %{y}年%{m}月"` と subtitle `"%{y}年%{m}月"` のどちらかにマッチすればよい部分一致。
- クラッシュしないこと＋当月で描画されることが本質。

### 実装（GREEN）

実装変更は**不要**。`MonthParams.parse/1` のフォールバック（`{today.year, today.month}` 戻し）が既に正しく動いている。RED → 既存実装で GREEN になる想定。

---

## Fix 4（Minor）: `AGENTS.md` に attendance 2ルートを明示

### 編集箇所

`AGENTS.md` の `### Routes that require authentication` セクション内、`:require_authenticated_user` の例ブロック（line 79 付近）。`live_session :require_authenticated_user, ...` ブロック内、`# show/index routes` コメント前後に2行追加。

`live_session :require_manager` ブロックには**入れない**（manager-only と誤読される）。

### 変更内容（diff の形）

```diff
       live_session :require_authenticated_user,
         on_mount: [AyumiWeb.LanOnly, {AyumiWeb.UserAuth, :require_authenticated}] do
         live "/", DashboardLive.Index, :index
         live "/users/settings", UserLive.Settings, :edit
+        live "/service_users/:service_user_id/attendance", AttendanceLive.Index, :index
+        live "/service_users/:service_user_id/attendance/sheet", AttendanceLive.Sheet, :index
         # show/index routes
       end
```

- 他の規約文には触れない。
- テスト追加なし（ドキュメント変更のみ）。

---

## 作業順序とコミット分割

1. **コミット 1: Fix 2（leap year test）**
   - `test/ayumi/plans/attendance_record_test.exs` にテスト1件追加。
   - 期待: いきなり green（既存実装で通る）。
   - `mix test test/ayumi/plans/attendance_record_test.exs` で確認。

2. **コミット 2: Fix 3（month_params fallback test）**
   - `test/ayumi_web/live/attendance_live_test.exs` にテスト1件追加。
   - 期待: いきなり green（既存 `MonthParams.parse/1` で通る）。
   - `mix test test/ayumi_web/live/attendance_live_test.exs` で確認。

3. **コミット 3: Fix 1（save_day server-side validation, TDD）**
   - **RED**: `test/ayumi_web/live/attendance_live_test.exs` に crafted date テストを追加 → 既存実装で**失敗することを確認**（DB 件数が増えてしまう or フラッシュが出ない）。
   - **GREEN**: `lib/ayumi_web/live/attendance_live/index.ex` の `handle_event("save_day", ...)` を上記の形に置換し、`parse_sheet_date/2` を追加。
   - 既存の `save_day` 正常系テスト群が引き続き green であることを確認。
   - `mix test test/ayumi_web/live/attendance_live_test.exs` 全件 green。

4. **コミット 4: Fix 4（AGENTS.md）**
   - 該当ブロックに2行追加。
   - テスト変更なし。

5. **最終チェック**: `mix review`（format → 警告エラー扱いコンパイル → credo → test 全件）が green であることを確認してから完了報告。

---

## 完了条件（Definition of Done）

- 4件の修正が反映され、**新規テスト3件（leap-year / fallback / crafted date 回帰）が green**。
- 既存テストが全て green（特に `save_day` 正常系の追記・訂正・送迎カウント・time order error・audit 無視がそのまま通ること）。
- `mix review` が green。
- コミットメッセージは `fix:` プレフィックス、Fix 1 は Important として明記。CHANGELOG 追記は不要（未リリースのインクリメント内改善のため）。
- 完了報告で次の3点を明示:
  1. 触ったファイル一覧と各々の変更概要
  2. Fix 1 が**どの crafted 入力を**（例: `?year=2026&month=6` のシートに `"date" => "2026-07-15"` を送る）**どう弾くか**（`parse_sheet_date/2` が `Enum.any?(sheet.lines, ...)` で false → エラーフラッシュ）を1〜2行
  3. 気づいた追加課題があれば列挙のみ（実装はしない）

---

## スコープ外（混ぜない）

- §7 で triage 済みの既知 Minor: 秒表示の HH:MM 化、inline onclick、navbar `print:hidden` 実機確認、`first_error_message` の interpolation 等。
- 認可ポリシー（出欠の全職員可）の変更。方針確認事項であり本修正の範囲外。
- 既存挙動を変える refactor（`MonthParams` の戻り値型変更など）。
