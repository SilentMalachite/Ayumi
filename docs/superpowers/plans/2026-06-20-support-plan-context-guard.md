# 支援計画 context 層ガード（TOCTOU 修正） 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Plans.create_support_plan/1` に退所者ガードを追加し、LiveView の mount 時値に依存する TOCTOU 脆弱性を context 層で塞ぐ。

**Architecture:** 既存の `validate_active_service_user/1`（Med-2 で支援記録用に作成済み）をメッセージ引数付きの `/2` に一般化し、`create_support_plan/1` の changeset パイプラインに挿入する。`withdrawn_service_user?/1` は変更せず再利用のみ。`form.ex` は触らない（mount 時チェックは冗長な早期リターンとして残す）。

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, SQLite3, ExUnit

## Global Constraints

- 差分は 3 ファイルのみ: `test/ayumi/plans_test.exs`, `test/ayumi_web/live/support_plan_live_test.exs`, `lib/ayumi/plans.ex`
- `form.ex` は触らない
- `withdrawn_service_user?/1` の実装は変えない（再利用のみ）
- Med-2 の支援記録ロジック・テストは壊さない
- 品質ゲートは `mix review`（format / compile --warnings-as-errors / credo / test）

---

### Task 1: Context テスト — `create_support_plan/1` が退所者を拒否する（Red）

**Files:**
- Modify: `test/ayumi/plans_test.exs:195-229` (`describe "support plans"` ブロック内)

**Interfaces:**
- Consumes: `Plans.create_support_plan/1`, `service_user_fixture/1`, `Ayumi.AccountsFixtures.user_fixture/0`, `errors_on/1`
- Produces: なし（テストのみ）

- [ ] **Step 1: テストを書く**

`describe "support plans" do` ブロック（229 行目の `end` の直前）に追加:

```elixir
test "create_support_plan/1 は退所者への作成を拒否する" do
  withdrawn = service_user_fixture(enrollment_status: :withdrawn)
  staff = Ayumi.AccountsFixtures.user_fixture()

  attrs = %{
    "service_user_id" => withdrawn.id,
    "staff_id" => staff.id,
    "period_start" => "2026-04-01",
    "period_end" => "2026-09-30",
    "long_term_goal" => "長期目標",
    "next_monitoring_date" => "2026-07-01"
  }

  assert {:error, changeset} = Plans.create_support_plan(attrs)
  assert %{service_user_id: _} = errors_on(changeset)
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/ayumi/plans_test.exs --only line:229`
Expected: FAIL — `create_support_plan/1` が `{:ok, _}` を返す（context にガードが無いため）

---

### Task 2: TOCTOU 再現テスト — フォーム表示後の退所でも計画が作成されない（Red）

**Files:**
- Modify: `test/ayumi_web/live/support_plan_live_test.exs:1-169`（トップレベル `setup :register_and_log_in_manager` 内、169 行目の `describe` の直前に追加）

**Interfaces:**
- Consumes: `Plans.update_service_user/2`, `Plans.list_support_plans_for_user/1`, `service_user_fixture/0`, `Ayumi.AccountsFixtures.user_fixture/0`
- Produces: なし（テストのみ）

- [ ] **Step 1: テストを書く**

169 行目（`describe "supporter access..."` の直前）に追加:

```elixir
test "フォーム表示後に対象が退所しても支援計画は作成されない", %{conn: conn} do
  su = service_user_fixture()
  staff = Ayumi.AccountsFixtures.user_fixture()
  {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/support_plans/new")

  # フォーム表示後に別経路で退所へ更新
  {:ok, _} = Ayumi.Plans.update_service_user(su, %{enrollment_status: :withdrawn})

  params = %{
    staff_id: staff.id,
    period_start: "2026-04-01",
    period_end: "2026-09-30",
    long_term_goal: "長期目標",
    next_monitoring_date: "2026-07-01"
  }

  lv
  |> form("#support-plan-form", support_plan: params)
  |> render_submit()

  assert Ayumi.Plans.list_support_plans_for_user(su) == []
end
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs --only line:170`
Expected: FAIL — context にガードが無いため計画が insert され、`list_support_plans_for_user(su)` が空でなくなる

---

