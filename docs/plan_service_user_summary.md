# 実装計画：利用者まとめ画面

## 結論

既存の `ServiceUserLive.Show`（`/service_users/:id`）を拡張し、1画面に基本情報・期限・計画/目標・進捗/フェーズ履歴・支援記録を集約表示する。スキーマ変更なし、新規依存なし。既存コンテキスト関数を再利用し、不足分は「最近N件」を返す薄い読み取りヘルパーのみ追加。

---

## 方針：既存 show ページの拡張

- 新規ルート不要。既存の `live "/service_users/:id", ServiceUserLive.Show, :show` をそのまま使う
- `mount/3` でデータを追加取得し、render に新セクションを追記する
- 読み取り専用。書き込み経路は一切追加しない

---

## フェーズ構成

### フェーズ 1：コンテキスト関数の追加（`lib/ayumi/plans.ex`）

既存関数で不足する「最近N件」系のヘルパーを追加する。

#### 1-1. `list_recent_support_records/2`（新規）

```elixir
@doc "指定利用者の支援記録を最新N件返す。"
def list_recent_support_records(service_user_id, limit \\ 20)
```

- 再利用: 既存の `list_support_records/2` のクエリパターン（`order_by desc: recorded_at, desc: id`、`preload [:service_user, :recorded_by]`）
- 差分: `service_user_id` 固定 + `limit` のみ。日付フィルタなし
- テーブル: `support_records`

#### 1-2. `list_recent_goal_progress_for_user/2`（新規）

```elixir
@doc "指定利用者の全目標の進捗記録を最新N件返す。"
def list_recent_goal_progress_for_user(service_user_id, limit \\ 20)
```

- join: `goal_progresses` → `goals` → `support_plans`（`service_user_id` でフィルタ）
- `order_by desc: id`、`preload [:recorded_by, goal: :support_plan]`
- `limit` 付き

#### 1-3. `list_recent_plan_phase_events_for_user/2`（新規）

```elixir
@doc "指定利用者の全計画のフェーズイベントを最新N件返す。"
def list_recent_plan_phase_events_for_user(service_user_id, limit \\ 20)
```

- join: `plan_phase_events` → `support_plans`（`service_user_id` でフィルタ）
- `order_by desc: id`、`preload [:recorded_by, support_plan: []]`
- `limit` 付き

#### 1-4. 期限ヘルパーの再利用（既存関数のまま）

- `monitoring_deadline_status/3` — 期限ステータス判定（`:overdue` / `:near` / `:ok`）
- `list_certificate_expiry_alerts/3` — 受給者証アラート（ただし全利用者対象なので、個別利用者用の軽量版の検討が必要 → 下記参照）

**受給者証期限のこの利用者版:** `monitoring_deadline_status/3` はジェネリックな `Date` 比較なので、show 画面では `service_user.recipient_cert_expiry` を直接渡してステータスを取得する。新関数は不要。

---

### フェーズ 2：テスト先行（TDD）

#### 2-1. コンテキスト単体テスト（`test/ayumi/plans_test.exs` に追記）

| テスト | 検証内容 |
|--------|----------|
| `list_recent_support_records/2` の基本動作 | N件制限・降順・当該利用者のみ |
| `list_recent_goal_progress_for_user/2` の基本動作 | N件制限・降順・当該利用者のみ |
| `list_recent_plan_phase_events_for_user/2` の基本動作 | N件制限・降順・当該利用者のみ |
| 他利用者のデータが混ざらない | 2名分のデータを作り、片方のみ返ることを確認 |

#### 2-2. LiveView テスト（`test/ayumi_web/live/service_user_live_test.exs` に追記）

| テスト | 検証内容 |
|--------|----------|
| まとめ画面に主要セクションが表示される | マウント後 HTML に「期限」「支援計画」「進捗履歴」「支援記録」見出しが含まれる |
| 表示が当該利用者のデータに限定される | 他利用者の support_record が HTML に出ない |
| 退所者でもまとめ画面が開ける | `enrollment_status: :withdrawn` の利用者を show で開いてエラーにならない |
| 期限バッジが既存ヘルパーで表示される | 超過/近接のバッジクラスが HTML に出る |
| 各セクションにリンクがある | 支援計画詳細・支援記録表・編集画面へのリンク存在を assert |

---

### フェーズ 3：LiveView の実装（`lib/ayumi_web/live/service_user_live/show.ex`）

#### 3-1. `mount/3` の拡張

追加する assigns:

| assign | 取得方法 |
|--------|----------|
| `@today` | `Date.utc_today()` （既存） |
| `@support_plans` | `Plans.list_support_plans_for_user(service_user)` （既存） |
| `@current_plan` | `List.first(@support_plans)` （最新計画、period_start desc で取得済み） |
| `@goals` | `@current_plan` があれば `Plans.list_goals(@current_plan)`、なければ `[]` |
| `@latest_progress` | `Plans.latest_goal_progress_by_goal(@goals)` （既存） |
| `@recent_goal_progress` | `Plans.list_recent_goal_progress_for_user(service_user.id)` （新規） |
| `@recent_phase_events` | `Plans.list_recent_plan_phase_events_for_user(service_user.id)` （新規） |
| `@recent_support_records` | `Plans.list_recent_support_records(service_user.id)` （新規） |
| `@monitoring_status` | `@current_plan` の `next_monitoring_date` を `monitoring_deadline_status/3` で判定 |
| `@cert_status` | `service_user.recipient_cert_expiry` を `monitoring_deadline_status/3` で判定 |
| `@near_days` | `30` （ダッシュボードと同じ定数） |
| `@cert_near_days` | `60` |

