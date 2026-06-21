# 実装計画：支援記録の退所者フィルタ・作成ガード（Med-2）

## 概要

支援記録（`SupportRecord`）に関する2つの不具合を TDD で修正する。

| # | 不具合 | 影響 |
|---|--------|------|
| 1 | `list_support_records/2` が退所者の記録を全体一覧に含めてしまう | 退所者の過去記録が一覧に混入 |
| 2 | `create_support_record/2` が退所者IDを弾いていない | 改ざんparamsで退所者への記録作成が可能 |

## コードベース調査結果

### 対象関数の現状

**`list_support_records/2`**（`lib/ayumi/plans.ex:375-405`）
- `SupportRecord` を直接クエリし、`service_user` の在籍状態を参照していない
- `service_user_id`, `from`, `to` のオプションフィルタのみ

**`create_support_record/2`**（`lib/ayumi/plans.ex:367-372`）
- `changeset → put_audit → insert_support_record` のパイプライン
- 対象利用者の在籍状態チェックなし

**`insert_support_record/1`**（`lib/ayumi/plans.ex:407-418`）
- FK制約エラーのみハンドリング（存在しないIDの処理）

### 触らない関数

**`list_recent_support_records/2`**（`lib/ayumi/plans.ex:457-464`）
- per-user 履歴関数。退所者の履歴もここから読める設計を維持する

### 既存の退所者フィルタパターン

プロジェクト内で統一されたパターンが存在する：

```elixir
# current_support_plans/0 (plans.ex:338-346)
SupportPlan
|> join(:inner, [p], su in assoc(p, :service_user))
|> where([_p, su], su.enrollment_status != :withdrawn)

# list_certificate_expiry_alerts (plans.ex:437-439)
ServiceUser
|> where([su], su.enrollment_status != :withdrawn)
```

→ **`list_support_records/2` にも同じ inner join + where パターンを適用する。**

### テスト構造

- `describe "support records"` ブロック：`plans_test.exs:882-1038`
  - 既存テスト6本（作成・バリデーション・一覧フィルタ・並び順）
- `describe "list_recent_support_records/2"` ブロック：`plans_test.exs:1040-`
  - 既存テスト3本（per-user、preload確認）
- `support_record_fixture`（`test/support/fixtures/plans_fixtures.ex:77`）
  - 内部で `create_support_record/2` を呼ぶ → テストでは在籍中に記録を作成してから退所に遷移する手順が必要

---

## 実装手順

### Step 1 — 失敗するテストを書く（Red）

**ファイル：** `test/ayumi/plans_test.exs`
**場所：** `describe "support records"` 内（既存テストの末尾、L1038 付近）

追加するテスト3本：

#### 1-a. 一覧除外テスト
```elixir
test "list_support_records/2 は退所者の記録を一覧から除外する" do
  active = service_user_fixture()
  withdrawn = service_user_fixture()

  _a = support_record_fixture(service_user_id: active.id)
  _w = support_record_fixture(service_user_id: withdrawn.id)

  # 在籍中に記録を作成した後、退所に遷移
  {:ok, _} = Plans.update_service_user(withdrawn, %{enrollment_status: :withdrawn})

  scope = Ayumi.Accounts.Scope.for_user(Ayumi.AccountsFixtures.user_fixture())
  ids = scope |> Plans.list_support_records() |> Enum.map(& &1.service_user_id)

  assert active.id in ids
  refute withdrawn.id in ids
end
```

**期待結果：** 在籍者の記録のみ返され、退所者の記録は除外される。
**現状：** 退所者の記録も含まれるため **FAIL**。

#### 1-b. 作成拒否テスト
```elixir
test "create_support_record/2 は退所者への記録作成を拒否する" do
  withdrawn = service_user_fixture(enrollment_status: :withdrawn)
  scope = Ayumi.Accounts.Scope.for_user(Ayumi.AccountsFixtures.user_fixture())

  assert {:error, changeset} =
           Plans.create_support_record(scope, %{
             service_user_id: withdrawn.id,
             content: "記録テスト",
             category: :work
           })

  assert %{service_user_id: _} = errors_on(changeset)
end
```

**期待結果：** `{:error, changeset}` で `:service_user_id` にエラーが付く。
**現状：** 正常に挿入されるため **FAIL**。

