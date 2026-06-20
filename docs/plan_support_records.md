# 実装計画：支援記録（support_records）

## 概要

既存の `GoalProgress` / `PlanPhaseEvent` と同じ追記専用パターンで `SupportRecord` を追加する。
`ServiceUser` に紐づき、`category`（区分）フィールドを持つ日々の支援記録。

---

## Phase 1: Enum モジュール + スキーマ + マイグレーション

### 1-1. `lib/ayumi/plans/support_record_category.ex`（新規）

`GoalProgressStage` を鏡にした enum モジュール。

```elixir
@labels [
  work: "作業",
  daily_living: "生活",
  health: "健康",
  interview: "面談",
  other: "その他"
]
```

- `all/0`, `label/1`, `options/0` を提供（`GoalProgressStage` と同一構造）

### 1-2. `lib/ayumi/plans/support_record.ex`（新規）

`GoalProgress` を鏡にしたスキーマ。

```elixir
@required [:service_user_id, :content, :category, :recorded_by_id, :recorded_at]
@optional []

schema "support_records" do
  field :content, :string
  field :category, Ecto.Enum, values: SupportRecordCategory.all()
  field :recorded_at, :utc_datetime

  belongs_to :service_user, ServiceUser
  belongs_to :recorded_by, Ayumi.Accounts.User

  timestamps(type: :utc_datetime, updated_at: false)
end
```

changeset:
- `cast` → `validate_required` → `validate_inclusion(:category, ...)` → `foreign_key_constraint` x2
- `content` は `validate_required` で空文字も拒否（Ecto デフォルト動作）

### 1-3. マイグレーション `priv/repo/migrations/<timestamp>_create_support_records.exs`

```elixir
create table(:support_records) do
  add :service_user_id, references(:service_users, on_delete: :restrict), null: false
  add :content, :text, null: false
  add :category, :string, null: false
  add :recorded_by_id, references(:users, on_delete: :restrict), null: false
  add :recorded_at, :utc_datetime, null: false
  timestamps(type: :utc_datetime, updated_at: false)
end

create index(:support_records, [:service_user_id])
create index(:support_records, [:recorded_at])
```

---

## Phase 2: コンテキスト関数（`Ayumi.Plans`）

### 2-1. `create_support_record(%Scope{} = scope, attrs)`

- `recorded_by_id` を `scope.user.id` から自動設定
- `recorded_at` を `DateTime.utc_now(:second)` で自動設定
- attrs からこの2フィールドは受け取らない（上書き）
- `%SupportRecord{}` → changeset → `insert_support_record/1`（private）
- `insert_support_record/1` は `insert_goal_progress/1` と同じ rescue パターン

### 2-2. `list_support_records(%Scope{}, opts \\ [])`

- opts: `service_user_id` (integer), `from` (Date), `to` (Date)
- `recorded_at` 降順
- `service_user` と `recorded_by` を preload
- クエリを段階的に `|> then(...)` で組み立て（`list_service_users` のフィルタパターンに倣う）
- 日付フィルタ: `from` → 当日 00:00:00 UTC 以降、`to` → 翌日 00:00:00 UTC 未満

### 2-3. `change_support_record(%SupportRecord{}, attrs \\ %{})`

- フォーム用 changeset 生成（`change_goal_progress` と同パターン）

### 2-4. 追加の private 関数

- `insert_support_record/1` — FK rescue パターン（`insert_goal_progress` の鏡）
- `add_support_record_foreign_key_errors/1` — `service_user_id` と `recorded_by_id` のエラーメッセージ追加

---

## Phase 3: テスト（TDD — 先にテストを書く）

### 3-1. fixture 追加 `test/support/fixtures/plans_fixtures.ex`

```elixir
def support_record_fixture(attrs \\ %{}) do
  service_user_id = attrs[:service_user_id] || service_user_fixture().id
  recorded_by = attrs[:recorded_by] || user_fixture()
  scope = Ayumi.Accounts.Scope.for_user(recorded_by)

  {:ok, record} =
    Plans.create_support_record(
      scope,
      Enum.into(attrs, %{
        service_user_id: service_user_id,
        content: "午前の作業に集中できた",
        category: :work
      })
    )

  record
end
```

