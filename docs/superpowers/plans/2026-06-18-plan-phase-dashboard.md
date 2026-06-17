# Plan Phase Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add append-only support-plan lifecycle phase records and replace the authenticated top page with a monitoring-deadline dashboard.

**Architecture:** Keep lifecycle and deadline logic in `Ayumi.Plans`: enum labels, schema validation, append-only insert, chronological history, current-stage derivation, and monitoring-deadline classification. `SupportPlanLive.Show` records and renders phase events while staying thin; the new `DashboardLive.Index` only loads context data and renders it. No current phase is stored on `support_plans`; it is derived from the latest `plan_phase_events` row.

**Tech Stack:** Elixir, Phoenix 1.8, Phoenix LiveView, Ecto + `ecto_sqlite3`, SQLite, Gettext, ExUnit, Phoenix.LiveViewTest/LazyHTML. Verification uses the existing `mix review` and `mix precommit` aliases.

**Scope note:** This plan follows `TODO.md` Step 3 and `docs/superpowers/specs/2026-06-14-ayumi-design.md`. Step 2 `goal_progress` has already landed; this plan preserves that UI while adding plan-phase records and the dashboard. It does not implement role separation, emails, background jobs, OS notifications, mutable current-state columns, edit/delete UI for phase events, or facility-level settings screens.

**Prerequisite:** Step 2 is already on `main`. This Step 3 plan modifies `SupportPlanLive.Show`, so apply changes around the existing goal-progress form and history rather than replacing them.

**Router/auth placement:** Put the new dashboard route `live "/", DashboardLive.Index, :index` inside the existing `scope "/", AyumiWeb`, `pipe_through [:browser, :require_authenticated_user]`, and existing `live_session :require_authenticated_user`. The dashboard shows service-user and support-plan data, so it must require a logged-in staff user and receive `@current_scope` from `AyumiWeb.UserAuth`. Remove the public `get "/", PageController, :home` route so guests visiting `/` are redirected to `/users/log-in`.

---

## File Structure

- Modify: `test/ayumi/plans/enumerations_test.exs` - add `PlanPhaseStage` enum tests.
- Create: `lib/ayumi/plans/plan_phase_stage.ex` - ordered lifecycle enum and Japanese labels.
- Create: `priv/repo/migrations/20260618000000_create_plan_phase_events.exs` - append-only phase-event table.
- Create: `lib/ayumi/plans/plan_phase_event.ex` - schema and changeset for phase-event rows.
- Create: `test/ayumi/plans/plan_phase_event_test.exs` - changeset tests.
- Modify: `lib/ayumi/plans/support_plan.ex` - add `has_many :plan_phase_events`.
- Modify: `lib/ayumi/plans.ex` - context APIs for phase events and monitoring-deadline alerts.
- Modify: `test/ayumi/plans_test.exs` - context tests for phase derivation and dashboard query behavior.
- Modify: `test/support/fixtures/plans_fixtures.ex` - add `plan_phase_event_fixture/1`.
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex` - phase form, current phase, and history.
- Modify: `test/ayumi_web/live/support_plan_live_test.exs` - LiveView flow for recording a phase.
- Create: `lib/ayumi_web/live/dashboard_live/index.ex` - authenticated monitoring dashboard.
- Create: `test/ayumi_web/live/dashboard_live_test.exs` - dashboard auth, alert, sort, and empty-state tests.
- Modify: `lib/ayumi_web/router.ex` - replace public root route with authenticated dashboard route.
- Delete: `test/ayumi_web/controllers/page_controller_test.exs` - public Phoenix default home is no longer routed.
- Modify: `priv/gettext/default.pot` - generated msgids for new Japanese UI strings.

---

## Task 1: Add the PlanPhaseStage enum

**Files:**
- Modify: `test/ayumi/plans/enumerations_test.exs`
- Create: `lib/ayumi/plans/plan_phase_stage.ex`

- [ ] **Step 1: Write the failing enum tests**

In `test/ayumi/plans/enumerations_test.exs`, add `PlanPhaseStage` to the alias and append this describe block:

```elixir
alias Ayumi.Plans.{CertificateKind, Gender, PlanPhaseStage, SupportCategory}

describe "PlanPhaseStage" do
  test "all/0 lists stages in lifecycle order" do
    assert PlanPhaseStage.all() == [
             :assessment,
             :draft,
             :support_meeting,
             :consent,
             :in_progress,
             :monitoring,
             :review
           ]
  end

  test "label/1 maps values to Japanese" do
    assert PlanPhaseStage.label(:assessment) == "アセスメント"
    assert PlanPhaseStage.label(:draft) == "計画原案"
    assert PlanPhaseStage.label(:support_meeting) == "個別支援会議"
    assert PlanPhaseStage.label(:consent) == "説明・同意・交付"
    assert PlanPhaseStage.label(:in_progress) == "支援の実施"
    assert PlanPhaseStage.label(:monitoring) == "モニタリング"
    assert PlanPhaseStage.label(:review) == "見直し"
  end

  test "label/1 returns nil for unknown or nil" do
    assert PlanPhaseStage.label(nil) == nil
    assert PlanPhaseStage.label(:bogus) == nil
  end

  test "options/0 returns {label, value} pairs for selects" do
    assert {"アセスメント", :assessment} in PlanPhaseStage.options()
    assert length(PlanPhaseStage.options()) == 7
  end
