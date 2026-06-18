# Goal Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add append-only `goal_progresses` records so staff can record each short-term goal's progress from the support-plan detail screen and see both the current progress and history.

**Status:** Implemented on `main` as of 2026-06-18. This file is retained as the historical Step 2 implementation plan.

**Architecture:** Keep all domain behavior in `Ayumi.Plans`: enum labels, schema validation, append-only insert, history listing, and current-progress derivation. `SupportPlanLive.Show` remains the single authenticated UI surface for this step; it delegates validation and persistence to the context and uses `@current_scope.user` as `recorded_by`. Current state is derived from the latest progress row, never stored on `goals`.

**Tech Stack:** Elixir, Phoenix 1.8, Phoenix LiveView, Ecto + `ecto_sqlite3`, SQLite, Gettext, ExUnit, Phoenix.LiveViewTest/LazyHTML. Verification uses the existing `mix review` and `mix precommit` aliases.

**Scope note:** This plan follows `TODO.md` Step 2 as the current source of truth. It intentionally does not add `plan_phase_event`, monitoring dashboard behavior, a mutable `current_stage` column, edit/delete UI for progress rows, or a `correction_of_id` column; corrections are represented by appending another progress row.

**Implemented progress stages:** `not_started / working / partially_met / mostly_met / met` (`未着手 / 取組中 / 一部達成 / 概ね達成 / 達成`). If the facility changes the vocabulary later, update `Ayumi.Plans.GoalProgressStage`, tests, and UI together.

**Router/auth placement:** No new route is needed. The existing `live "/support_plans/:id", SupportPlanLive.Show, :show` route stays inside `scope "/", AyumiWeb`, `pipe_through [:browser, :require_authenticated_user]`, and `live_session :require_authenticated_user` because recording progress requires a logged-in staff member and uses `@current_scope.user.id` for `recorded_by_id`.

---

## File Structure

- Modify: `test/ayumi/plans/enumerations_test.exs` — add tests for `GoalProgressStage`.
- Create: `lib/ayumi/plans/goal_progress_stage.ex` — centralized enum values and Japanese labels.
- Create: `priv/repo/migrations/20260617000000_create_goal_progresses.exs` — append-only progress table; no `lock_version`.
- Create: `lib/ayumi/plans/goal_progress.ex` — schema and changeset for progress rows.
- Create: `test/ayumi/plans/goal_progress_test.exs` — schema/changeset tests.
- Modify: `lib/ayumi/plans/goal.ex` — add `has_many :goal_progresses`.
- Modify: `lib/ayumi/plans.ex` — context API: `change_goal_progress/2`, `record_goal_progress/1`, `record_goal_progress_for_plan/2`, `list_goal_progress/1`, `list_goal_progress_for_goals/1`, `current_goal_progress/1`, `latest_goal_progress_by_goal/1`.
- Modify: `test/ayumi/plans_test.exs` — context tests for append-only insert, ordering, pure derivation, and grouped latest progress.
- Modify: `test/support/fixtures/plans_fixtures.ex` — add `goal_progress_fixture/1`.
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex` — show current progress, add per-goal progress forms, and render history.
- Modify: `test/ayumi_web/live/support_plan_live_test.exs` — LiveView flow: record progress, current display updates, history appears.
- Modify: `priv/gettext/default.pot` — generated msgids for new Japanese UI strings after `mix gettext.extract`.

---

## Task 1: Add the GoalProgressStage enum

**Files:**
- Modify: `test/ayumi/plans/enumerations_test.exs`
- Create: `lib/ayumi/plans/goal_progress_stage.ex`

- [x] **Step 1: Write the failing enum tests**

In `test/ayumi/plans/enumerations_test.exs`, add `GoalProgressStage` to the alias and append this describe block:

```elixir
alias Ayumi.Plans.{CertificateKind, Gender, GoalProgressStage, SupportCategory}

