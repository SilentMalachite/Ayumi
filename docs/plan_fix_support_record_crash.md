# 実装計画書：支援記録の新規作成 Ecto.CastError 修正

**起票日:** 2026-06-20
**優先度:** High
**方針:** TDD（Red → Green → Refactor）
**概算工数:** 小（差分 4 ファイル、±30 行程度）

---

## 1. 不具合の概要

LiveView フォームから支援記録を作成すると **`Ecto.CastError`** で必ずクラッシュする。

### 原因の機序

```
[LiveView] handle_event("create") → params は文字列キーマップ
  ↓
[Plans.create_support_record/2] Map.put(:recorded_by_id, ...) / Map.put(:recorded_at, ...)
  → atom キーと文字列キーが混在するマップになる
  ↓
[SupportRecord.changeset/2] cast/3 がキー混在マップを受け取り Ecto.CastError を送出
```

### なぜ既存テストで見逃されたか

`test/ayumi/plans_test.exs:884` の `create_support_record` テストは **atom キーのみ** のマップを渡している。LiveView 経由（文字列キー）の経路をカバーするテストが存在しない。

---

## 2. 修正方針

`recorded_by_id` と `recorded_at` は **サーバ確定値**（scope 由来のユーザー ID・サーバー時刻）であり、ユーザー入力ではない。

**`cast` の許可リストから外し、`put_change` で後付けする。**

これにより：
1. `cast/3` に渡る `attrs` は文字列キー or atom キーの **単一種別** のまま保たれ、キー混在が構造的に起きない
2. クライアントから `recorded_by_id` / `recorded_at` を送っても `cast` が無視するため、改ざん耐性も同時に確保される

---

## 3. 影響範囲の分析（Serena による確認結果）

### 変更対象ファイル（4 ファイルのみ）

| ファイル | 変更内容 | 概算 |
|---------|---------|------|
| `test/ayumi_web/live/support_record_live_test.exs` | 新規作成：LiveView 経由のテスト 2 件 | +40 行 |
| `lib/ayumi_web/live/support_record_live/index.ex` | `<.form>` に `id="support-record-form"` を付与 | +1 行 |
| `lib/ayumi/plans/support_record.ex` | `changeset` を user fields のみに絞り、`put_audit/3` を追加 | ±15 行 |
| `lib/ayumi/plans.ex` | `create_support_record/2` で `Map.put` を `put_audit` 呼び出しに置換 | ±5 行 |

### 影響を受ける既存コード

- **`Plans.create_support_record/2`**（`lib/ayumi/plans.ex:367-376`）— 呼び出し元は `handle_event("create")` の 1 箇所のみ
- **`SupportRecord.changeset/2`**（`lib/ayumi/plans/support_record.ex:22-29`）— 呼び出し元は `create_support_record` と `change_support_record` の 2 箇所。`change_support_record` は空フォーム用なので `put_audit` は不要（影響なし）
- **既存テスト**（`test/ayumi/plans_test.exs:884-945`）— atom キー経路。`create_support_record` 内で `put_audit` が呼ばれるため動作は変わらず、グリーン維持の見込み

---

## 4. 実装手順（TDD）

### Step 1 — フォームに id 付与（テストセレクタ安定化）

**ファイル:** `lib/ayumi_web/live/support_record_live/index.ex`（170 行目付近）

```diff
- <.form for={@form} phx-submit="create" class="mt-4">
+ <.form for={@form} id="support-record-form" phx-submit="create" class="mt-4">
```

既存の `#support-plan-form` に倣った命名。

### Step 2 — 失敗テストを書く（RED）

**ファイル:** `test/ayumi_web/live/support_record_live_test.exs`（新規作成）

テスト 2 件：

1. **「LiveView フォーム（文字列キー）から支援記録を作成できる」**
   - `register_and_log_in_manager` でログイン
   - `service_user_fixture()` で利用者を作成
   - `/support_records` に LiveView 接続
   - `#support-record-form` に `service_user_id`, `category`, `content` を submit
   - フラッシュ「支援記録を保存しました」と `content` が HTML に含まれることを assert