end
```

- [ ] **Step 2: Run the enum test and verify it fails**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs
```

Expected: FAIL with `Ayumi.Plans.PlanPhaseStage` undefined.

- [ ] **Step 3: Implement the enum module**

Create `lib/ayumi/plans/plan_phase_stage.ex`:

```elixir
defmodule Ayumi.Plans.PlanPhaseStage do
  @moduledoc "Support-plan lifecycle stage enumeration. Labels live here, not in views."

  @labels [
    assessment: "アセスメント",
    draft: "計画原案",
    support_meeting: "個別支援会議",
    consent: "説明・同意・交付",
    in_progress: "支援の実施",
    monitoring: "モニタリング",
    review: "見直し"
  ]

  @doc "All values, in lifecycle display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

- [ ] **Step 4: Run the enum test and verify it passes**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ayumi/plans/plan_phase_stage.ex test/ayumi/plans/enumerations_test.exs
git commit -m "feat: add plan phase stage enum"
```

---

## Task 2: Add the PlanPhaseEvent table and schema

**Files:**
- Create: `priv/repo/migrations/20260618000000_create_plan_phase_events.exs`
- Create: `lib/ayumi/plans/plan_phase_event.ex`
- Create: `test/ayumi/plans/plan_phase_event_test.exs`
- Modify: `lib/ayumi/plans/support_plan.ex`

- [ ] **Step 1: Write the failing changeset tests**

Create `test/ayumi/plans/plan_phase_event_test.exs`:

```elixir
defmodule Ayumi.Plans.PlanPhaseEventTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.PlanPhaseEvent

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  test "requires support_plan_id, stage, recorded_by_id, and recorded_at" do
    changeset = PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{})

    refute changeset.valid?
    assert errors_on(changeset)[:support_plan_id]
    assert errors_on(changeset)[:stage]
    assert errors_on(changeset)[:recorded_by_id]
    assert errors_on(changeset)[:recorded_at]
  end

  test "rejects an unknown stage" do
    plan = support_plan_fixture()
    staff = staff_fixture()

    changeset =
      PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{
        support_plan_id: plan.id,
        stage: :bogus,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:02:03Z]
      })

    refute changeset.valid?
    assert errors_on(changeset)[:stage]
  end

  test "valid with a support plan, allowed stage, staff, recorded_at, and optional note" do
    plan = support_plan_fixture()
    staff = staff_fixture()

    changeset =
      PlanPhaseEvent.changeset(%PlanPhaseEvent{}, %{
        support_plan_id: plan.id,
        stage: :support_meeting,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:02:03Z],
        note: "会議で支援内容を確認した"
      })

    assert changeset.valid?
  end
end
```

- [ ] **Step 2: Run the focused schema test and verify it fails**

Run:

```bash
mix test test/ayumi/plans/plan_phase_event_test.exs
```

Expected: FAIL with `Ayumi.Plans.PlanPhaseEvent` undefined.

- [ ] **Step 3: Create the migration**

Create `priv/repo/migrations/20260618000000_create_plan_phase_events.exs`:

```elixir
defmodule Ayumi.Repo.Migrations.CreatePlanPhaseEvents do
  use Ecto.Migration

  def change do
    create table(:plan_phase_events) do
      add :support_plan_id, references(:support_plans, on_delete: :restrict), null: false
      add :stage, :string, null: false
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:plan_phase_events, [:support_plan_id])
    create index(:plan_phase_events, [:recorded_by_id])
    create index(:plan_phase_events, [:support_plan_id, :id])
  end
end
```

Why this shape:
- `plan_phase_events` is append-only, so it has `inserted_at` but no `updated_at` and no `lock_version`.
- `recorded_at` is supplied server-side by the LiveView flow and displayed as the staff-facing record time.
- `[:support_plan_id, :id]` supports history listing and latest-stage derivation in insertion order.

- [ ] **Step 4: Create the schema**

Create `lib/ayumi/plans/plan_phase_event.ex`:

```elixir
defmodule Ayumi.Plans.PlanPhaseEvent do
  @moduledoc "An append-only lifecycle stage event for a support plan."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.PlanPhaseStage

  @required [:support_plan_id, :stage, :recorded_by_id, :recorded_at]
  @optional [:note]

  schema "plan_phase_events" do
    field :stage, Ecto.Enum, values: PlanPhaseStage.all()
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :support_plan, Ayumi.Plans.SupportPlan
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(plan_phase_event, attrs) do
    plan_phase_event
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:stage, PlanPhaseStage.all())
    |> foreign_key_constraint(:support_plan_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
```

- [ ] **Step 5: Add the association to support plans**

In `lib/ayumi/plans/support_plan.ex`, add this association below `has_many :goals`:

```elixir
has_many :plan_phase_events, Ayumi.Plans.PlanPhaseEvent
```

- [ ] **Step 6: Migrate and run the focused schema test**

Run:

```bash
mix ecto.migrate
mix test test/ayumi/plans/plan_phase_event_test.exs
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ayumi/plans/support_plan.ex lib/ayumi/plans/plan_phase_event.ex priv/repo/migrations/20260618000000_create_plan_phase_events.exs test/ayumi/plans/plan_phase_event_test.exs
git commit -m "feat: add plan phase event schema"
```

---

## Task 3: Add Plans context functions and fixtures

**Files:**
- Modify: `lib/ayumi/plans.ex`
- Modify: `test/ayumi/plans_test.exs`
- Modify: `test/support/fixtures/plans_fixtures.ex`

- [ ] **Step 1: Write failing context tests for phase events**

In `test/ayumi/plans_test.exs`, add `PlanPhaseEvent` to the aliases:

```elixir
alias Ayumi.Plans.PlanPhaseEvent
```

Append this describe block before `describe "referential integrity"`:

```elixir
describe "plan phase events" do
  test "record_plan_phase_event/1 appends a phase event row" do
    plan = support_plan_fixture()
    staff = Ayumi.AccountsFixtures.staff_fixture()
    recorded_at = ~U[2026-06-18 01:02:03Z]

    assert {:ok, %PlanPhaseEvent{} = event} =
             Plans.record_plan_phase_event(%{
               support_plan_id: plan.id,
               stage: :support_meeting,
               note: "会議で支援内容を確認した",
               recorded_by_id: staff.id,
               recorded_at: recorded_at
             })

    assert event.support_plan_id == plan.id
    assert event.stage == :support_meeting
    assert event.note == "会議で支援内容を確認した"
    assert event.recorded_by_id == staff.id
    assert event.recorded_at == recorded_at
  end

  test "record_plan_phase_event/1 never updates previous phase rows" do
    plan = support_plan_fixture()
    staff = Ayumi.AccountsFixtures.staff_fixture()

    {:ok, first} =
      Plans.record_plan_phase_event(%{
        support_plan_id: plan.id,
        stage: :assessment,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:00:00Z]
      })

    {:ok, second} =
      Plans.record_plan_phase_event(%{
        support_plan_id: plan.id,
        stage: :draft,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 02:00:00Z]
      })

    history = Plans.list_plan_phase_events(plan)

    assert first.id != second.id
    assert Enum.map(history, & &1.id) == [first.id, second.id]
    assert Enum.map(history, & &1.stage) == [:assessment, :draft]
  end

  test "list_plan_phase_events/1 returns one plan's history in insertion order with staff preloaded" do
    plan = support_plan_fixture()
    staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "記録 職員"})

    {:ok, _} =
      Plans.record_plan_phase_event(%{
        support_plan_id: plan.id,
        stage: :assessment,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 01:00:00Z]
      })

    {:ok, _} =
      Plans.record_plan_phase_event(%{
        support_plan_id: plan.id,
        stage: :consent,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-18 02:00:00Z]
      })

    assert [:assessment, :consent] =
             Plans.list_plan_phase_events(plan) |> Enum.map(& &1.stage)

    assert [%{recorded_by: %{name: "記録 職員"}} | _] = Plans.list_plan_phase_events(plan)
  end

  test "current_plan_stage/1 returns nil for an empty history" do
    assert Plans.current_plan_stage([]) == nil
  end

  test "current_plan_stage/1 returns the latest inserted phase event" do
    older = %PlanPhaseEvent{id: 1, stage: :assessment}
    newer = %PlanPhaseEvent{id: 2, stage: :in_progress}

    assert Plans.current_plan_stage([newer, older]) == newer
  end
end
```

- [ ] **Step 2: Write failing context tests for monitoring deadlines**

Append this describe block after the phase-event describe block:

```elixir
describe "monitoring deadline alerts" do
  test "monitoring_deadline_status/3 classifies overdue, near, and ok" do
    today = ~D[2026-06-18]

    assert Plans.monitoring_deadline_status(~D[2026-06-17], today, 30) == :overdue
    assert Plans.monitoring_deadline_status(~D[2026-06-18], today, 30) == :near
    assert Plans.monitoring_deadline_status(~D[2026-07-18], today, 30) == :near
    assert Plans.monitoring_deadline_status(~D[2026-07-19], today, 30) == :ok
  end

  test "list_monitoring_deadline_alerts/3 ignores older plans for the same service user" do
    today = ~D[2026-06-18]
    staff = Ayumi.AccountsFixtures.staff_fixture()
    service_user = service_user_fixture(%{name: "期またぎ 太郎", name_kana: "きまたぎ たろう"})

    _old_overdue =
      support_plan_fixture(%{
        service_user_id: service_user.id,
        staff_id: staff.id,
        period_start: ~D[2025-04-01],
        period_end: ~D[2025-09-30],
        next_monitoring_date: ~D[2025-05-01]
      })

    current_ok =
      support_plan_fixture(%{
        service_user_id: service_user.id,
        staff_id: staff.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-09-30],
        next_monitoring_date: ~D[2026-08-01]
      })

    alerts = Plans.list_monitoring_deadline_alerts(Ayumi.Accounts.Scope.for_user(staff), today, 30)

    refute Enum.any?(alerts, &(&1.support_plan.id == current_ok.id))
    assert alerts == []
  end

  test "list_monitoring_deadline_alerts/3 includes all users and sorts current staff first, then urgent" do
    today = ~D[2026-06-18]
    current_staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "担当 職員"})
    other_staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "別 職員"})

    own_user = service_user_fixture(%{name: "自分 担当", name_kana: "じぶん たんとう"})
    other_overdue_user = service_user_fixture(%{name: "他 超過", name_kana: "た ちょうか"})
    other_near_user = service_user_fixture(%{name: "他 近接", name_kana: "た きんせつ"})

    own_near =
      support_plan_fixture(%{
        service_user_id: own_user.id,
        staff_id: current_staff.id,
        next_monitoring_date: ~D[2026-06-25]
      })

    other_overdue =
      support_plan_fixture(%{
        service_user_id: other_overdue_user.id,
        staff_id: other_staff.id,
        next_monitoring_date: ~D[2026-06-01]
      })

    other_near =
      support_plan_fixture(%{
        service_user_id: other_near_user.id,
        staff_id: other_staff.id,
        next_monitoring_date: ~D[2026-06-20]
      })

    alerts =
      current_staff
      |> Ayumi.Accounts.Scope.for_user()
      |> Plans.list_monitoring_deadline_alerts(today, 30)

    assert Enum.map(alerts, & &1.support_plan.id) == [
             own_near.id,
             other_overdue.id,
             other_near.id
           ]

    assert [%{status: :near, assigned_to_current_user?: true} | _] = alerts
    assert Enum.map(alerts, & &1.days_until) == [7, -17, 2]
  end
end
```