describe "GoalProgressStage" do
  test "all/0 lists stages in display order" do
    assert GoalProgressStage.all() == [
             :not_started,
             :working,
             :partially_met,
             :mostly_met,
             :met
           ]
  end

  test "label/1 maps values to Japanese" do
    assert GoalProgressStage.label(:not_started) == "未着手"
    assert GoalProgressStage.label(:working) == "取組中"
    assert GoalProgressStage.label(:partially_met) == "一部達成"
    assert GoalProgressStage.label(:mostly_met) == "概ね達成"
    assert GoalProgressStage.label(:met) == "達成"
  end

  test "label/1 returns nil for unknown or nil" do
    assert GoalProgressStage.label(nil) == nil
    assert GoalProgressStage.label(:bogus) == nil
  end

  test "options/0 returns {label, value} pairs for selects" do
    assert {"未着手", :not_started} in GoalProgressStage.options()
    assert length(GoalProgressStage.options()) == 5
  end
end
```

- [x] **Step 2: Run the enum test and verify it fails**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs
```

Expected: FAIL with `Ayumi.Plans.GoalProgressStage` undefined.

- [x] **Step 3: Implement the enum module**

Create `lib/ayumi/plans/goal_progress_stage.ex`:

```elixir
defmodule Ayumi.Plans.GoalProgressStage do
  @moduledoc "Goal progress stage enumeration. Labels live here, not in views."

  @labels [
    not_started: "未着手",
    working: "取組中",
    partially_met: "一部達成",
    mostly_met: "概ね達成",
    met: "達成"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

- [x] **Step 4: Run the enum test and verify it passes**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/ayumi/plans/goal_progress_stage.ex test/ayumi/plans/enumerations_test.exs
git commit -m "feat: add goal progress stage enum"
```

---

## Task 2: Add the GoalProgress table and schema

**Files:**
- Create: `priv/repo/migrations/20260617000000_create_goal_progresses.exs`
- Create: `lib/ayumi/plans/goal_progress.ex`
- Create: `test/ayumi/plans/goal_progress_test.exs`
- Modify: `lib/ayumi/plans/goal.ex`

- [x] **Step 1: Write the failing changeset tests**

Create `test/ayumi/plans/goal_progress_test.exs`:

```elixir
defmodule Ayumi.Plans.GoalProgressTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.GoalProgress

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  test "requires goal_id, stage, recorded_by_id, and recorded_at" do
    changeset = GoalProgress.changeset(%GoalProgress{}, %{})

    refute changeset.valid?
    assert errors_on(changeset)[:goal_id]
    assert errors_on(changeset)[:stage]
    assert errors_on(changeset)[:recorded_by_id]
    assert errors_on(changeset)[:recorded_at]
  end

  test "rejects an unknown stage" do
    goal = goal_fixture()
    staff = user_fixture()

    changeset =
      GoalProgress.changeset(%GoalProgress{}, %{
        goal_id: goal.id,
        stage: :bogus,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:02:03Z]
      })

    refute changeset.valid?
    assert errors_on(changeset)[:stage]
  end

  test "valid with a goal, allowed stage, staff, recorded_at, and optional note" do
    goal = goal_fixture()
    staff = user_fixture()

    changeset =
      GoalProgress.changeset(%GoalProgress{}, %{
        goal_id: goal.id,
        stage: :working,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:02:03Z],
        note: "午前の作業に参加できた"
      })

    assert changeset.valid?
  end
end
```

- [x] **Step 2: Run the focused schema test and verify it fails**

Run:

```bash
mix test test/ayumi/plans/goal_progress_test.exs
```

Expected: FAIL with `Ayumi.Plans.GoalProgress` undefined.

- [x] **Step 3: Create the migration**

Create `priv/repo/migrations/20260617000000_create_goal_progresses.exs`:

```elixir
defmodule Ayumi.Repo.Migrations.CreateGoalProgresses do
  use Ecto.Migration

  def change do
    create table(:goal_progresses) do
      add :goal_id, references(:goals, on_delete: :restrict), null: false
      add :stage, :string, null: false
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:goal_progresses, [:goal_id])
    create index(:goal_progresses, [:recorded_by_id])
    create index(:goal_progresses, [:goal_id, :id])
  end
end
```