#### 1-c. per-user 履歴の非退行テスト
```elixir
test "list_recent_support_records/2 は退所者の履歴を引き続き返す" do
  su = service_user_fixture()
  rec = support_record_fixture(service_user_id: su.id)
  {:ok, _} = Plans.update_service_user(su, %{enrollment_status: :withdrawn})

  assert [%{id: id}] = Plans.list_recent_support_records(su.id)
  assert id == rec.id
end
```

**期待結果：** 退所後もper-user履歴は取得可能。
**現状：** `list_recent_support_records/2` は変更しないため **PASS**（非退行確認）。

#### 確認コマンド
```bash
mix test test/ayumi/plans_test.exs
```
→ 1-a と 1-b が RED、1-c が GREEN であること。

---

### Step 2 — 一覧フィルタの実装（Green: 1-a）

**ファイル：** `lib/ayumi/plans.ex`
**関数：** `list_support_records/2`（L380 付近）

`SupportRecord` クエリの起点に inner join + where を追加：

```diff
     SupportRecord
+    |> join(:inner, [r], su in assoc(r, :service_user))
+    |> where([_r, su], su.enrollment_status != :withdrawn)
     |> order_by([r], desc: r.recorded_at, desc: r.id)
     |> preload([:service_user, :recorded_by])
```

**既存 where 節への影響：**
後続の `where([r], ...)` はバインディング `r` のみ参照。join で追加された `su` は位置束縛の2番目に入るが、既存の where 節は `[r]` で先頭のみ参照しているため影響なし。preload もそのまま動作する。

**パターンの根拠：**
`current_support_plans/0`（L338-346）と同一パターン。

---

### Step 3 — 作成ガードの実装（Green: 1-b）

**ファイル：** `lib/ayumi/plans.ex`

#### 3-a. `create_support_record/2` のパイプラインに検証を挿入

```diff
  def create_support_record(%Scope{} = scope, attrs) when is_map(attrs) do
    %SupportRecord{}
    |> SupportRecord.changeset(attrs)
    |> SupportRecord.put_audit(scope.user.id, DateTime.utc_now(:second))
+   |> validate_active_service_user()
    |> insert_support_record()
  end
```

#### 3-b. private 関数を追加（`insert_support_record/1` 付近）

```elixir
defp validate_active_service_user(%Ecto.Changeset{valid?: false} = changeset), do: changeset

defp validate_active_service_user(changeset) do
  case Ecto.Changeset.get_field(changeset, :service_user_id) do
    nil ->
      changeset

    id ->
      if withdrawn_service_user?(id) do
        Ecto.Changeset.add_error(
          changeset,
          :service_user_id,
          "退所者には支援記録を作成できません"
        )
      else
        changeset
      end
  end
end

defp withdrawn_service_user?(id) do
  ServiceUser
  |> where([su], su.id == ^id and su.enrollment_status == :withdrawn)
  |> Repo.exists?()
end
```

**設計判断：**
- `valid?: false` のときはスキップ（先行バリデーションのエラーを尊重）
- `service_user_id` が `nil` のときもスキップ（required バリデーションに委ねる）
- 存在しない ID は `Repo.exists?` が `false` → FK制約処理（`insert_support_record/1`）に委ねる
- `ServiceUser` alias は `plans.ex` で既に使用済み

---

### Step 4 — 品質ゲート

```bash
mix review
```

（format / compile --warnings-as-errors / credo / test）全てグリーンであること。

---

## 変更対象ファイル

| ファイル | 変更内容 | 概算 |
|----------|----------|------|
| `test/ayumi/plans_test.exs` | テスト3本追加 | +30行 |
| `lib/ayumi/plans.ex` | join/where追加 + validate関数追加 | +20行 |

**合計：** 2ファイル、約 +50行

## スコープ外（触らない）

- `list_recent_support_records/2` 等の per-user 履歴関数
- Med-3（支援計画フォームの退所者ガード）
- LiveView 側（`SupportRecordLive.Index`）— select は既に在籍者のみ
- リファクタ・整形

## 受け入れ条件

- [ ] `list_support_records/2` が退所者の記録を一覧から除外する
- [ ] `create_support_record/2` が退所者IDへの記録作成を `{:error, changeset}` で拒否する
- [ ] `list_recent_support_records/2` が退所者の履歴を引き続き返せる（非退行）
- [ ] 既存の support records テスト（在籍者の作成・取得）がグリーン維持
- [ ] `mix review` グリーン
- [ ] 差分は上記2ファイルのみ