- [ ] **Step 3: Run the context tests and verify they fail**

Run:

```bash
mix test test/ayumi/plans_test.exs
```

Expected: FAIL because the `Plans` phase-event and monitoring functions do not exist yet.

- [ ] **Step 4: Add the fixture helper**

In `test/support/fixtures/plans_fixtures.ex`, add:

```elixir
def plan_phase_event_fixture(attrs \\ %{}) do
  support_plan_id = attrs[:support_plan_id] || support_plan_fixture().id
  recorded_by_id = attrs[:recorded_by_id] || user_fixture().id

  {:ok, plan_phase_event} =
    attrs
    |> Enum.into(%{
      support_plan_id: support_plan_id,
      stage: :assessment,
      note: "アセスメントを記録した",
      recorded_by_id: recorded_by_id,
      recorded_at: ~U[2026-06-18 01:02:03Z]
    })
    |> Plans.record_plan_phase_event()

  plan_phase_event
end
```

- [ ] **Step 5: Implement the context aliases**

In `lib/ayumi/plans.ex`, add `PlanPhaseEvent` and `Scope` to the aliases:

```elixir
alias Ayumi.Accounts.Scope
alias Ayumi.Plans.PlanPhaseEvent
```

- [ ] **Step 6: Implement the phase-event context API**

In `lib/ayumi/plans.ex`, add this section after the existing Goals section and before private helpers:

```elixir
## Plan phase events

@doc "Returns a changeset for a plan phase event row (forms)."
def change_plan_phase_event(%PlanPhaseEvent{} = event, attrs \\ %{}) do
  PlanPhaseEvent.changeset(event, attrs)
end

@doc "Appends a plan phase event row. Existing rows are never updated."
def record_plan_phase_event(attrs) do
  %PlanPhaseEvent{}
  |> PlanPhaseEvent.changeset(attrs)
  |> Repo.insert()
end

@doc "Lists one support plan's phase history in insertion order."
def list_plan_phase_events(%SupportPlan{id: id}), do: list_plan_phase_events(id)

def list_plan_phase_events(support_plan_id) when is_integer(support_plan_id) do
  PlanPhaseEvent
  |> where([e], e.support_plan_id == ^support_plan_id)
  |> order_by([e], asc: e.id)
  |> preload([:recorded_by])
  |> Repo.all()
end

@doc """
Returns the latest phase event from an enumerable history.

This is pure and DB-independent. Latest is defined by the greatest id, not by
`recorded_at`, because corrections and rapid inserts should be resolved by
append order.
"""
def current_plan_stage(events) do
  events
  |> Enum.reject(&is_nil(&1.id))
  |> Enum.max_by(& &1.id, fn -> nil end)
end
```

- [ ] **Step 7: Implement the monitoring-deadline context API**

In `lib/ayumi/plans.ex`, add this section after the phase-event context API:

```elixir
## Monitoring deadlines

@doc "Classifies a monitoring deadline relative to a date."
def monitoring_deadline_status(next_monitoring_date, today, near_days)
    when is_integer(near_days) and near_days >= 0 do
  days_until = Date.diff(next_monitoring_date, today)

  cond do
    days_until < 0 -> :overdue
    days_until <= near_days -> :near
    true -> :ok
  end
end

@doc """
Returns monitoring-deadline alerts for the current support plan of every service user.

All users are included. Alerts assigned to the current staff user sort first,
then rows sort by `days_until` ascending so the most urgent deadlines are easiest
to scan. Current plan means the newest `period_start`, with highest id breaking
ties.
"""
def list_monitoring_deadline_alerts(%Scope{user: user}, today \\ Date.utc_today(), near_days \\ 30) do
  current_staff_id = user.id

  current_support_plans()
  |> Enum.map(&monitoring_deadline_alert(&1, current_staff_id, today, near_days))
  |> Enum.reject(&(&1.status == :ok))
  |> Enum.sort_by(fn alert ->
    plan = alert.support_plan
    own_order = if alert.assigned_to_current_user?, do: 0, else: 1

    {
      own_order,
      alert.days_until,
      plan.service_user.name_kana || "",
      plan.service_user.name || "",
      plan.id
    }
  end)
end

defp current_support_plans do
  SupportPlan
  |> order_by([p], asc: p.service_user_id, desc: p.period_start, desc: p.id)
  |> preload([:service_user, :staff])
  |> Repo.all()
  |> Enum.uniq_by(& &1.service_user_id)
end

defp monitoring_deadline_alert(plan, current_staff_id, today, near_days) do
  days_until = Date.diff(plan.next_monitoring_date, today)

  %{
    support_plan: plan,
    status: monitoring_deadline_status(plan.next_monitoring_date, today, near_days),
    days_until: days_until,
    assigned_to_current_user?: plan.staff_id == current_staff_id
  }
end
```

- [ ] **Step 8: Run the focused context tests**

Run:

```bash
mix test test/ayumi/plans_test.exs test/ayumi/plans/plan_phase_event_test.exs
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans_test.exs test/support/fixtures/plans_fixtures.ex
git commit -m "feat: add phase event and deadline context"
```

---

## Task 4: Add phase recording to SupportPlanLive.Show