Why this shape:
- `goal_progresses` is append-only, so it has `inserted_at` but no `updated_at` and no `lock_version`.
- `recorded_at` is server supplied by the context/UI flow and shown as the staff-facing record time.
- `[:goal_id, :id]` supports fetching histories and latest progress per goal in insertion order.

- [x] **Step 4: Create the schema**

Create `lib/ayumi/plans/goal_progress.ex`:

```elixir
defmodule Ayumi.Plans.GoalProgress do
  @moduledoc "An append-only progress update for a short-term goal."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.GoalProgressStage

  @required [:goal_id, :stage, :recorded_by_id, :recorded_at]
  @optional [:note]

  schema "goal_progresses" do
    field :stage, Ecto.Enum, values: GoalProgressStage.all()
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :goal, Ayumi.Plans.Goal
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(goal_progress, attrs) do
    goal_progress
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:stage, GoalProgressStage.all())
    |> foreign_key_constraint(:goal_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
```

- [x] **Step 5: Add the association to goals**

In `lib/ayumi/plans/goal.ex`, add this association below `belongs_to :support_plan`:

```elixir
has_many :goal_progresses, Ayumi.Plans.GoalProgress
```

- [x] **Step 6: Migrate and run the focused schema test**

Run:

```bash
mix ecto.migrate
mix test test/ayumi/plans/goal_progress_test.exs
```

Expected: PASS.

- [x] **Step 7: Commit**

```bash
git add lib/ayumi/plans/goal.ex lib/ayumi/plans/goal_progress.ex priv/repo/migrations/20260617000000_create_goal_progresses.exs test/ayumi/plans/goal_progress_test.exs
git commit -m "feat: add goal progress schema"
```

---

## Task 3: Add Plans context functions and fixtures

**Files:**
- Modify: `lib/ayumi/plans.ex`
- Modify: `test/ayumi/plans_test.exs`
- Modify: `test/support/fixtures/plans_fixtures.ex`

- [x] **Step 1: Write failing context tests**

In `test/ayumi/plans_test.exs`, add `GoalProgress` to the aliases:

```elixir
alias Ayumi.Plans.GoalProgress
```

Append this describe block before `describe "referential integrity"`:

```elixir
describe "goal progress" do
  test "record_goal_progress/1 appends a progress row" do
    goal = goal_fixture()
    staff = Ayumi.AccountsFixtures.user_fixture()
    recorded_at = ~U[2026-06-17 01:02:03Z]

    assert {:ok, %GoalProgress{} = progress} =
             Plans.record_goal_progress(%{
               goal_id: goal.id,
               stage: :working,
               note: "午前の作業に参加できた",
               recorded_by_id: staff.id,
               recorded_at: recorded_at
             })

    assert progress.goal_id == goal.id
    assert progress.stage == :working
    assert progress.note == "午前の作業に参加できた"
    assert progress.recorded_by_id == staff.id
    assert progress.recorded_at == recorded_at
  end

  test "record_goal_progress/1 never updates previous progress rows" do
    goal = goal_fixture()
    staff = Ayumi.AccountsFixtures.user_fixture()

    {:ok, first} =
      Plans.record_goal_progress(%{
        goal_id: goal.id,
        stage: :working,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:00:00Z]
      })

    {:ok, second} =
      Plans.record_goal_progress(%{
        goal_id: goal.id,
        stage: :met,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 02:00:00Z]
      })

    history = Plans.list_goal_progress(goal)

    assert first.id != second.id
    assert Enum.map(history, & &1.id) == [first.id, second.id]
    assert Enum.map(history, & &1.stage) == [:working, :met]
  end

  test "list_goal_progress/1 returns one goal's history in insertion order with staff preloaded" do
    goal = goal_fixture()
    staff = Ayumi.AccountsFixtures.staff_fixture(%{name: "記録 職員"})

    {:ok, _} =
      Plans.record_goal_progress(%{
        goal_id: goal.id,
        stage: :working,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:00:00Z]
      })

    {:ok, _} =
      Plans.record_goal_progress(%{
        goal_id: goal.id,
        stage: :mostly_met,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 02:00:00Z]
      })

    assert [:working, :mostly_met] = Plans.list_goal_progress(goal) |> Enum.map(& &1.stage)
    assert [%{recorded_by: %{name: "記録 職員"}} | _] = Plans.list_goal_progress(goal)
  end

  test "current_goal_progress/1 returns nil for an empty history" do
    assert Plans.current_goal_progress([]) == nil
  end

  test "current_goal_progress/1 returns the latest inserted progress row" do
    older = %GoalProgress{id: 1, stage: :working}
    newer = %GoalProgress{id: 2, stage: :met}

    assert Plans.current_goal_progress([newer, older]) == newer
  end

  test "latest_goal_progress_by_goal/1 returns latest progress for multiple goals without losing empty goals" do
    plan = support_plan_fixture()
    first_goal = goal_fixture(%{support_plan_id: plan.id, description: "1番目"})
    second_goal = goal_fixture(%{support_plan_id: plan.id, description: "2番目"})
    empty_goal = goal_fixture(%{support_plan_id: plan.id, description: "未記録"})
    staff = Ayumi.AccountsFixtures.user_fixture()

    {:ok, _} =
      Plans.record_goal_progress(%{
        goal_id: first_goal.id,
        stage: :working,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 01:00:00Z]
      })

    {:ok, latest_first} =
      Plans.record_goal_progress(%{
        goal_id: first_goal.id,
        stage: :met,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 02:00:00Z]
      })

    {:ok, latest_second} =
      Plans.record_goal_progress(%{
        goal_id: second_goal.id,
        stage: :partially_met,
        recorded_by_id: staff.id,
        recorded_at: ~U[2026-06-17 03:00:00Z]
      })

    latest_by_goal = Plans.latest_goal_progress_by_goal([first_goal, second_goal, empty_goal])

    assert latest_by_goal[first_goal.id].id == latest_first.id
    assert latest_by_goal[second_goal.id].id == latest_second.id
    assert latest_by_goal[empty_goal.id] == nil
  end
end
```

- [x] **Step 2: Run the context tests and verify they fail**

Run:

```bash
mix test test/ayumi/plans_test.exs
```

Expected: FAIL because the `Plans` goal-progress functions do not exist yet.

- [x] **Step 3: Add the fixture helper**

In `test/support/fixtures/plans_fixtures.ex`, add:

```elixir
def goal_progress_fixture(attrs \\ %{}) do
  goal_id = attrs[:goal_id] || goal_fixture().id
  recorded_by_id = attrs[:recorded_by_id] || user_fixture().id

  {:ok, goal_progress} =
    attrs
    |> Enum.into(%{
      goal_id: goal_id,
      stage: :working,
      note: "午前の作業に参加できた",
      recorded_by_id: recorded_by_id,
      recorded_at: ~U[2026-06-17 01:02:03Z]
    })
    |> Plans.record_goal_progress()

  goal_progress
end
```

- [x] **Step 4: Implement the context API**

In `lib/ayumi/plans.ex`, add `GoalProgress` to the aliases:

```elixir
alias Ayumi.Plans.GoalProgress
```

Add this section after the existing Goals section and before `insert_goal/1` private helpers:

```elixir
## Goal progress

@doc "Returns a changeset for a goal progress row (forms)."
def change_goal_progress(%GoalProgress{} = goal_progress, attrs \\ %{}) do
  GoalProgress.changeset(goal_progress, attrs)
end

@doc "Appends a goal progress row. Existing rows are never updated."
def record_goal_progress(attrs) do
  %GoalProgress{}
  |> GoalProgress.changeset(attrs)
  |> Repo.insert()
end

@doc "Lists one goal's progress history in insertion order."
def list_goal_progress(%Goal{id: id}), do: list_goal_progress(id)

def list_goal_progress(goal_id) when is_integer(goal_id) do
  GoalProgress
  |> where([p], p.goal_id == ^goal_id)
  |> order_by([p], asc: p.id)
  |> preload([:recorded_by])
  |> Repo.all()
end

@doc """
Returns the latest progress row from an enumerable history.

This is pure and DB-independent. Latest is defined by the greatest id, not by
`recorded_at`, because corrections and rapid inserts should be resolved by
append order.
"""
def current_goal_progress(progress_events) do
  progress_events
  |> Enum.reject(&is_nil(&1.id))
  |> Enum.max_by(& &1.id, fn -> nil end)
end

@doc "Returns `%{goal_id => latest_progress_or_nil}` for a list of goals."
def latest_goal_progress_by_goal(goals) when is_list(goals) do
  goal_ids = Enum.map(goals, & &1.id)
  empty_map = Map.new(goal_ids, &{&1, nil})

  latest =
    GoalProgress
    |> where([p], p.goal_id in ^goal_ids)
    |> order_by([p], asc: p.goal_id, asc: p.id)
    |> preload([:recorded_by])
    |> Repo.all()
    |> Enum.group_by(& &1.goal_id)
    |> Map.new(fn {goal_id, progress_events} ->
      {goal_id, current_goal_progress(progress_events)}
    end)

  Map.merge(empty_map, latest)
end
```

- [x] **Step 5: Run the context tests**

Run:

```bash
mix test test/ayumi/plans_test.exs test/ayumi/plans/goal_progress_test.exs
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans_test.exs test/support/fixtures/plans_fixtures.ex
git commit -m "feat: add goal progress context functions"
```

---

## Task 4: Add progress recording to SupportPlanLive.Show