#### 3-2. `render/1` のセクション構成

表示順（指示書に従う）:

1. **基本情報**（既存セクションをそのまま維持）
   - 氏名/フリガナ/生年月日(年齢)/在籍状態/利用開始日/連絡先
   - 編集リンク（manager のみ）

2. **期限（この利用者）**（新規セクション）
   - 受給者証期限 + 状態バッジ (`@cert_status`)
   - 直近モニタリング期限 + 状態バッジ (`@monitoring_status`)
   - バッジ表示: `deadline_status_label/1` と `days_until_label/1` をダッシュボードから移植 → **共通化の判断**: ダッシュボードの private 関数をそのまま show にも defp で持つ（2箇所なら重複許容。抽象化は3箇所以上になったら検討）

3. **受給者証・手帳**（既存セクションを維持）
   - 受給者証情報 + disability_certificates テーブル

4. **現行の支援計画と目標**（既存「支援計画」セクションを拡張）
   - 現行計画の基本情報（担当者、計画期間、長期目標、次回モニタリング日）
   - 目標一覧 + 各目標の最新進捗ステータス (`@latest_progress`)
   - 計画詳細ページへのリンク
   - 過去計画は折りたたみまたは下部に簡易リスト

5. **進捗・フェーズ履歴（最近）**（新規セクション）
   - `@recent_goal_progress` — 目標名 / ステージ / 記録者 / 日時 / 所見
   - `@recent_phase_events` — 計画名 / ステージ / 記録者 / 日時 / 所見
   - 最近20件。「すべて見る」→ 支援計画詳細ページへのリンク

6. **支援記録（最近）**（新規セクション）
   - `@recent_support_records` — 日時 / カテゴリ / 内容抜粋 / 記録者
   - 最近20件。末尾に「支援記録表でこの利用者を見る」リンク
   - リンク先: `/support_records`（将来的に `?service_user_id=xxx` パラメータ対応が望ましいが、現状の SupportRecordLive.Index は mount 時にフィルタが nil のため、まずはリンクのみ）

#### 3-3. ヘルパー関数

| 関数 | 説明 |
|------|------|
| `deadline_status_label/1` | `:overdue` → "超過"、`:near` → "近接"（DashboardLive と同一ロジック） |
| `days_until_label/1` | 日数ラベル（DashboardLive と同一ロジック） |
| `goal_progress_stage_label/1` | GoalProgressStage.label を呼ぶ |
| `plan_phase_stage_label/1` | PlanPhaseStage.label を呼ぶ |

---

### フェーズ 4：品質ゲート

1. `mix test` — 全テスト緑、既存テスト無傷
2. `mix review` — compile / Credo / Sobelow / Dialyzer クリーン
3. ブラウザで確認：
   - 在籍中の利用者の show ページに全セクション表示
   - 退所者の show ページがエラーなく開ける
   - 各リンクが正しい遷移先に飛ぶ

---

## ファイル変更一覧（予定）

| ファイル | 変更種別 | 内容 |
|----------|----------|------|
| `lib/ayumi/plans.ex` | 修正 | `list_recent_support_records/2`, `list_recent_goal_progress_for_user/2`, `list_recent_plan_phase_events_for_user/2` を追加 |
| `lib/ayumi_web/live/service_user_live/show.ex` | 修正 | mount でデータ追加取得、render に6セクション構成 |
| `test/ayumi/plans_test.exs` | 修正 | 新規ヘルパーの単体テスト追加 |
| `test/ayumi_web/live/service_user_live_test.exs` | 修正 | まとめ画面の LiveView テスト追加 |

**変更しないファイル:** スキーマ、マイグレーション、ルーター、ダッシュボード、その他の LiveView

---

## 再利用する既存関数マップ

| 用途 | 既存関数 | 所在 |
|------|----------|------|
| 利用者取得 + 証明書 preload | `Plans.get_service_user!/1` | plans.ex:32 |
| 支援計画一覧（降順） | `Plans.list_support_plans_for_user/1` | plans.ex:103 |
| 目標一覧 | `Plans.list_goals/1` | plans.ex |
| 目標ごとの最新進捗 | `Plans.latest_goal_progress_by_goal/1` | plans.ex:231 |
| 期限ステータス判定 | `Plans.monitoring_deadline_status/3` | plans.ex:295 |
| バッジラベル | `deadline_status_label/1`, `days_until_label/1` | DashboardLive.Index（defp — show にも同一 defp を置く） |

---

## リスク・判断ポイント

1. **`deadline_status_label/1` の重複**: DashboardLive と Show に同じ defp を置く。2箇所なら許容範囲。3箇所に増えたら CoreComponents に移動する
2. **支援記録表への利用者フィルタ付きリンク**: 現状の SupportRecordLive.Index は URL パラメータでの初期フィルタ未対応。まとめ画面からは `/support_records` へのプレーンリンクに留め、フィルタ付き遷移は別タスクとする
3. **データ量**: 利用者35名、各20件制限なので N+1 問題は実質発生しない。join + preload で1-2クエリに収まる
4. **`list_goals/1` の preload**: 既存は goals のみ。目標名 + 最新進捗の表示に十分

---

## 受け入れ基準（チェックリスト）

- [x] 利用者まとめ画面で、基本情報・期限・計画/目標・進捗/フェーズ・支援記録が1画面に出る
- [x] 期限判定が既存ヘルパーの再利用になっている（ロジック重複なし）
- [x] 表示がその利用者のデータだけに限定されている
- [x] 退所者でも画面が開ける
- [x] 各セクションから既存の編集/追加画面へリンクがある
- [x] テスト先行で緑、既存テスト無傷
- [x] `mix review` クリーン