**Files:**
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex`
- Modify: `test/ayumi_web/live/support_plan_live_test.exs`
- Modify: `priv/gettext/default.pot`

- [ ] **Step 1: Write the failing LiveView flow test**

In `test/ayumi_web/live/support_plan_live_test.exs`, add this test:

```elixir
test "records a plan phase event and shows current phase and history", %{conn: conn, user: staff} do
  plan = support_plan_fixture()

  {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")

  assert has_element?(lv, "#plan-phase-form")
  assert html =~ "未記録"

  html =
    lv
    |> form("#plan-phase-form",
      plan_phase_event: %{stage: "support_meeting", note: "会議で支援内容を確認した"}
    )
    |> render_submit()

  assert html =~ "個別支援会議"
  assert html =~ "会議で支援内容を確認した"
  assert html =~ staff.email
end
```

- [ ] **Step 2: Run the LiveView test and verify it fails**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs
```

Expected: FAIL because `#plan-phase-form` does not exist.

- [ ] **Step 3: Add aliases and event handling**

In `lib/ayumi_web/live/support_plan_live/show.ex`, add:

```elixir
alias Ayumi.Plans.PlanPhaseEvent
alias Ayumi.Plans.PlanPhaseStage
```

Add this event handler below the existing `handle_event("add_goal", ...)` handler:

```elixir
@impl true
def handle_event("record_plan_phase_event", %{"plan_phase_event" => params}, socket) do
  plan = socket.assigns.support_plan
  now = DateTime.utc_now(:second)

  event_params =
    params
    |> Map.put("support_plan_id", plan.id)
    |> Map.put("recorded_by_id", socket.assigns.current_scope.user.id)
    |> Map.put("recorded_at", now)

  case Plans.record_plan_phase_event(event_params) do
    {:ok, _event} ->
      {:noreply,
       socket
       |> put_flash(:info, gettext("ステージを記録しました"))
       |> load(plan.id)}

    {:error, changeset} ->
      {:noreply, assign(socket, :plan_phase_form, to_form(changeset))}
  end
end
```

- [ ] **Step 4: Load phase assigns**

In `lib/ayumi_web/live/support_plan_live/show.ex`, update `load/2` so it assigns phase history, current phase, and a form:

```elixir
defp load(socket, id) do
  support_plan = Plans.get_support_plan!(id)
  phase_events = Plans.list_plan_phase_events(support_plan)

  socket
  |> assign(:page_title, gettext("支援計画"))
  |> assign(:support_plan, support_plan)
  |> assign(:goals, Plans.list_goals(support_plan))
  |> assign(:goal_form, to_form(Plans.change_goal(%Goal{})))
  |> assign(:plan_phase_events, phase_events)
  |> assign(:current_plan_phase, Plans.current_plan_stage(phase_events))
  |> assign(:plan_phase_form, to_form(Plans.change_plan_phase_event(%PlanPhaseEvent{})))
end
```

If Step 2 is already implemented, preserve its goal-progress assigns and add the four phase assigns to that existing `load/2` instead of replacing them.

- [ ] **Step 5: Add the phase panel to the template**

In `SupportPlanLive.Show.render/1`, insert this block after the `<.list>` that shows period, goal, and monitoring date, and before the short-term goals section:

```heex
<section id="plan-phase-panel" class="mt-8 rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
  <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
    <div>
      <h2 class="text-base font-semibold text-zinc-900">{gettext("計画ライフサイクル")}</h2>
      <p class="mt-1 text-sm text-zinc-600">
        {gettext("現在ステージ")}:
        <span class="font-medium text-zinc-900">{plan_phase_label(@current_plan_phase)}</span>
      </p>
    </div>

    <.form
      for={@plan_phase_form}
      id="plan-phase-form"
      phx-submit="record_plan_phase_event"
      class="grid gap-3 rounded-md bg-zinc-50 p-3 md:min-w-96"
    >
      <.input
        field={@plan_phase_form[:stage]}
        type="select"
        label={gettext("ステージ")}
        prompt={gettext("選択してください")}
        options={PlanPhaseStage.options()}
      />
      <.input field={@plan_phase_form[:note]} type="textarea" label={gettext("所見")} />
      <.button id="record-plan-phase" phx-disable-with={gettext("記録中...")}>
        {gettext("ステージを記録")}
      </.button>
    </.form>
  </div>

  <div class="mt-4">
    <h3 class="text-sm font-semibold text-zinc-800">{gettext("ステージ履歴")}</h3>
    <div id="plan-phase-history" class="mt-2 space-y-2">
      <div
        :if={@plan_phase_events == []}
        class="rounded-md border border-dashed border-zinc-300 px-3 py-2 text-sm text-zinc-500"
      >
        {gettext("まだステージ記録はありません")}
      </div>

      <div
        :for={event <- @plan_phase_events}
        id={"plan-phase-event-#{event.id}"}
        class="rounded-md border border-zinc-100 px-3 py-2 text-sm"
      >
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <span class="font-medium text-zinc-900">{PlanPhaseStage.label(event.stage)}</span>
          <span class="text-zinc-600">{User.display_name(event.recorded_by)}</span>
          <span class="text-zinc-500">{event.recorded_at}</span>
        </div>
        <p :if={event.note not in [nil, ""]} class="mt-1 whitespace-pre-line text-zinc-700">
          {event.note}
        </p>
      </div>
    </div>
  </div>
</section>
```

- [ ] **Step 6: Add a label helper**

Add this private helper near the bottom of `SupportPlanLive.Show`:

```elixir
defp plan_phase_label(nil), do: gettext("未記録")
defp plan_phase_label(event), do: PlanPhaseStage.label(event.stage)
```

- [ ] **Step 7: Run the LiveView test**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs
```

Expected: PASS.

- [ ] **Step 8: Extract gettext messages**

Run:

```bash
mix gettext.extract
mix gettext.extract --check-up-to-date
```

Expected: `priv/gettext/default.pot` is updated and the check exits 0.

- [ ] **Step 9: Commit**

```bash
git add lib/ayumi_web/live/support_plan_live/show.ex test/ayumi_web/live/support_plan_live_test.exs priv/gettext/default.pot
git commit -m "feat: record plan phase events"
```

---

## Task 5: Add the authenticated monitoring dashboard

**Files:**
- Create: `lib/ayumi_web/live/dashboard_live/index.ex`
- Create: `test/ayumi_web/live/dashboard_live_test.exs`
- Modify: `lib/ayumi_web/router.ex`
- Delete: `test/ayumi_web/controllers/page_controller_test.exs`
- Modify: `priv/gettext/default.pot`

- [ ] **Step 1: Write failing dashboard LiveView tests**

Create `test/ayumi_web/live/dashboard_live_test.exs`:

```elixir
defmodule AyumiWeb.DashboardLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "authenticated dashboard" do
    setup :register_and_log_in_user

    test "shows an empty state when there are no monitoring alerts", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#monitoring-alerts")
      assert has_element?(lv, "#monitoring-alerts-empty")
    end

    test "shows overdue and near monitoring deadlines", %{conn: conn, user: staff} do
      service_user = service_user_fixture(%{name: "山田 太郎", name_kana: "やまだ たろう"})

      overdue_plan =
        support_plan_fixture(%{
          service_user_id: service_user.id,
          staff_id: staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), -1)
        })

      {:ok, lv, html} = live(conn, ~p"/")

      assert has_element?(lv, "#monitoring-alert-#{overdue_plan.id}")
      assert html =~ "山田 太郎"
      assert html =~ "超過"
      assert html =~ ~p"/support_plans/#{overdue_plan.id}"
      assert html =~ ~p"/service_users/#{service_user.id}"
    end

    test "sorts current staff alerts first", %{conn: conn, user: current_staff} do
      other_staff = staff_fixture(%{name: "別 職員"})
      own_user = service_user_fixture(%{name: "自分 担当", name_kana: "じぶん たんとう"})
      other_user = service_user_fixture(%{name: "他 担当", name_kana: "た たんとう"})

      own_plan =
        support_plan_fixture(%{
          service_user_id: own_user.id,
          staff_id: current_staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), 7)
        })

      other_plan =
        support_plan_fixture(%{
          service_user_id: other_user.id,
          staff_id: other_staff.id,
          next_monitoring_date: Date.add(Date.utc_today(), -10)
        })

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "monitoring-alert-#{own_plan.id}"
      assert html =~ "monitoring-alert-#{other_plan.id}"
      assert html =~ "monitoring-alert-#{own_plan.id}"
      assert html =~ "monitoring-alert-#{other_plan.id}"
      assert :binary.match(html, "monitoring-alert-#{own_plan.id}") <
               :binary.match(html, "monitoring-alert-#{other_plan.id}")
    end
  end