### 3-2. テスト `test/ayumi/plans_test.exs`

`describe "support records"` ブロックを追加。

| # | テスト | 検証内容 |
|---|--------|----------|
| 1 | `create_support_record/2` 正常 | insert される、`recorded_by_id` = scope.user.id、`recorded_at` が自動設定 |
| 2 | `create_support_record/2` content 空 | `{:error, changeset}` で `:content` にエラー |
| 3 | `create_support_record/2` category 不正 | `{:error, changeset}` で `:category` にエラー |
| 4 | `create_support_record/2` FK 不正 | `service_user_id=-1` → changeset エラー |
| 5 | `list_support_records/2` service_user 絞り込み | 別ユーザーの記録が出ない |
| 6 | `list_support_records/2` 日付範囲 | from/to で期間内のみ返す |
| 7 | `list_support_records/2` 降順・preload | `recorded_at` desc、`service_user`/`recorded_by` が preload |

---

## Phase 4: LiveView（支援記録表）

### 4-1. `lib/ayumi_web/live/support_record_live/index.ex`（新規）

**mount:**
- `list_service_users()` で在籍中ユーザーを取得（select 用）
- デフォルト絞り込み: 当日（`Date.utc_today()`）
- `list_support_records` で一覧取得
- `change_support_record(%SupportRecord{})` でフォーム初期化

**handle_event:**
- `"filter"` — 利用者ID / 日付範囲でリストを再取得
- `"create"` — `create_support_record(scope, attrs)` → 成功でリスト再読み込み＋フォームリセット

**render:**
- 絞り込みフォーム: 利用者 select（在籍中のみ）＋ 日付 from / to
- 一覧テーブル: 日付、利用者、区分（ラベル表示）、記入者、本文
- 新規追加フォーム: 利用者 select、区分 select、本文 textarea
- 編集・削除 UI なし（append-only）
- 全文字列 `gettext` で日本語

### 4-2. ルーター `lib/ayumi_web/router.ex`

`:require_authenticated_user` live_session 内に追加:

```elixir
live "/support_records", SupportRecordLive.Index, :index
```

---

## Phase 5: 品質ゲート

1. `mix test` — 全テスト緑（既存テスト無傷を確認）
2. `mix review` — compile / Credo / Sobelow / Dialyzer クリーン
3. 差分の要約と結果を報告

---

## ファイル変更サマリ

| 操作 | ファイル |
|------|----------|
| 新規 | `lib/ayumi/plans/support_record_category.ex` |
| 新規 | `lib/ayumi/plans/support_record.ex` |
| 新規 | `priv/repo/migrations/*_create_support_records.exs` |
| 新規 | `lib/ayumi_web/live/support_record_live/index.ex` |
| 編集 | `lib/ayumi/plans.ex`（コンテキスト関数追加） |
| 編集 | `lib/ayumi_web/router.ex`（ルート追加） |
| 編集 | `test/support/fixtures/plans_fixtures.ex`（fixture 追加） |
| 編集 | `test/ayumi/plans_test.exs`（テスト追加） |

## 設計判断

1. **置き場所**: `Ayumi.Plans` に追加（タスク指示通り、最小摩擦）
2. **`recorded_at` / `recorded_by_id` 自動設定**: 既存パターンでは LiveView 側で手動設定しているが、タスク仕様で「`scope` から自動設定」と明記されているため、コンテキスト関数内で設定する（より安全な API）
3. **`content` の空文字チェック**: `validate_required` が Ecto のデフォルトで `""` も拒否するため追加バリデーション不要
4. **日付フィルタの `from` / `to`**: `recorded_at`（UTC datetime）を `Date` で比較。`from` の開始は当日 00:00:00 UTC、`to` の終了は翌日 00:00:00 UTC 未満で切る
