# 実績記録票 増分1 — 出欠データ基盤＋月次集計の純関数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** サービス提供実績記録票の追記専用ログ `attendance_record` と、月次の記録票をログから畳み込んで導出する純関数 `build_attendance_sheet/3` までを TDD で実装する。UI・印刷・上限算定はやらない。

**Architecture:** 既存の `support_record` 一式（schema / context / fixture / 監査付与）を参照実装とし、命名・構造・FK エラー整形を同型で揃える。current state は保存せず、`id` 昇順の畳み込みで導出する pure function (`fold_attendance_sheet/4`, `totals_from/1`) を `Plans` context に置く。1点だけ意図的に変える：`validate_active_service_user`（退所者ブロック）は `attendance_record` には**付けない**（退所月の実績を後から確定する運用があるため）。

**Tech Stack:** Elixir 1.18 / Phoenix / Phoenix LiveView / Ecto + ecto_sqlite3 / ExUnit / Credo / Sobelow / Dialyzer。仕様書: `/Users/hiro/Desktop/ayumi_increment1_attendance.md`。

## Global Constraints

- **Append-only 厳守**：既存行を上書きする `update`/`delete` は書かない。訂正も新しい行で表現。
- **「最新行」は `id` 最大で決定**：同一秒の連続 insert があり得るため `recorded_at` で並べない（既存コードベースの方針）。
- **退所者ブロックは付けない（意図的差分）**：参照実装 `create_support_record/2` の `validate_active_service_user/2` は `attendance_record` には**コピーしない**。月途中退所者の当月分記録は正当。
- **報酬単価・加算上限は埋め込まない**：欠席時対応の月回数上限、施設外支援の日数上限などは**強制しない**。アプリは数えて提示するだけ。改定耐性のため。
- **食事提供フィールドは作らない**：事業所運用にないため。
- **`recorded_by_id` / `recorded_at` は `put_audit/3` で付与**：`scope.user.id` と `DateTime.utc_now(:second)` から入れる。
- **FK エラーは既存 private 関数を再利用**：`unnamed_foreign_key_constraint_error?/1`・`add_missing_assoc_error/3`・`assoc_exists?/2` は新規複製せず、`Plans` context 内のものを使う。
- **テストの非同期設定**：DB を触るテスト（context テスト）は `async: false`（SQLite single-writer）。DB を触らないテスト（純関数テスト、enum テスト、changeset 単体テスト）は `async: true`。
- **コード識別子・コメントは英語、UI 文言は日本語**（このプランは UI 範囲外なので主に英語識別子＋エラーメッセージ日本語のみ）。
- **完了条件**：`mix review`（format / warnings as errors / Credo / Sobelow / Dialyzer / test）が green。
- **スコープ外**：LiveView、入力画面、印刷／PDF／CSV、報酬算定、既存スキーマ変更（`service_user` 等）。

## File Structure

| ファイル | 役割 | 新規/編集 |
|---|---|---|
| `lib/ayumi/plans/provision_type.ex` | サービス提供形態 enum + `billable/0` | 新規 |
| `lib/ayumi/plans/attendance_record.ex` | append-only schema + changeset + `put_audit/3` + `validate_time_order/1` | 新規 |
| `lib/ayumi/plans/attendance_sheet.ex` | 1利用者・1か月の記録票を表す純データ構造体 | 新規 |
| `priv/repo/migrations/<ts>_create_attendance_records.exs` | テーブル＋複合 index | 新規 |
| `lib/ayumi/plans.ex` | `change_attendance_record/2`, `create_attendance_record/2`, `list_attendance_records/3`, `build_attendance_sheet/3` と private `insert_attendance_record/1`, `add_attendance_record_foreign_key_errors/1`, `month_bounds/2`, `fold_attendance_sheet/4`, `totals_from/1` | 編集（追記） |
| `test/ayumi/plans/enumerations_test.exs` | `ProvisionType` describe ブロック追加 | 編集 |
| `test/ayumi/plans/attendance_record_test.exs` | changeset + context + 畳み込みテスト | 新規 |
| `test/support/fixtures/plans_fixtures.ex` | `attendance_record_fixture/1` | 編集（追記） |

---

## Task 1: `ProvisionType` enum

**Files:**
- Create: `lib/ayumi/plans/provision_type.ex`
- Modify: `test/ayumi/plans/enumerations_test.exs`

**Interfaces:**
- Consumes: なし
- Produces:
  - `Ayumi.Plans.ProvisionType.all/0 :: [:commute | :offsite_work | :offsite_support | :absence | :absence_support]`
  - `Ayumi.Plans.ProvisionType.label/1 :: (atom() | nil) -> String.t() | nil`
  - `Ayumi.Plans.ProvisionType.options/0 :: [{String.t(), atom()}]`
  - `Ayumi.Plans.ProvisionType.billable/0 :: [:commute | :offsite_work | :offsite_support]`