**Files:**
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex`
- Modify: `test/ayumi_web/live/support_plan_live_test.exs`
- Modify: `priv/gettext/default.pot`

- [x] **Step 1: Write the failing LiveView flow test**

In `test/ayumi_web/live/support_plan_live_test.exs`, add this test:

```elixir
test "records goal progress and shows current progress and history", %{conn: conn, user: staff} do
  plan = support_plan_fixture()
  goal = goal_fixture(%{support_plan_id: plan.id, description: "毎日昼食を完食する"})

  {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")

  assert has_element?(lv, "#goal-progress-form-#{goal.id}")
  assert html =~ "未記録"

  html =
    lv
    |> form("#goal-progress-form-#{goal.id}",
      goal_progress: %{stage: "working", note: "午前の作業に参加できた"}
    )
    |> render_submit()

  assert html =~ "取組中"
  assert html =~ "午前の作業に参加できた"
  assert html =~ staff.email
end
```

- [x] **Step 2: Run the LiveView test and verify it fails**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs
```

Expected: FAIL because `#goal-progress-form-<id>` does not exist.

- [x] **Step 3: Add aliases and event handling**

In `lib/ayumi_web/live/support_plan_live/show.ex`, add:

```elixir
alias Ayumi.Plans.GoalProgress
alias Ayumi.Plans.GoalProgressStage
```

Add this event handler below `handle_event("add_goal", ...)`:

```elixir
@impl true
def handle_event("record_goal_progress", %{"goal_id" => goal_id, "goal_progress" => params}, socket) do
  plan = socket.assigns.support_plan
  now = DateTime.utc_now(:second)

  progress_params =
    params
    |> Map.put("goal_id", goal_id)
    |> Map.put("recorded_by_id", socket.assigns.current_scope.user.id)
    |> Map.put("recorded_at", now)

  case Plans.record_goal_progress(progress_params) do
    {:ok, _progress} ->
      {:noreply,
       socket
       |> put_flash(:info, gettext("進捗を記録しました"))
       |> load(plan.id)}

    {:error, changeset} ->
      goal_progress_forms =
        Map.put(socket.assigns.goal_progress_forms, String.to_integer(goal_id), to_form(changeset))

      {:noreply, assign(socket, :goal_progress_forms, goal_progress_forms)}
  end
end
```

If `String.to_integer/1` raises in tests for non-integer `goal_id`, keep the crash: the event is emitted only by server-rendered forms for known integer goals. Do not add ad-hoc validation in LiveView.

- [x] **Step 4: Load progress assigns**

Replace the `load/2` body with this structure:

```elixir
defp load(socket, id) do
  support_plan = Plans.get_support_plan!(id)
  goals = Plans.list_goals(support_plan)

  socket
  |> assign(:page_title, gettext("支援計画"))
  |> assign(:support_plan, support_plan)
  |> assign(:goals, goals)
  |> assign(:goal_form, to_form(Plans.change_goal(%Goal{})))
  |> assign(:goal_progress_forms, goal_progress_forms(goals))
  |> assign(:latest_goal_progress_by_goal, Plans.latest_goal_progress_by_goal(goals))
  |> assign(:goal_progress_history_by_goal, goal_progress_history_by_goal(goals))
end
```

Add these private helpers:

```elixir
defp goal_progress_forms(goals) do
  Map.new(goals, fn goal ->
    {goal.id, to_form(Plans.change_goal_progress(%GoalProgress{}))}
  end)
end

defp goal_progress_history_by_goal(goals) do
  Map.new(goals, fn goal -> {goal.id, Plans.list_goal_progress(goal)} end)
end
```

- [x] **Step 5: Replace the simple goals table with per-goal sections**

Replace the existing goals table block:

```heex
<.table id="goals" rows={@goals}>
  <:col :let={goal} label={gettext("内容")}>{goal.description}</:col>
</.table>
```

with:

```heex
<div id="goals" class="mt-4 space-y-5">
  <div
    :for={goal <- @goals}
    id={"goal-#{goal.id}"}
    class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
  >
    <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
      <div>
        <h3 class="text-base font-semibold text-zinc-900">{goal.description}</h3>
        <p class="mt-1 text-sm text-zinc-600">
          {gettext("現在の進捗")}:
          <span class="font-medium text-zinc-900">
            {goal_progress_label(@latest_goal_progress_by_goal[goal.id])}
          </span>
        </p>
      </div>

      <.form
        for={@goal_progress_forms[goal.id]}
        id={"goal-progress-form-#{goal.id}"}
        phx-submit="record_goal_progress"
        class="grid gap-3 rounded-md bg-zinc-50 p-3 md:min-w-96"
      >
        <input type="hidden" name="goal_id" value={goal.id} />
        <.input
          field={@goal_progress_forms[goal.id][:stage]}
          type="select"
          label={gettext("進捗ステージ")}
          prompt={gettext("選択してください")}
          options={GoalProgressStage.options()}
        />
        <.input field={@goal_progress_forms[goal.id][:note]} type="textarea" label={gettext("所見")} />
        <.button id={"record-goal-progress-#{goal.id}"} phx-disable-with={gettext("記録中...")}>
          {gettext("進捗を記録")}
        </.button>
      </.form>
    </div>

    <div class="mt-4">
      <h4 class="text-sm font-semibold text-zinc-800">{gettext("進捗履歴")}</h4>
      <div id={"goal-progress-history-#{goal.id}"} class="mt-2 space-y-2">
        <div
          :if={@goal_progress_history_by_goal[goal.id] == []}
          class="rounded-md border border-dashed border-zinc-300 px-3 py-2 text-sm text-zinc-500"
        >
          {gettext("まだ進捗記録はありません")}
        </div>

        <div
          :for={progress <- @goal_progress_history_by_goal[goal.id]}
          id={"goal-progress-#{progress.id}"}
          class="rounded-md border border-zinc-100 px-3 py-2 text-sm"
        >
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
            <span class="font-medium text-zinc-900">{GoalProgressStage.label(progress.stage)}</span>
            <span class="text-zinc-600">{User.display_name(progress.recorded_by)}</span>
            <span class="text-zinc-500">{progress.recorded_at}</span>
          </div>
          <p :if={progress.note not in [nil, ""]} class="mt-1 whitespace-pre-line text-zinc-700">
            {progress.note}
          </p>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [x] **Step 6: Add a label helper**

Add this private helper near the bottom of `SupportPlanLive.Show`:

```elixir
defp goal_progress_label(nil), do: gettext("未記録")
defp goal_progress_label(progress), do: GoalProgressStage.label(progress.stage)
```

- [x] **Step 7: Run the LiveView test**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs
```

Expected: PASS.

- [x] **Step 8: Extract gettext messages**

Run:

```bash
mix gettext.extract
mix gettext.extract --check-up-to-date
```

Expected: `priv/gettext/default.pot` is updated and the check exits 0.

- [x] **Step 9: Commit**

```bash
git add lib/ayumi_web/live/support_plan_live/show.ex test/ayumi_web/live/support_plan_live_test.exs priv/gettext/default.pot
git commit -m "feat: record goal progress from support plan detail"
```

---

## Task 5: Final integration and quality gate

**Files:**
- All files changed in Tasks 1-4.

- [x] **Step 1: Run focused domain tests**

Run:

```bash
mix test test/ayumi/plans/enumerations_test.exs test/ayumi/plans/goal_progress_test.exs test/ayumi/plans_test.exs
```

Expected: PASS.

- [x] **Step 2: Run focused LiveView tests**

Run:

```bash
mix test test/ayumi_web/live/support_plan_live_test.exs
```

Expected: PASS.

- [x] **Step 3: Run the full review gate**

Run:

```bash
mix review
```

Expected: `format --check-formatted`, `compile --warnings-as-errors --force`, `credo`, and `test` all pass.

- [x] **Step 4: Run the project precommit alias**

Run:

```bash
mix precommit
```

Expected: compile, unused-dependency check, format, and tests pass. If `mix precommit` formats files, continue to the next step and re-run `mix review`.

- [x] **Step 5: If `mix review` or `mix precommit` reports formatting changes**

Run:

```bash
mix format
mix review
mix precommit
```

Expected: PASS after formatting. Include formatting changes in the final commit if they touch only files from this plan.

- [x] **Step 6: Final commit if earlier commits were skipped**

If the implementation was not committed task-by-task, make one final commit:

```bash
git add lib/ayumi/plans.ex lib/ayumi/plans/goal.ex lib/ayumi/plans/goal_progress.ex lib/ayumi/plans/goal_progress_stage.ex lib/ayumi_web/live/support_plan_live/show.ex test/ayumi/plans/enumerations_test.exs test/ayumi/plans/goal_progress_test.exs test/ayumi/plans_test.exs test/ayumi_web/live/support_plan_live_test.exs test/support/fixtures/plans_fixtures.ex priv/repo/migrations/20260617000000_create_goal_progresses.exs priv/gettext/default.pot
git commit -m "feat: add append-only goal progress tracking"
```

---

## Self-Review Checklist

- [x] The progress stage vocabulary was confirmed or deliberately kept as the TODO-proposed five stages.
- [x] `goal_progresses` has `inserted_at` and no `updated_at`, `lock_version`, edit UI, delete UI, or mutable current-state column.
- [x] `recorded_by_id` is always supplied from `@current_scope.user.id` in the authenticated LiveView flow.
- [x] `recorded_at` is assigned server-side with `DateTime.utc_now(:second)`.
- [x] Current progress is derived by `Plans.current_goal_progress/1` using latest inserted id.
- [x] Plan detail uses a single grouped latest lookup for current progress and avoids one latest query per goal.
- [x] Progress history preloads `:recorded_by` before rendering staff names.
- [x] New Japanese UI strings are wrapped in `gettext(...)` and `priv/gettext/default.pot` is updated.
- [x] `mix review` and `mix precommit` pass before the implementation is considered complete.
