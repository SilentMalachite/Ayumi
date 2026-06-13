# Ayumi 設計仕様（実装計画の前提）

- 日付: 2026-06-14
- 対象: Ayumi（歩み）— 就労継続支援B型 施設の個別支援計画 進捗トラッカー
- 前提資料: リポジトリ直下 `CLAUDE.md`（プロジェクト指針）

このドキュメントは CLAUDE.md を基に、ブレインストーミングで確定した設計判断をまとめたもの。
実装計画（writing-plans）の入力となる。コード識別子・モジュール名・列挙値は英語、
利用者向け文字列は日本語（CLAUDE.md 準拠）。

---

## 0. 確定した決定事項（ブレインストーミング結果）

1. **サービス利用者は独立テーブル** `service_user`。過去の計画を期またぎで参照したいため
   一級の存在にする（CLAUDE.md の「四つのテーブル」に対し、`service_user` と認証スタッフは
   それを支える参照テーブルという位置づけ）。
2. **ダッシュボードは全員分の締切を表示**。ログイン中スタッフの担当利用者を先頭に寄せる
   ソートを添える（全員が見える点は不変）。
3. **目標の進捗ステージは提案の5段階で進める（暫定）**。enum を1か所に集約し、施設の確認後に
   変更しやすくする。
4. **「期限が近い」窓は 30 日**（overdue = 過去日、near = 今日〜30日先）。
5. **コンテキストは単一 `Ayumi.Plans`** に集約（認証 `Ayumi.Accounts` は `phx.gen.auth` 生成）。
6. **「現在の状態」は純関数 fold が正本**。「最新」は **`id` 昇順の最後の行**（挿入順）で定義。
   訂正も新しい行を後から append → 最新が勝つ。

## 1. 技術前提

- Erlang/OTP 29, Elixir 1.20.1（確認済み）
- Phoenix installer 1.8.1 → `phx.gen.auth` は **scope ベース**（`current_scope` に担当スタッフ）。
- Ecto + SQLite（`ecto_sqlite3`）。SQLite 3.51。**PostgreSQL は使わない**。
- 単一ホスト + LAN、完全オフライン。DB ファイルは1インスタンスが占有、ネットワーク共有/クラウド同期不可。
- SQLite 設定（Repo config）: `journal_mode: :wal` ＋ `busy_timeout` ＋ **`foreign_keys: :on`**
  （SQLite は既定で FK を強制しないが、本設計は FK 前提のため有効化する）。

## 2. スキーマ

スタッフ = `phx.gen.auth` の `Accounts.User`。表示用に **`name`（担当者名）列を1つ追加**。
ドメインは単一 `Ayumi.Plans` コンテキスト。

### service_user（一級・新規）
| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| name | string | ✓ | 氏名 |
| name_kana | string | | 五十音ソート/検索用 |
| timestamps | | | |

### support_plan（body・滅多に編集しない）
| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| service_user_id | FK → service_user | ✓ | |
| staff_id | FK → users | ✓ | 担当者 |
| period_start | date | ✓ | 計画開始 |
| period_end | date | ✓ | 計画終了 |
| long_term_goal | text | ✓ | 長期目標 |
| next_monitoring_date | date | ✓ | 次回モニタリング予定日 |
| timestamps | | | |

検証: `period_end >= period_start`。

### goal（body）
| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| support_plan_id | FK → support_plan | ✓ | |
| description | text | ✓ | 短期目標 |
| timestamps | | | |

### plan_phase_event（append-only ログ）
| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| support_plan_id | FK → support_plan | ✓ | |
| stage | Ecto.Enum（7段階） | ✓ | 新しいステージ |
| recorded_by_id | FK → users | ✓ | 誰が記録したか |
| note | text | | 所見 |
| correction_of_id | FK → self（nullable） | | 訂正の明示マーカー |
| inserted_at | | ✓ | いつ。**更新は一切しない** |

### goal_progress（append-only ログ）
| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| goal_id | FK → goal | ✓ | |
| stage | Ecto.Enum（5段階） | ✓ | 新しい進捗段階 |
| recorded_by_id | FK → users | ✓ | 誰が記録したか |
| note | text | | 所見 |
| correction_of_id | FK → self（nullable） | | 訂正の明示マーカー |
| inserted_at | | ✓ | いつ |

### Append-only 原則（不変条件）
- 状態変更は**必ず新しい行**。既存行の上書きはしない。
- 訂正も新しい行（`correction_of_id` で明示）。履歴は失わない。
- 「現在の状態」は**保存せず導出**。`current_stage` のような可変列は持たない。
- ログ行に編集/削除 UI を置かない。

## 3. 列挙とラベルの集約

JP 文字列を散らさず専用モジュールに一元化:

- `Ayumi.Plans.PlanStage` — 順序付き7段階アトム + JP ラベル + `all/0` `label/1` `index/1`
  - 順序: `assessment` → `draft` → `support_meeting` → `consent` → `in_progress` → `monitoring` → `review`
  - JP: アセスメント → 計画原案 → 個別支援会議 → 説明・同意・交付 → 支援の実施 → モニタリング → 見直し
- `Ayumi.Plans.GoalProgressStage` — 5段階（暫定）+ JP ラベル
  - `not_started` / `working` / `partially_met` / `mostly_met` / `met`
  - JP: 未着手 / 取組中 / 一部達成 / 概ね達成 / 達成

スキーマは `field :stage, Ecto.Enum, values: PlanStage.all()`。施設が段階名を変えてもこの
モジュール1か所で済む。