2. **「クライアント由来の監査フィールドは無視される」**（改ざん耐性の回帰テスト）
   - params に `recorded_by_id: other.id` と `recorded_at: "2000-01-01T00:00:00Z"` を混入
   - submit 後に `list_support_records` で取得し、`recorded_by_id` がログインユーザーと一致することを assert

**確認:** `mix test test/ayumi_web/live/support_record_live_test.exs` を実行し、1 本目が `Ecto.CastError` で落ちることを確認する。

### Step 3 — changeset の修正（GREEN）

**ファイル:** `lib/ayumi/plans/support_record.ex`

```diff
- @required [:service_user_id, :content, :category, :recorded_by_id, :recorded_at]
- @optional []
+ @user_fields [:service_user_id, :content, :category]
+ @audit_fields [:recorded_by_id, :recorded_at]
```

```diff
  def changeset(support_record, attrs) do
    support_record
-   |> cast(attrs, @required ++ @optional)
-   |> validate_required(@required)
+   |> cast(attrs, @user_fields)
+   |> validate_required(@user_fields)
    |> validate_inclusion(:category, SupportRecordCategory.all())
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
+
+ def put_audit(changeset, recorded_by_id, recorded_at) do
+   changeset
+   |> put_change(:recorded_by_id, recorded_by_id)
+   |> put_change(:recorded_at, recorded_at)
+   |> validate_required(@audit_fields)
+ end
```

### Step 4 — コンテキスト関数の修正

**ファイル:** `lib/ayumi/plans.ex`（`create_support_record/2`、367-376 行目）

```diff
  def create_support_record(%Scope{} = scope, attrs) when is_map(attrs) do
-   attrs =
-     attrs
-     |> Map.put(:recorded_by_id, scope.user.id)
-     |> Map.put(:recorded_at, DateTime.utc_now(:second))
-
    %SupportRecord{}
    |> SupportRecord.changeset(attrs)
+   |> SupportRecord.put_audit(scope.user.id, DateTime.utc_now(:second))
    |> insert_support_record()
  end
```

### Step 5 — テスト実行（GREEN 確認）

```bash
# 新規 LiveView テスト
mix test test/ayumi_web/live/support_record_live_test.exs

# 既存コンテキストテスト（atom キー経路がグリーン維持）
mix test test/ayumi/plans_test.exs
```

### Step 6 — 品質ゲート

```bash
mix review
```

`format --check-formatted` / `compile --warnings-as-errors --force` / `credo` / `test` が全てグリーンであること。

---

## 5. 受け入れ条件チェックリスト

- [ ] 文字列キー経路の LiveView submit テストが存在し、保存成功（フラッシュ＋一覧反映）を検証
- [ ] `recorded_by_id` が scope 由来、`recorded_at` がサーバ時刻で設定される
- [ ] 改ざん params（`recorded_by_id` 等）を混ぜてもサーバ値で確定される（回帰テストで検証）
- [ ] `plans_test.exs` の既存テストがグリーン維持
- [ ] `mix review` オールグリーン
- [ ] 差分は上記 4 ファイルのみ

---

## 6. スコープ厳守（やらないこと）

- 退所者フィルタ（Med-2: `list_support_records` の join / active 検証）には着手しない
- 退所者の支援計画作成ガード（Med-3: `show.ex` / `support_plan` form）には着手しない
- ついでのリファクタ・命名変更・無関係な整形をしない
- 最小差分を維持する

---

## 7. リスク評価

| リスク | 影響 | 対策 |
|--------|------|------|
| `change_support_record` が `put_audit` なしで呼ばれる | フォーム初期化用のため問題なし。`put_audit` はDB保存前の `create_support_record` でのみ必要 | 既存動作を確認済み |
| 既存テストが atom キーで `category: :work` を渡す | `cast/3` は atom キーも文字列キーも受け付ける。`@user_fields` に `:category` があるので問題なし | Step 5 で検証 |
| `validate_required(@audit_fields)` が `put_audit` 呼び忘れ時にエラーを出すか | `put_audit` を通さなければ `recorded_by_id` / `recorded_at` が nil のまま insert → DB の NOT NULL 制約で失敗。`validate_required` は `put_audit` 内で実行されるため、呼べば changeset レベルで検証される | 設計上安全 |