end
```

- [ ] **Step 2: Run the dashboard tests and verify they fail**

Run:

```bash
mix test test/ayumi_web/live/dashboard_live_test.exs
```

Expected: FAIL because `AyumiWeb.DashboardLive.Index` and the authenticated root route do not exist.

- [ ] **Step 3: Create the dashboard LiveView**

Create `lib/ayumi_web/live/dashboard_live/index.ex`:

```elixir
defmodule AyumiWeb.DashboardLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans

  @near_days 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("ダッシュボード"))
     |> assign(:near_days, @near_days)
     |> assign(:monitoring_alerts, Plans.list_monitoring_deadline_alerts(socket.assigns.current_scope, Date.utc_today(), @near_days))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("ダッシュボード")}
        <:subtitle>{gettext("モニタリング期限と担当状況を確認します")}</:subtitle>
      </.header>

      <section id="monitoring-alerts" class="space-y-3">
        <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 class="text-base font-semibold text-zinc-900">{gettext("モニタリング期限")}</h2>
            <p class="text-sm text-zinc-600">
              {gettext("超過と%{days}日以内の予定を表示しています", days: @near_days)}
            </p>
          </div>
          <.link navigate={~p"/service_users"} class="text-sm font-semibold text-zinc-700 hover:text-zinc-950">
            {gettext("利用者一覧へ")}
          </.link>
        </div>

        <div
          :if={@monitoring_alerts == []}
          id="monitoring-alerts-empty"
          class="rounded-lg border border-dashed border-zinc-300 bg-white px-4 py-5 text-sm text-zinc-600"
        >
          {gettext("期限が近いモニタリング予定はありません")}
        </div>

        <div
          :for={alert <- @monitoring_alerts}
          id={"monitoring-alert-#{alert.support_plan.id}"}
          class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <div class="flex flex-wrap items-center gap-2">
                <span class={[
                  "rounded-full px-2 py-1 text-xs font-semibold",
                  alert.status == :overdue && "bg-red-100 text-red-800",
                  alert.status == :near && "bg-amber-100 text-amber-800"
                ]}>
                  {deadline_status_label(alert.status)}
                </span>
                <span :if={alert.assigned_to_current_user?} class="rounded-full bg-zinc-100 px-2 py-1 text-xs font-semibold text-zinc-700">
                  {gettext("自分の担当")}
                </span>
              </div>

              <h3 class="mt-2 text-base font-semibold text-zinc-900">
                <.link navigate={~p"/service_users/#{alert.support_plan.service_user.id}"}>
                  {alert.support_plan.service_user.name}
                </.link>
              </h3>

              <p class="mt-1 text-sm text-zinc-600">
                {gettext("担当")}: {User.display_name(alert.support_plan.staff)}
              </p>
            </div>

            <div class="text-left sm:text-right">
              <p class="text-sm text-zinc-600">{gettext("次回モニタリング予定日")}</p>
              <p class="text-lg font-semibold text-zinc-900">{alert.support_plan.next_monitoring_date}</p>
              <p class="text-sm text-zinc-600">{days_until_label(alert.days_until)}</p>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap gap-3 text-sm font-semibold">
            <.link navigate={~p"/support_plans/#{alert.support_plan.id}"} class="text-zinc-800 hover:text-zinc-950">
              {gettext("計画を開く")}
            </.link>
            <.link navigate={~p"/service_users/#{alert.support_plan.service_user.id}"} class="text-zinc-600 hover:text-zinc-950">
              {gettext("利用者詳細")}
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp deadline_status_label(:overdue), do: gettext("超過")
  defp deadline_status_label(:near), do: gettext("近接")

  defp days_until_label(days) when days < 0 do
    gettext("%{days}日超過", days: abs(days))
  end

  defp days_until_label(0), do: gettext("本日期限")
  defp days_until_label(days), do: gettext("あと%{days}日", days: days)
end
```

After formatting, split the long `assign(:monitoring_alerts, ...)` line if `mix format` rewrites it. Keep the code behavior identical.

- [ ] **Step 4: Replace the public root route with the authenticated dashboard route**

In `lib/ayumi_web/router.ex`, remove this public root scope:

```elixir
scope "/", AyumiWeb do
  pipe_through :browser

  get "/", PageController, :home
end
```

Inside the existing authenticated `live_session :require_authenticated_user` block, add `live "/", DashboardLive.Index, :index` before the settings routes:

```elixir
scope "/", AyumiWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [AyumiWeb.LanOnly, {AyumiWeb.UserAuth, :require_authenticated}] do
    live "/", DashboardLive.Index, :index
    live "/users/settings", UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

    live "/service_users", ServiceUserLive.Index, :index
    live "/service_users/new", ServiceUserLive.Form, :new
    live "/service_users/:id/edit", ServiceUserLive.Form, :edit
    live "/service_users/:id", ServiceUserLive.Show, :show
    live "/service_users/:service_user_id/support_plans/new", SupportPlanLive.Form, :new
    live "/support_plans/:id", SupportPlanLive.Show, :show
  end

  post "/users/update-password", UserSessionController, :update_password