**設計判断（ライフサイクル遷移）**: 順序は表示・ソート用に保持するが、**遷移の前後関係は強制しない**
（現場は戻り・やり直しがあるため）。changeset は「既知のステージのいずれか」のみ検証する。
厳格なステートマシンは将来必要になれば追加。

## 4. 現在状態の導出（純関数が正本）

`Ayumi.Plans.Derive`（DB 非依存・純粋）:

- `current_stage(events)` / `current_progress(rows)` = **`id` 昇順の最後の行**（最新勝ち。訂正行も後勝ち）。
- `history(rows)` = 時系列順リスト（タイムライン表示用）。
- 空ログ → `nil`。

一覧・詳細は関連行を preload してメモリ上で適用。35人規模なので N+1 は許容。将来重くなれば
「グループ別最新行」クエリに差し替え、正本の純関数は不変のまま使う。

`inserted_at` は秒単位衝突の恐れがあるため「最新」の判定には使わず、単調増加の `id` を順序の
正本とする（`inserted_at` は「いつ」の表示用）。

## 5. ダッシュボードの締切クエリ

`Plans.monitoring_deadlines(scope, today, near_days \\ 30)`:

- 各 `service_user` の**現在の計画** = `period_start` が最新の plan を選ぶ（古い完了計画の過去日が
  「万年期限切れ」にならないようにする）。
- `days_until = next_monitoring_date - today` で分類:
  - **overdue**: `days_until < 0`
  - **near**: `0 <= days_until <= near_days`
  - それ以外: 非表示
- ソート: **自分の担当（`staff_id == current_scope.user.id`）を先頭** → 次に `days_until` 昇順（緊急順）。
- 全員分を表示（確定事項）。計画未作成の利用者は今回はリスト外（将来別枠で出すのは任意）。

`near_days` は既定 30。後で変えやすいよう関数引数 + 呼び出し側の集約値とする。

## 6. 画面（LiveView は薄く・ロジックは context へ）

LiveView は assigns とイベントハンドラのみ。検証は changeset、ロジックは `Plans` に委譲。

- **Step1**: 利用者一覧/詳細（詳細 = その人の計画履歴を期またぎ表示）、計画 新規/詳細/編集、
  目標を計画に複数追加。`+ phx.gen.auth` ログイン。
- **Step2**: 計画詳細の各目標に「現在の進捗 + 進捗記録フォーム（ステージ選択 + 所見）」。送信で
  `goal_progress` を append、進捗履歴も表示。**最頻出画面なので最小クリック**。
- **Step3**: 計画詳細にライフサイクル「現ステージ + ステージ記録」アクション（`plan_phase_event`
  を append）+ 履歴。**ダッシュボード（ログイン後トップ `/`）に締切（超過 + 30日以内、自分の担当先頭）**。

修正フロー: 「訂正を記録」= `correction_of_id` 付きの新規行を append。

## 7. エラー処理

- 検証は全て changeset → エラーはフォーム再描画（LiveView 標準）。LiveView 内に ad-hoc 検証は書かない。
- 未存在/不正 ID → 404・分かりやすいメッセージ。
- 破壊的操作なし（append-only）。

## 8. テスト（TDD・先に失敗テストを書く）

- 単体: `Derive`（最新勝ち / 訂正勝ち / 空 → nil）、各 changeset（必須・enum・日付順）、
  context 関数（append が新規行を作る・一覧/導出）。
- クエリ: 締切の overdue/near 分類、自分先頭ソート、利用者ごとの現在計画の選択。
- LiveView: 主要フロー（計画 + 目標作成 / 進捗記録 / ステージ記録 / ダッシュボード表示）。
- **`mix review` を品質ゲートとして新設**（mix alias）:
  `format --check-formatted` → `compile --warnings-as-errors` → `credo`（軽量・導入する） → `test`。
  dialyzer は重いので当面見送り。

## 9. ビルド順（各ステップ green + `mix review` クリーンで次へ）

CLAUDE.md の3ステップに Step0（足場）を加える。一度に1ステップずつ。

- **Step0 足場**: `mix phx.new . --app ayumi --database sqlite3`（カレントに展開し CLAUDE.md を残す）、
  git init、WAL/`busy_timeout`/`foreign_keys: :on` 設定、`mix review` alias + credo 導入、
  `phx.gen.auth Accounts User users`（+ `name` 列）、commit。
- **Step1**: service_user + support_plan + goal（スキーマ/移行/changeset/context/LiveView/テスト）。
- **Step2**: goal_progress + `Derive.current_progress` + 進捗記録 UI + テスト。
- **Step3**: plan_phase_event + `Derive.current_stage` + 締切クエリ + ダッシュボード + テスト。

## 10. 非目標（CLAUDE.md 準拠・本仕様でも維持）

- PostgreSQL / クラウド / マルチテナントなし。
- 実行時にインターネット依存なし。
- メール / プッシュ配信なし。
- 認証はローカルスタッフ口座のみ。ロール分離（サビ管 vs 支援者）は後回し。

## 11. 未確定・将来課題（実装をブロックしない）

- 目標進捗の5段階は施設の最終確認待ち（暫定で進める）。
- ライフサイクルの厳格なステートマシン化（今は強制しない）。
- 計画未作成の利用者をダッシュボードに別枠表示するか。
- 退所した利用者の絞り込み（`service_user.active` 等）。
- plan_phase_event に業務上の発生日（`occurred_on`）を別途持つか。
- 締切の near_days を施設ごとに設定可能にするか。
- LiveView フックによる OS デスクトップ通知（任意のおまけ、ベースラインの後）。
