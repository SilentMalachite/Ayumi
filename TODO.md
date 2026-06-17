# TODO — Ayumi

CLAUDE.md の設計とビルド順に沿った実装タスク一覧。リポジトリの現状を反映済み
（2026-06-18 時点）。**1つずつ・TDDで・`mix review` がグリーンになってから次へ。**

進め方の原則（CLAUDE.md より）:

- 失敗するテストを先に書く（contexts と changeset から）。
- 追記専用（append-only）を厳守。状態変更・訂正は**新しい行**として記録し、上書きしない。
- 「現在の状態」は保存せず、ログの最新行から**純粋関数で導出**する。
- ドメインロジックは context に。LiveView は薄く（assigns とイベントのみ）。
- 検証は changeset に集約。UI 文言は日本語＋gettext、識別子・コメントは英語。
- 差分は最小限。変更したファイル・関数とその理由を報告する。

---

## ✅ 完了済み（参考）

- Phoenix + SQLite(WAL) scaffold、`phx.gen.auth` 職員ログイン
- オフライン前提の職員アカウント作成（`mix ayumi.create_user` / dev seeds）
- LAN / localhost 限定アクセス（`AyumiWeb.LanOnly`）
- `service_user`（基本情報・年齢導出・障害者手帳 `disability_certificate`）
- `support_plan` スキーマ + 作成/一覧 + フォーム/詳細
- `goal` スキーマ + `create_goal` / `list_goals`（plan 詳細画面から追加）
- 同時編集対策: body テーブルの `lock_version` 楽観ロック + `AyumiWeb.Presence`
- UI 文言の gettext 化（service-user / support-plan 画面、レイアウト nav）
- 列挙体ヘルパ: `Gender` / `SupportCategory` / `CertificateKind`（`all/0` `label/1` `options/0`）
- `goal_progress` 追記専用ログ（`GoalProgressStage` / `GoalProgress` / `goal_progresses`）
- `SupportPlanLive.Show` での進捗記録フォーム、現在進捗、進捗履歴表示
- `Ayumi.Plans.current_goal_progress/1` / `latest_goal_progress_by_goal/1` による最新進捗導出
- `plan_phase_event` 追記専用ログ（`PlanPhaseStage` / `PlanPhaseEvent` / `plan_phase_events`）
- `SupportPlanLive.Show` でのステージ記録フォーム、現在ステージ、ステージ履歴表示
- 認証済みトップ `/` のモニタリング期限ダッシュボード

---

## ✅ ステップ2 — `goal_progress`（完了済み）

目的: 各 `goal`（短期目標）の進捗更新を**追記専用ログ**として記録し、最新行から
現在の進捗を導出する。

### 採用済みの進捗ステージ
- [x] `not_started / working / partially_met / mostly_met / met`
      （未着手 / 取組中 / 一部達成 / 概ね達成 / 達成）を現行仕様として実装済み。
      語彙を変える場合は `Ayumi.Plans.GoalProgressStage` と関連テストを更新する。

### 列挙体
- [x] `Ayumi.Plans.GoalProgressStage` を既存 enum ヘルパと同じ形で追加
      （`all/0` / `label/1`（日本語）/ `options/0`）。テスト先行。

### スキーマ + マイグレーション
- [x] マイグレーション `create_goal_progresses`:
      `goal_id`(FK, not null) / `stage`(string, not null) /
      `note`(text, 所見) / `recorded_by_id`(staff/user FK, not null) /
      `recorded_at`(utc_datetime, not null) / `inserted_at`。
      ※ body テーブルと違い `lock_version` は不要（追記専用なので更新しない）。
- [x] `Ayumi.Plans.GoalProgress` スキーマ + `belongs_to :goal` / `belongs_to :recorded_by`。
- [x] `changeset/2`: `stage` を許可値に inclusion 制約、必須項目を validate。
      訂正も新規行として扱う（既存行は更新しない）。

### context（純粋関数 + 永続化）
- [x] `record_goal_progress(attrs)` — 新しい進捗行を1件 insert（更新は一切しない）。
- [x] `record_goal_progress_for_plan(support_plan, attrs)` — plan に属する goal にだけ進捗を記録。
- [x] `list_goal_progress(goal)` — 1つの goal の履歴を時系列で返す。
- [x] `list_goal_progress_for_goals(goals)` — 複数 goal の履歴をまとめて取得。
- [x] `current_goal_progress(progress_events)` — **純粋関数**で最新行を畳み込み、
      現在の進捗行を返す（DB非依存・単体テスト容易に）。