end
```

Reason: `/` now renders operational data and must run behind `:require_authenticated_user`. It uses the existing live session rather than a duplicate live-session name, preserving the phx.gen.auth route structure.

- [ ] **Step 5: Remove the obsolete public-home controller test**

Delete `test/ayumi_web/controllers/page_controller_test.exs`. The default Phoenix home page is no longer a routed behavior; guest root access is now covered by `test/ayumi_web/live/dashboard_live_test.exs`.

- [ ] **Step 6: Run dashboard tests**

Run:

```bash
mix test test/ayumi_web/live/dashboard_live_test.exs
```

Expected: PASS.

- [ ] **Step 7: Run auth/session tests touched by the root route**

Run:

```bash
mix test test/ayumi_web/controllers/user_session_controller_test.exs test/ayumi_web/user_auth_test.exs
```

Expected: PASS. If a test still asserts Phoenix default home text, replace that assertion with dashboard structure such as `#monitoring-alerts`; do not reintroduce a public root page.

- [ ] **Step 8: Extract gettext messages**

Run:

```bash
mix gettext.extract
mix gettext.extract --check-up-to-date
```

Expected: `priv/gettext/default.pot` is updated and the check exits 0.

- [ ] **Step 9: Commit**

```bash
git add lib/ayumi_web/live/dashboard_live/index.ex lib/ayumi_web/router.ex test/ayumi_web/live/dashboard_live_test.exs priv/gettext/default.pot
git rm test/ayumi_web/controllers/page_controller_test.exs
git commit -m "feat: add monitoring deadline dashboard"
```

---

## Task 6: Final integration and quality gate

**Files:**
- All files changed in Tasks 1-5.

- [ ] **Step 1: Run focused domain tests**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs test/ayumi/plans/plan_phase_event_test.exs test/ayumi/plans_test.exs
```

Expected: PASS.

- [ ] **Step 2: Run focused LiveView tests**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs test/ayumi_web/live/dashboard_live_test.exs
```

Expected: PASS.

- [ ] **Step 3: Run auth tests affected by `/`**

Run:

```bash
mix test test/ayumi_web/controllers/user_session_controller_test.exs test/ayumi_web/user_auth_test.exs
```

Expected: PASS.

- [ ] **Step 4: Run the full review gate**

Run:

```bash
mix review
```

Expected: `format --check-formatted`, `compile --warnings-as-errors --force`, `credo`, and `test` all pass.

- [ ] **Step 5: Run the project precommit alias**

Run:

```bash
mix precommit
```

Expected: compile, unused-dependency check, format, and tests pass. If `mix precommit` formats files, continue to the next step and re-run `mix review`.

- [ ] **Step 6: If formatting changes are reported**

Run:

```bash
mix format
mix review
mix precommit
```

Expected: PASS after formatting. Include formatting changes only when they touch files from this plan.

- [ ] **Step 7: Final commit if earlier commits were skipped**

If the implementation was not committed task-by-task, make one final commit:

```bash
git add lib/ayumi/plans.ex lib/ayumi/plans/support_plan.ex lib/ayumi/plans/plan_phase_event.ex lib/ayumi/plans/plan_phase_stage.ex lib/ayumi_web/live/support_plan_live/show.ex lib/ayumi_web/live/dashboard_live/index.ex lib/ayumi_web/router.ex test/ayumi/plans/enumerations_test.exs test/ayumi/plans/plan_phase_event_test.exs test/ayumi/plans_test.exs test/ayumi_web/live/support_plan_live_test.exs test/ayumi_web/live/dashboard_live_test.exs test/support/fixtures/plans_fixtures.ex priv/repo/migrations/20260618000000_create_plan_phase_events.exs priv/gettext/default.pot
git rm test/ayumi_web/controllers/page_controller_test.exs
git commit -m "feat: add plan phase tracking and dashboard"
```

---

## Self-Review Checklist

- [ ] Step 3 lifecycle order is exactly `assessment -> draft -> support_meeting -> consent -> in_progress -> monitoring -> review`.
- [ ] `plan_phase_events` has `inserted_at` and no `updated_at`, `lock_version`, edit UI, delete UI, or mutable current-stage column.
- [ ] `recorded_by_id` is supplied from `@current_scope.user.id` in the authenticated LiveView flow.
- [ ] `recorded_at` is assigned server-side with `DateTime.utc_now(:second)`.
- [ ] Current phase is derived by `Plans.current_plan_stage/1` using latest inserted id.
- [ ] Phase history preloads `:recorded_by` before rendering staff names.
- [ ] Dashboard uses all service users' current plans, where current means newest `period_start` and highest id as tie-breaker.
- [ ] Dashboard classification uses `days_until < 0` as `:overdue`, `0 <= days_until <= 30` as `:near`, and everything else as `:ok`.
- [ ] Dashboard sorts current staff's assigned plans first, then `days_until` ascending.
- [ ] `/` is in `pipe_through [:browser, :require_authenticated_user]` and the existing `live_session :require_authenticated_user`; there is no duplicate live-session name.
- [ ] All new templates begin with `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- [ ] Templates use `@current_scope.user` or context-provided structs, never `@current_user`.
- [ ] New Japanese UI strings are wrapped in `gettext(...)` and `priv/gettext/default.pot` is updated.
- [ ] `mix review` and `mix precommit` pass before the implementation is considered complete.