- [ ] **Step 1: 失敗するテストを追加（`enumerations_test.exs` 末尾の `end` 直前に describe を1つ足す）**

ファイル末尾の最終 `end` の直前に以下を挿入する。`alias` 行も `ProvisionType` を含むよう更新する。

```elixir
  # alias 行を以下に置き換える：
  alias Ayumi.Plans.{
    CertificateKind,
    Gender,
    GoalProgressStage,
    PlanPhaseStage,
    ProvisionType,
    SupportCategory
  }

  # 末尾 end の直前に追加：
  describe "ProvisionType" do
    test "all/0 lists values in display order" do
      assert ProvisionType.all() == [
               :commute,
               :offsite_work,
               :offsite_support,
               :absence,
               :absence_support
             ]
    end

    test "label/1 maps values to Japanese" do
      assert ProvisionType.label(:commute) == "通所"
      assert ProvisionType.label(:offsite_work) == "施設外就労"
      assert ProvisionType.label(:offsite_support) == "施設外支援"
      assert ProvisionType.label(:absence) == "欠席"
      assert ProvisionType.label(:absence_support) == "欠席時対応"
    end

    test "label/1 returns nil for unknown or nil" do
      assert ProvisionType.label(nil) == nil
      assert ProvisionType.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"通所", :commute} in ProvisionType.options()
      assert length(ProvisionType.options()) == 5
    end

    test "billable/0 lists only commute / offsite_work / offsite_support" do
      assert ProvisionType.billable() == [:commute, :offsite_work, :offsite_support]
    end
  end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/enumerations_test.exs
```
Expected: `(CompileError) module Ayumi.Plans.ProvisionType is not loaded` で失敗。

- [ ] **Step 3: `ProvisionType` を実装**

新規作成 `lib/ayumi/plans/provision_type.ex`:

```elixir
defmodule Ayumi.Plans.ProvisionType do
  @moduledoc "サービス提供形態（実績記録票）。ラベルはここに集約し、view に散らさない。"

  @labels [
    commute: "通所",
    offsite_work: "施設外就労",
    offsite_support: "施設外支援",
    absence: "欠席",
    absence_support: "欠席時対応"
  ]

  @doc "全値（表示順）。"
  def all, do: Keyword.keys(@labels)

  @doc "値の日本語ラベル。未知/nil は nil。"
  def label(value), do: Keyword.get(@labels, value)

  @doc "`<.input type=\"select\">` 用の `[{label, value}]`。"
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)

  @doc "利用日数の算定対象となる提供形態。"
  def billable, do: [:commute, :offsite_work, :offsite_support]
end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/enumerations_test.exs --only describe:ProvisionType
mix test test/ayumi/plans/enumerations_test.exs
```
Expected: 5 tests, 0 failures（追加分）/ 全体 green。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans/provision_type.ex test/ayumi/plans/enumerations_test.exs
git commit -m "feat: add ProvisionType enum for attendance records"
```

---

## Task 2: `AttendanceRecord` schema + changeset

**Files:**
- Create: `lib/ayumi/plans/attendance_record.ex`
- Create: `test/ayumi/plans/attendance_record_test.exs`

**Interfaces:**
- Consumes: `Ayumi.Plans.ProvisionType.all/0`（Task 1）
- Produces:
  - `%Ayumi.Plans.AttendanceRecord{}` schema（`attendance_records` テーブル）
  - `Ayumi.Plans.AttendanceRecord.changeset/2 :: (struct, map) -> Ecto.Changeset.t()`
  - `Ayumi.Plans.AttendanceRecord.put_audit/3 :: (Ecto.Changeset.t(), integer(), DateTime.t()) -> Ecto.Changeset.t()`

> NOTE: このタスクの changeset テストは DB に触らないので `async: true` でよい。`%AttendanceRecord{}` を直接 changeset に渡す。テーブルは Task 3 で作る。

- [ ] **Step 1: changeset の失敗するテストを書く**

新規作成 `test/ayumi/plans/attendance_record_test.exs`:

```elixir
defmodule Ayumi.Plans.AttendanceRecordTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.AttendanceRecord

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "with valid minimum attrs is valid" do
      attrs = %{
        service_user_id: 1,
        service_date: ~D[2026-06-01],
        provision_type: :commute
      }

      cs = AttendanceRecord.changeset(%AttendanceRecord{}, attrs)
      assert cs.valid?
      assert get_change_or_field(cs, :pickup) == false
      assert get_change_or_field(cs, :dropoff) == false
    end

    test "requires service_user_id / service_date / provision_type" do
      cs = AttendanceRecord.changeset(%AttendanceRecord{}, %{})
      errors = errors_on(cs)
      assert errors[:service_user_id]
      assert errors[:service_date]
      assert errors[:provision_type]
    end

    test "rejects provision_type outside of the enum" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :bogus
        })

      refute cs.valid?
      assert errors_on(cs)[:provision_type]
    end

    test "allows both start_time and end_time nil" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })

      assert cs.valid?
    end

    test "rejects end_time on or before start_time" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          start_time: ~T[10:00:00],
          end_time: ~T[10:00:00]
        })

      refute cs.valid?
      assert errors_on(cs)[:end_time] == ["終了時刻は開始時刻より後にしてください"]
    end

    test "accepts pickup / dropoff true" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :pickup) == true
      assert Ecto.Changeset.get_field(cs, :dropoff) == true
    end
  end

  describe "put_audit/3" do
    test "puts recorded_by_id and recorded_at" do
      cs =
        %AttendanceRecord{}
        |> AttendanceRecord.changeset(%{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })
        |> AttendanceRecord.put_audit(42, ~U[2026-06-21 12:00:00Z])

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :recorded_by_id) == 42
      assert Ecto.Changeset.get_field(cs, :recorded_at) == ~U[2026-06-21 12:00:00Z]
    end
  end

  defp get_change_or_field(cs, field) do
    Map.get(cs.changes, field, Map.get(cs.data, field))
  end
end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: `module Ayumi.Plans.AttendanceRecord is not loaded` か `is not available` で失敗。

- [ ] **Step 3: schema + changeset を実装**

新規作成 `lib/ayumi/plans/attendance_record.ex`:

```elixir
defmodule Ayumi.Plans.AttendanceRecord do
  @moduledoc "An append-only daily attendance / service-provision record for a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.ProvisionType

  @user_fields [
    :service_user_id,
    :service_date,
    :provision_type,
    :pickup,
    :dropoff,
    :start_time,
    :end_time,
    :note
  ]
  @required [:service_user_id, :service_date, :provision_type]
  @audit_fields [:recorded_by_id, :recorded_at]

  schema "attendance_records" do
    field :service_date, :date
    field :provision_type, Ecto.Enum, values: ProvisionType.all()
    field :pickup, :boolean, default: false
    field :dropoff, :boolean, default: false
    field :start_time, :time
    field :end_time, :time
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :service_user, Ayumi.Plans.ServiceUser
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(attendance_record, attrs) do
    attendance_record
    |> cast(attrs, @user_fields)
    |> validate_required(@required)
    |> validate_inclusion(:provision_type, ProvisionType.all())
    |> validate_time_order()
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def put_audit(changeset, recorded_by_id, recorded_at) do
    changeset
    |> put_change(:recorded_by_id, recorded_by_id)
    |> put_change(:recorded_at, recorded_at)
    |> validate_required(@audit_fields)
  end

  defp validate_time_order(changeset) do
    start_t = get_field(changeset, :start_time)
    end_t = get_field(changeset, :end_time)

    if start_t && end_t && Time.compare(end_t, start_t) != :gt do
      add_error(changeset, :end_time, "終了時刻は開始時刻より後にしてください")
    else
      changeset
    end
  end
end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: 7 tests, 0 failures。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans/attendance_record.ex test/ayumi/plans/attendance_record_test.exs
git commit -m "feat: add AttendanceRecord schema and changeset"
```

---

## Task 3: Migration `create_attendance_records`

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_attendance_records.exs`

**Interfaces:**
- Consumes: 既存 `service_users` / `users` テーブル
- Produces: `attendance_records` テーブル＋`(service_user_id, service_date)` 複合 index。

- [ ] **Step 1: migration ファイルを生成**

```bash
mix ecto.gen.migration create_attendance_records
```
Expected: `priv/repo/migrations/<YYYYMMDDHHMMSS>_create_attendance_records.exs` が生成される。

- [ ] **Step 2: 生成された migration の中身を書き換える**

```elixir
defmodule Ayumi.Repo.Migrations.CreateAttendanceRecords do
  use Ecto.Migration

  def change do
    create table(:attendance_records) do
      add :service_user_id, references(:service_users, on_delete: :restrict), null: false
      add :service_date, :date, null: false
      add :provision_type, :string, null: false
      add :pickup, :boolean, null: false, default: false
      add :dropoff, :boolean, null: false, default: false
      add :start_time, :time
      add :end_time, :time
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:attendance_records, [:service_user_id, :service_date])
  end
end
```