### Task 3: Context 層にガードを実装する（Green）

**Files:**
- Modify: `lib/ayumi/plans.ex:121-125` (`create_support_plan/1`)
- Modify: `lib/ayumi/plans.ex:423-441` (`validate_active_service_user/1` → `/2` へ一般化)
- Modify: `lib/ayumi/plans.ex:367-373` (`create_support_record/2` の呼び出し更新)

**Interfaces:**
- Consumes: `withdrawn_service_user?/1`（変更なし、再利用）
- Produces: `validate_active_service_user/2`（メッセージ引数付き private 関数）

- [ ] **Step 1: `validate_active_service_user/1` を `/2` に一般化する**

`lib/ayumi/plans.ex` の 423 行目付近を以下に変更:

```elixir
defp validate_active_service_user(%Ecto.Changeset{valid?: false} = changeset, _message),
  do: changeset

defp validate_active_service_user(changeset, message) do
  case Ecto.Changeset.get_field(changeset, :service_user_id) do
    nil ->
      changeset

    id ->
      if withdrawn_service_user?(id) do
        Ecto.Changeset.add_error(
          changeset,
          :service_user_id,
          message
        )
      else
        changeset
      end
  end
end
```

- [ ] **Step 2: `create_support_record/2` の呼び出しをメッセージ引数付きに更新する**

`lib/ayumi/plans.ex` の 371 行目付近:

```elixir
def create_support_record(%Scope{} = scope, attrs) when is_map(attrs) do
  %SupportRecord{}
  |> SupportRecord.changeset(attrs)
  |> SupportRecord.put_audit(scope.user.id, DateTime.utc_now(:second))
  |> validate_active_service_user("退所者には支援記録を作成できません")
  |> insert_support_record()
end
```

- [ ] **Step 3: `create_support_plan/1` にガードを挿入する**

`lib/ayumi/plans.ex` の 121 行目付近:

```elixir
def create_support_plan(attrs) do
  %SupportPlan{}
  |> SupportPlan.changeset(attrs)
  |> validate_active_service_user("退所者には支援計画を作成できません")
  |> Repo.insert()
end
```

- [ ] **Step 4: Task 1 の context テストが通ることを確認する**

Run: `mix test test/ayumi/plans_test.exs`
Expected: ALL PASS（新規テスト含む既存テスト全て通る）

- [ ] **Step 5: Task 2 の TOCTOU テストが通ることを確認する**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs`
Expected: ALL PASS（新規 TOCTOU テスト含む）

- [ ] **Step 6: Med-2 の支援記録テストが壊れていないことを確認する**

Run: `mix test test/ayumi/plans_test.exs`
Expected: support records の退所拒否テスト・在籍者作成テスト全て PASS（メッセージ文言を引数に移しただけなので挙動は同一。Med-2 のテストはメッセージ文言をアサートしていない）

---

### Task 4: 品質ゲート通過とコミット

**Files:**
- なし（全変更は Task 1〜3 で完了）

- [ ] **Step 1: `mix review` を実行する**

Run: `mix review`
Expected: format / compile --warnings-as-errors / credo / test 全て PASS

- [ ] **Step 2: 差分が 3 ファイルのみであることを確認する**

Run: `git diff --stat`
Expected: 変更ファイルが以下の 3 つだけ:
- `test/ayumi/plans_test.exs`
- `test/ayumi_web/live/support_plan_live_test.exs`
- `lib/ayumi/plans.ex`

- [ ] **Step 3: コミットする**

```bash
git add test/ayumi/plans_test.exs test/ayumi_web/live/support_plan_live_test.exs lib/ayumi/plans.ex
git commit -m "fix: guard create_support_plan against withdrawn service users (TOCTOU)"
```

---

## 受け入れ条件チェックリスト

- [ ] context テスト: `create_support_plan/1` が退所者で `{:error, changeset}` を返す
- [ ] TOCTOU テスト: フォーム表示後に退所 → submit しても計画が作成されない
- [ ] Med-2 の支援記録テスト（在籍者作成・退所拒否）グリーン維持
- [ ] 既存の support_plan / service_user LiveView テスト グリーン維持
- [ ] `mix review` グリーン
- [ ] 差分は 3 ファイルのみ