- [x] `latest_goal_progress_by_goal(goals)` — N+1 を避けて複数 goal の最新進捗をまとめて取得。

### LiveView（最も使う画面）
- [x] goal ごとに進捗を記録するフォーム（ステージ選択 + 所見）。`recorded_by` は
      ログイン職員、`recorded_at` はサーバ側で付与。
- [x] plan 詳細（`SupportPlanLive.Show`）の goal 一覧に**現在の進捗**を表示。
- [x] goal の進捗**履歴**（誰が・いつ・どのステージ・所見）を表示。
- [x] LiveView フローのテスト（記録 → 一覧・最新表示の反映）。

---

## ✅ ステップ3 — `plan_phase_event` ＋ モニタリング期限ダッシュボード（完了済み）

### 3a. `plan_phase_event`（計画ライフサイクルの追記ログ）

ライフサイクル順:
`assessment → draft → support_meeting → consent → in_progress → monitoring → review`
（アセスメント → 計画原案 → 個別支援会議 → 説明・同意・交付 → 支援の実施 →
モニタリング → 見直し）

- [x] `Ayumi.Plans.PlanPhaseStage` 列挙体ヘルパ（順序付き `all/0` / `label/1` / `options/0`）。テスト先行。
- [x] マイグレーション `create_plan_phase_events`:
      `support_plan_id`(FK, not null) / `stage`(string, not null) /
      `note`(text, 所見) / `recorded_by_id`(FK, not null) /
      `recorded_at`(utc_datetime, not null) / `inserted_at`。`lock_version` 不要。
- [x] `Ayumi.Plans.PlanPhaseEvent` スキーマ + `changeset/2`（stage inclusion・必須）。
- [x] context:
      - [x] `record_plan_phase_event(attrs)` — 追記のみ。
      - [x] `list_plan_phase_events(support_plan)` — 履歴を時系列で。
      - [x] `current_plan_stage(events)` — **純粋関数**で最新ステージを導出。
- [x] LiveView: plan 詳細でステージ遷移を記録 + 現在ステージ + 履歴表示。
- [x] テスト（context / changeset / LiveView フロー）。

### 3b. モニタリング期限ダッシュボード（信頼できるベースライン）

目的: 接近中・超過のモニタリング期限を見逃さない。スタッフは業務で必ずアプリを
開くので、ページ表示時の Ecto クエリで**画面上部に常時表示**する。メール・定期
ジョブは使わない。

- [x] 表示範囲: 全施設の期限を表示し、ログイン職員の担当ユーザを先頭にソート。
- [x] context クエリ: `next_monitoring_date` を基準に「近接（しきい値内）/ 超過」の
      support_plan を抽出。近接の既定は 30 日以内。純粋に判定できる
      ヘルパ（日付 → near/overdue/ok 区分）を分離して単体テスト。
- [x] ホームを差し替え: `page_html/home.html.heex` の公開 root を廃止し、
      認証済みダッシュボード LiveView を新設。ゲストの `/` はログインへリダイレクト。
- [x] ソート: ログイン職員の担当ユーザを先頭にし、各グループ内は `days_until` 昇順。
- [x] 各行から該当 support_plan / service_user 詳細へ遷移。
- [x] テスト: クエリ（near/overdue 境界値）、ダッシュボード表示・ソート・空状態。

---

## 🔵 任意（later、ボーナス。保証はしない）

- [ ] アプリ起動中のみ、LiveView hook から Web Notifications API で OS 通知を出す
      ナッジ。ブラウザごとの許可が前提なので保証層にはしない（画面内リストが保証）。
- [ ] ロール分離（サビ管 vs 支援者）。CLAUDE.md では「後で」。今はやらない。

---

## 🚫 非対象（やらない — CLAUDE.md Non-goals）

PostgreSQL / クラウド / マルチテナント / 実行時のインターネット依存 /
メール・プッシュ配信 / Oban 等のジョブ基盤。

---

## Definition of Done（各タスク共通）

- 失敗テスト先行 → 実装 → リファクタ。context と changeset を直接テスト、主要
  フローに LiveView テスト。
- 追記専用・状態導出（純粋関数）の原則を守っている。
- UI 文言は日本語＋gettext。識別子・コメントは英語。
- `mix review` とテストがグリーン。変更したファイル・関数と理由を報告。