- [ ] **Step 3: dev / test DB に migration を適用**

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```
Expected: `* running CHANGE forward` のログ、エラーなし。

- [ ] **Step 4: 既存テストが壊れていないことを確認**

```bash
mix test
```
Expected: 全テスト green（Task 2 までと既存全部）。

- [ ] **Step 5: コミット**

```bash
git add priv/repo/migrations/
git commit -m "feat: add attendance_records table migration"
```

---

## Task 4: `AttendanceSheet` 純データ構造体

**Files:**
- Create: `lib/ayumi/plans/attendance_sheet.ex`

**Interfaces:**
- Consumes: なし
- Produces:
  - `%Ayumi.Plans.AttendanceSheet{service_user_id, year, month, lines, totals}` 構造体
  - 型: `t :: %__MODULE__{...}`, `line :: %{date, record}`, `totals :: %{billable_days, offsite_days, pickup_count, dropoff_count, absence_support_count}`

> NOTE: pure data 構造体なのでテストは省略（typespec とコンパイル成功で十分）。利用は Task 7 でカバーする。

- [ ] **Step 1: 構造体を作成**

新規作成 `lib/ayumi/plans/attendance_sheet.ex`:

```elixir
defmodule Ayumi.Plans.AttendanceSheet do
  @moduledoc "1利用者・1か月の実績記録票（ログから導出した値。保存しない）。"
  @enforce_keys [:service_user_id, :year, :month, :lines, :totals]
  defstruct [:service_user_id, :year, :month, :lines, :totals]

  @type line :: %{date: Date.t(), record: Ayumi.Plans.AttendanceRecord.t() | nil}
  @type totals :: %{
          billable_days: non_neg_integer(),
          offsite_days: non_neg_integer(),
          pickup_count: non_neg_integer(),
          dropoff_count: non_neg_integer(),
          absence_support_count: non_neg_integer()
        }
  @type t :: %__MODULE__{
          service_user_id: integer(),
          year: integer(),
          month: integer(),
          lines: [line()],
          totals: totals()
        }
end
```

- [ ] **Step 2: コンパイル確認**

```bash
mix compile --warnings-as-errors
```
Expected: warnings 0、エラーなし。

- [ ] **Step 3: コミット**

```bash
git add lib/ayumi/plans/attendance_sheet.ex
git commit -m "feat: add AttendanceSheet struct for monthly attendance derivation"
```

---

## Task 5: `change_attendance_record/2` と `create_attendance_record/2`

**Files:**
- Modify: `lib/ayumi/plans.ex`（alias 追加＋関数追記）
- Modify: `test/ayumi/plans/attendance_record_test.exs`（context describe を追加）

**Interfaces:**
- Consumes:
  - `Ayumi.Accounts.Scope`, `Ayumi.Plans.AttendanceRecord`, `Ayumi.Plans.ProvisionType`（Tasks 1–2）
  - 既存 private: `unnamed_foreign_key_constraint_error?/1`, `add_missing_assoc_error/3`, `assoc_exists?/2`
- Produces:
  - `Ayumi.Plans.change_attendance_record/2 :: (%AttendanceRecord{}, map) -> Ecto.Changeset.t()`
  - `Ayumi.Plans.create_attendance_record/2 :: (%Scope{}, map) -> {:ok, %AttendanceRecord{}} | {:error, Ecto.Changeset.t()}`
- Intentional difference from `create_support_record/2`: **`validate_active_service_user/2` を付けない**。

- [ ] **Step 1: 失敗する context テストを追記**

`test/ayumi/plans/attendance_record_test.exs` の末尾 `end` の直前に以下を追加。冒頭の `use` も `Ayumi.DataCase, async: false` に**置き換え**、fixtures を import する。`Ayumi.DataCase` は `errors_on/1` を提供するので Step 1 で書いた private `errors_on/1` は**削除**する。

ファイル全体の差し替え骨格:

```elixir
defmodule Ayumi.Plans.AttendanceRecordTest do
  use Ayumi.DataCase, async: false

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.Plans
  alias Ayumi.Plans.AttendanceRecord

  # Task 2 で書いた changeset / put_audit の describe はそのまま残す
  # （private errors_on/1 は削除、DataCase の関数を使う）

  describe "create_attendance_record/2" do
    test "inserts a record with scope-derived audit fields" do
      su = service_user_fixture()
      staff = user_fixture()
      scope = Scope.for_user(staff)

      assert {:ok, %AttendanceRecord{} = rec} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: su.id,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })

      assert rec.service_user_id == su.id
      assert rec.provision_type == :commute
      assert rec.recorded_by_id == staff.id
      assert %DateTime{} = rec.recorded_at
    end

    test "allows recording for a withdrawn service user (intentional diff vs support_record)" do
      su = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})
      scope = Scope.for_user(user_fixture())

      assert {:ok, _rec} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: su.id,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })
    end

    test "returns FK error changeset for an unknown service_user_id" do
      scope = Scope.for_user(user_fixture())

      assert {:error, cs} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: -1,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })

      assert errors_on(cs)[:service_user_id]
    end
  end

  describe "change_attendance_record/2" do
    test "returns a changeset for empty attrs" do
      cs = Plans.change_attendance_record(%AttendanceRecord{})
      assert %Ecto.Changeset{} = cs
    end
  end
end
```

> NOTE: changeset describe を残すために `use Ayumi.DataCase` を併用する。`DataCase` は `async: false` の Sandbox を立てるが、changeset 単体テストでも問題なく動く（DB は触らない）。

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: `Ayumi.Plans.change_attendance_record/2 is undefined` 等で失敗。

- [ ] **Step 3: `lib/ayumi/plans.ex` に alias と関数を追記**

ファイル先頭の `alias Ayumi.Plans.SupportRecord` の直後に以下を追加:

```elixir
  alias Ayumi.Plans.AttendanceRecord
  alias Ayumi.Plans.ProvisionType
```

> NOTE: `ProvisionType` の alias はこの時点では未使用警告にならない（Task 7 の `build_attendance_sheet` で使う）。気になるなら Task 7 で同時に足してもよい。warnings-as-errors を回避するため、Task 5 では `AttendanceRecord` のみ alias し、`ProvisionType` は Task 7 で追加する方が安全。

修正: ここでは `AttendanceRecord` の alias のみ追加する。

```elixir
  alias Ayumi.Plans.AttendanceRecord
```

次に、`create_support_record` 関連の関数群の直後（参照実装の隣）に以下を追記:

```elixir
  ## Attendance records

  @doc "Returns a changeset for an attendance record (forms)."
  def change_attendance_record(%AttendanceRecord{} = record, attrs \\ %{}) do
    AttendanceRecord.changeset(record, attrs)
  end

  @doc """
  Creates an attendance record.

  `recorded_by_id` / `recorded_at` are set from `scope.user.id` and the wall clock.
  Unlike `create_support_record/2`, this **does not** block withdrawn service users —
  the monthly attendance sheet for the month of withdrawal must still be recordable.
  """
  def create_attendance_record(%Scope{} = scope, attrs) when is_map(attrs) do
    %AttendanceRecord{}
    |> AttendanceRecord.changeset(attrs)
    |> AttendanceRecord.put_audit(scope.user.id, DateTime.utc_now(:second))
    |> insert_attendance_record()
  end

  defp insert_attendance_record(changeset) do
    Repo.insert(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      if unnamed_foreign_key_constraint_error?(exception) do
        changeset = add_attendance_record_foreign_key_errors(changeset)

        if changeset.valid?, do: reraise(exception, __STACKTRACE__), else: {:error, changeset}
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp add_attendance_record_foreign_key_errors(changeset) do
    changeset
    |> add_missing_assoc_error(:service_user_id, ServiceUser)
    |> add_missing_assoc_error(:recorded_by_id, User)
  end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
mix test
```
Expected: 新規 4 テスト含めて全部 pass。既存テストは引き続き green。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans/attendance_record_test.exs
git commit -m "feat: add create_attendance_record/2 (no withdrawn-user block)"
```

---

## Task 6: `list_attendance_records/3` と `month_bounds/2`

**Files:**
- Modify: `lib/ayumi/plans.ex`
- Modify: `test/ayumi/plans/attendance_record_test.exs`

**Interfaces:**
- Consumes: `Ayumi.Plans.AttendanceRecord`, `Ayumi.Plans.create_attendance_record/2`（Task 5）
- Produces:
  - `Ayumi.Plans.list_attendance_records/3 :: (integer(), integer(), integer()) -> [%AttendanceRecord{}]`（指定月の全行、`id` 昇順）
  - private `Ayumi.Plans.month_bounds/2 :: (integer(), integer()) -> {Date.t(), Date.t()}`（同ファイル内）

- [ ] **Step 1: 失敗するテストを追記**

`attendance_record_test.exs` の末尾 `end` の直前に追加:

```elixir
  describe "list_attendance_records/3" do
    test "returns only rows in the requested month, oldest-first by id" do
      su = service_user_fixture()
      scope = Scope.for_user(user_fixture())

      {:ok, before_rec} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-05-31],
          provision_type: :commute
        })

      {:ok, jun1} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })

      {:ok, jun30} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-30],
          provision_type: :absence
        })

      {:ok, after_rec} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-07-01],
          provision_type: :commute
        })

      ids = Plans.list_attendance_records(su.id, 2026, 6) |> Enum.map(& &1.id)
      assert ids == [jun1.id, jun30.id]
      refute before_rec.id in ids
      refute after_rec.id in ids
    end

    test "scopes by service_user_id" do
      su1 = service_user_fixture()
      su2 = service_user_fixture(%{name: "別の人", name_kana: "べつのひと"})
      scope = Scope.for_user(user_fixture())

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su1.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su2.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute
        })

      assert length(Plans.list_attendance_records(su1.id, 2026, 6)) == 1
      assert length(Plans.list_attendance_records(su2.id, 2026, 6)) == 1
    end
  end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: `Ayumi.Plans.list_attendance_records/3 is undefined` で失敗。

- [ ] **Step 3: `list_attendance_records/3` と `month_bounds/2` を実装**

`Plans` の `## Attendance records` セクション末尾に追加:

```elixir
  @doc """
  Lists raw attendance rows for `service_user_id` within `year` / `month`,
  oldest-first by `id`. The fold for `build_attendance_sheet/3` consumes this order.
  """
  def list_attendance_records(service_user_id, year, month)
      when is_integer(service_user_id) and is_integer(year) and is_integer(month) do
    {first, last} = month_bounds(year, month)

    AttendanceRecord
    |> where([r], r.service_user_id == ^service_user_id)
    |> where([r], r.service_date >= ^first and r.service_date <= ^last)
    |> order_by([r], asc: r.id)
    |> Repo.all()
  end

  defp month_bounds(year, month) do
    first = Date.new!(year, month, 1)
    last = Date.end_of_month(first)
    {first, last}
  end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: 新規 2 テスト含め全部 pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans/attendance_record_test.exs
git commit -m "feat: add list_attendance_records/3 with month_bounds helper"
```

---

## Task 7: `build_attendance_sheet/3` 純関数 + `fold_attendance_sheet/4` + `totals_from/1`

**Files:**
- Modify: `lib/ayumi/plans.ex`
- Modify: `test/ayumi/plans/attendance_record_test.exs`

**Interfaces:**
- Consumes: `list_attendance_records/3`（Task 6）、`AttendanceRecord`、`AttendanceSheet`、`ProvisionType.billable/0`
- Produces:
  - `Ayumi.Plans.build_attendance_sheet/3 :: (integer(), integer(), integer()) -> %AttendanceSheet{}`
  - private `Ayumi.Plans.fold_attendance_sheet/4 :: (integer(), integer(), integer(), [%AttendanceRecord{}]) -> %AttendanceSheet{}`
  - private `Ayumi.Plans.totals_from/1 :: ([%{date: Date.t(), record: %AttendanceRecord{} | nil}]) -> map`
- 畳み込み規則:
  - 同日の複数行は `id` 最大を「最新（採用）」とする
  - 月の全日分の `lines` を返す。記録なしは `record: nil`
  - `billable_days` = 採用行の `provision_type` が `ProvisionType.billable/0` に含まれる日数
  - `offsite_days` = `:offsite_work` または `:offsite_support` の日数
  - `pickup_count` / `dropoff_count` = 採用行で `pickup`/`dropoff` true の数
  - `absence_support_count` = `:absence_support` の日数

- [ ] **Step 1: 失敗するテストを追記**

`attendance_record_test.exs` の末尾 `end` の直前に追加。`Ayumi.Plans.AttendanceSheet` の alias も冒頭に足す。

冒頭 alias 行（既存）を以下に置き換え:

```elixir
  alias Ayumi.Plans.{AttendanceRecord, AttendanceSheet}
```

テスト追加:

```elixir
  describe "build_attendance_sheet/3" do
    setup do
      su = service_user_fixture()
      scope = Scope.for_user(user_fixture())
      %{su: su, scope: scope}
    end

    test "lines cover every day of a 30-day month", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert %AttendanceSheet{year: 2026, month: 6, service_user_id: su_id} = sheet
      assert su_id == su.id
      assert length(sheet.lines) == 30
      assert hd(sheet.lines).date == ~D[2026-06-01]
      assert List.last(sheet.lines).date == ~D[2026-06-30]
    end

    test "lines cover every day of a 31-day month", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 7)
      assert length(sheet.lines) == 31
    end

    test "lines cover every day of February (non-leap 2026)", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 2)
      assert length(sheet.lines) == 28
    end

    test "days without rows have record: nil and do not count toward totals", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert Enum.all?(sheet.lines, &is_nil(&1.record))
      assert sheet.totals == %{
               billable_days: 0,
               offsite_days: 0,
               pickup_count: 0,
               dropoff_count: 0,
               absence_support_count: 0
             }
    end

    test "later id wins for the same service_date (correction semantics)",
         %{su: su, scope: scope} do
      {:ok, _first} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-15],
          provision_type: :absence
        })

      {:ok, correction} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-15],
          provision_type: :commute
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      jun15 = Enum.find(sheet.lines, &(&1.date == ~D[2026-06-15]))
      assert jun15.record.id == correction.id
      assert jun15.record.provision_type == :commute
    end

    test "billable_days counts only commute / offsite_work / offsite_support",
         %{su: su, scope: scope} do
      for {date, type} <- [
            {~D[2026-06-01], :commute},
            {~D[2026-06-02], :offsite_work},
            {~D[2026-06-03], :offsite_support},
            {~D[2026-06-04], :absence},
            {~D[2026-06-05], :absence_support}
          ] do
        {:ok, _} =
          Plans.create_attendance_record(scope, %{
            service_user_id: su.id,
            service_date: date,
            provision_type: type
          })
      end

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.billable_days == 3
      assert sheet.totals.offsite_days == 2
      assert sheet.totals.absence_support_count == 1
    end

    test "pickup_count and dropoff_count count adopted rows only",
         %{su: su, scope: scope} do
      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-02],
          provision_type: :commute,
          pickup: true,
          dropoff: false
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.pickup_count == 2
      assert sheet.totals.dropoff_count == 1
    end

    test "correction overwrites prior pickup/dropoff in counts",
         %{su: su, scope: scope} do
      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-10],
          provision_type: :absence,
          pickup: false,
          dropoff: false
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.pickup_count == 0
      assert sheet.totals.dropoff_count == 0
      assert sheet.totals.billable_days == 0
    end
  end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: `Ayumi.Plans.build_attendance_sheet/3 is undefined` で失敗。

- [ ] **Step 3: `build_attendance_sheet/3` ＋ private 純関数を実装**

`lib/ayumi/plans.ex` 先頭 alias 群に追加:

```elixir
  alias Ayumi.Plans.AttendanceSheet
  alias Ayumi.Plans.ProvisionType
```

`## Attendance records` セクション末尾に追加:

```elixir
  @doc """
  Builds a monthly attendance sheet for a service user by folding the
  append-only log. The sheet is derived, not stored.
  """
  def build_attendance_sheet(service_user_id, year, month)
      when is_integer(service_user_id) and is_integer(year) and is_integer(month) do
    rows = list_attendance_records(service_user_id, year, month)
    fold_attendance_sheet(service_user_id, year, month, rows)
  end

  defp fold_attendance_sheet(service_user_id, year, month, rows) do
    latest_by_date =
      rows
      |> Enum.group_by(& &1.service_date)
      |> Map.new(fn {date, rs} -> {date, Enum.max_by(rs, & &1.id)} end)

    {first, _last} = month_bounds(year, month)
    days = Date.days_in_month(first)

    lines =
      for day <- 1..days do
        date = Date.new!(year, month, day)
        %{date: date, record: Map.get(latest_by_date, date)}
      end

    %AttendanceSheet{
      service_user_id: service_user_id,
      year: year,
      month: month,
      lines: lines,
      totals: totals_from(lines)
    }
  end

  defp totals_from(lines) do
    billable = ProvisionType.billable()
    offsite = [:offsite_work, :offsite_support]

    Enum.reduce(
      lines,
      %{
        billable_days: 0,
        offsite_days: 0,
        pickup_count: 0,
        dropoff_count: 0,
        absence_support_count: 0
      },
      fn
        %{record: nil}, acc ->
          acc

        %{record: rec}, acc ->
          acc
          |> Map.update!(:billable_days, &(&1 + bool_to_int(rec.provision_type in billable)))
          |> Map.update!(:offsite_days, &(&1 + bool_to_int(rec.provision_type in offsite)))
          |> Map.update!(:pickup_count, &(&1 + bool_to_int(rec.pickup)))
          |> Map.update!(:dropoff_count, &(&1 + bool_to_int(rec.dropoff)))
          |> Map.update!(
            :absence_support_count,
            &(&1 + bool_to_int(rec.provision_type == :absence_support))
          )
      end
    )
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
mix test
```
Expected: 新規 8 テスト含め全部 pass。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans/attendance_record_test.exs
git commit -m "feat: derive monthly attendance sheet by folding the log"
```

---

## Task 8: `attendance_record_fixture/1`

**Files:**
- Modify: `test/support/fixtures/plans_fixtures.ex`

**Interfaces:**
- Consumes: `Plans.create_attendance_record/2`、`service_user_fixture/1`、`user_fixture/0`
- Produces: `Ayumi.PlansFixtures.attendance_record_fixture/1 :: (map | keyword) -> %AttendanceRecord{}`

- [ ] **Step 1: 既存 fixture テストの薄いサニティを attendance_record_test.exs に1本だけ追加（fixture 経由の最小確認）**

`attendance_record_test.exs` の末尾 `end` の直前に追加:

```elixir
  describe "attendance_record_fixture/1" do
    test "creates a default commute record on 2026-06-01" do
      rec = attendance_record_fixture()
      assert rec.service_date == ~D[2026-06-01]
      assert rec.provision_type == :commute
    end

    test "accepts overrides for service_user_id and provision_type" do
      su = service_user_fixture()
      rec = attendance_record_fixture(%{service_user_id: su.id, provision_type: :absence})
      assert rec.service_user_id == su.id
      assert rec.provision_type == :absence
    end
  end
```

- [ ] **Step 2: テスト実行で失敗を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
```
Expected: `undefined function attendance_record_fixture/0` 等で失敗。

- [ ] **Step 3: `attendance_record_fixture/1` を追記**

`test/support/fixtures/plans_fixtures.ex` の `support_record_fixture/1` の直後（または `plan_phase_event_fixture/1` の前）に挿入:

```elixir
  def attendance_record_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    service_user_id = Map.get(attrs, :service_user_id) || service_user_fixture().id
    recorded_by = Map.get(attrs, :recorded_by) || user_fixture()
    scope = Ayumi.Accounts.Scope.for_user(recorded_by)

    defaults = %{
      service_user_id: service_user_id,
      service_date: ~D[2026-06-01],
      provision_type: :commute
    }

    {:ok, record} =
      Plans.create_attendance_record(scope, Map.merge(defaults, Map.drop(attrs, [:recorded_by])))

    record
  end
```

- [ ] **Step 4: テスト実行で green を確認**

```bash
mix test test/ayumi/plans/attendance_record_test.exs
mix test
```
Expected: 全部 pass。

- [ ] **Step 5: コミット**

```bash
git add test/support/fixtures/plans_fixtures.ex test/ayumi/plans/attendance_record_test.exs
git commit -m "test: add attendance_record_fixture/1"
```

---

## Task 9: `mix review` 完走と完了報告

**Files:** なし（quality gate のみ）

**Interfaces:** なし

- [ ] **Step 1: 品質ゲートを通す**

```bash
mix review
```
Expected: format check OK / compile warnings-as-errors OK / Credo OK / Sobelow OK / Dialyzer OK / `mix test` 全 green。

- [ ] **Step 2: 失敗があれば修正（fix 専用の小さなコミットに切る）**

例:
- format: `mix format`
- credo: 該当箇所を最小差分で修正
- dialyzer: `@spec` 不足や型不整合を解消

修正ごとに:
```bash
git add <修正したファイル>
git commit -m "chore: appease <tool> for attendance record changes"
```

- [ ] **Step 3: 変更ファイル一覧と「なぜ」をまとめて報告**

報告フォーマット:
- `lib/ayumi/plans/provision_type.ex` — サービス提供形態 enum＋`billable/0` を分離（ラベル集約・改定耐性）
- `lib/ayumi/plans/attendance_record.ex` — append-only schema＋`put_audit/3`＋`validate_time_order/1`
- `lib/ayumi/plans/attendance_sheet.ex` — 1利用者・1か月の記録票（保存しない pure data）
- `priv/repo/migrations/<ts>_create_attendance_records.exs` — テーブル＋`(service_user_id, service_date)` index
- `lib/ayumi/plans.ex` — `create_attendance_record/2`（退所者ブロックなし／意図的差分）と `list_attendance_records/3` と `build_attendance_sheet/3`（純関数で畳み込み）
- `test/ayumi/plans/enumerations_test.exs` — `ProvisionType` describe 追加
- `test/ayumi/plans/attendance_record_test.exs` — changeset＋context＋畳み込みの単体テスト
- `test/support/fixtures/plans_fixtures.ex` — `attendance_record_fixture/1` 追加

「気づいた将来課題（実装しない／列挙のみ）」も合わせて報告:
- 増分2: 入力 LiveView（`/attendance_records` の月別一覧＋日々の入力画面）
- 増分3: PDF/CSV/印刷出力
- 施設外支援の日数上限の表示（強制しない／注意喚起のみ）
- 削除や時刻入力 UX の整備
- ドキュメント反映（README / CLAUDE.md / CHANGELOG）は別パスで一括

- [ ] **Step 4: スコープ外チェック**

以下が**入っていない**ことを確認:
- LiveView ファイルの新規追加なし
- 報酬単価・加算上限のロジックなし
- 食事提供フィールドなし
- 既存 schema（`service_user` 等）の変更なし
- `support_record` 系の挙動変更なし

---

## Self-Review チェックリスト（実装者が最後に通す）

- [ ] 仕様書 1 〜 4 章（ゴール／パターン合わせ／意図的差分／TDD 手順）の項目すべてに対応タスクがある
- [ ] 仕様書「作るファイル 1〜5」が File Structure 表に揃っている
- [ ] 仕様書「書くテスト」の各 bullet がいずれかの Task のテストでカバーされている
  - changeset 必須／enum 外／時刻順序／pickup・dropoff 既定／put_audit → Task 2
  - 正常 append／退所者でも作れる／FK エラー → Task 5
  - 同日 2 行 id 最大採用 → Task 7（"later id wins"）
  - 月の全日 / 末日数（30/31/2 月） → Task 7
  - `billable_days` の対象 → Task 7
  - `offsite_days` 2 種合計／`pickup_count`／`dropoff_count`／`absence_support_count`／nil 除外 → Task 7
  - `ProvisionType.all/1`・`label/1`・`billable/1` → Task 1
- [ ] **退所者ブロックを `attendance_record` に付けていない**（参照実装からコピーしていない）
- [ ] FK エラー整形は既存 private 関数を**再利用**しており、新規複製していない
- [ ] `recorded_at` ではなく `id` で最新行を決めている
- [ ] LiveView／印刷／報酬上限／食事提供の実装が**ない**

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-21-attendance-record-increment-1.md`. 実装に進む際の選択肢:

1. **Subagent-Driven（推奨）** — Task ごとに新しい subagent を起動し、間にレビューを挟む。`superpowers:subagent-driven-development` を使う。
2. **Inline Execution** — このセッションで `superpowers:executing-plans` を使い、チェックポイントで止めながらバッチ実行する。

どちらで進めますか？
