# 同時編集の安全化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Eliminate silent lost-updates when two staff edit the same body record (service_user / support_plan / goal), and surface "○○さん編集中" so collisions are reduced — fully offline, no external dependency.

**Architecture:** Two layers on the body tables. Layer A (optimistic lock, hard guarantee): a `lock_version` integer column + `Ecto.Changeset.optimistic_lock/2` in the update path; a stale write raises `Ecto.StaleEntryError`, which the context rescues into `{:error, :stale}`. Layer B (presence, soft/advisory): `AyumiWeb.Presence` (built on the already-running `Ayumi.PubSub`) tracks who has the edit form open and the LiveView shows a warning banner. Layer A guarantees correctness even if Layer B is ignored.

**Tech Stack:** Elixir, Phoenix 1.8.8, Phoenix LiveView 1.1.32, Phoenix.Presence (phoenix_pubsub 2.2.0), Ecto + SQLite (`ecto_sqlite3`, WAL).

**Scope this plan ships (per design §スコープ):** the `lock_version` **column on all three bodies** (one migration, future-proofs support_plan/goal), but Layer A wiring + Layer B presence only on the **service_user edit screen** (the only body that currently has an update function + edit UI). `support_plan` / `goal` get the same pattern later, when they gain update functions and edit UIs — the column will already be there.

**Out of scope (design §非目標):** auto-merge / conflict resolution, changes to append-only logs, assignee-based access scoping, making bodies append-only (案C).

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `priv/repo/migrations/20260614020000_add_lock_version_to_bodies.exs` | Create | Add `lock_version` to `service_users`, `support_plans`, `goals` |
| `lib/ayumi/plans/service_user.ex` | Modify | Add `field :lock_version, :integer, default: 0` (NOT cast) |
| `lib/ayumi/plans/support_plan.ex` | Modify | Add `field :lock_version, :integer, default: 0` (NOT cast) |
| `lib/ayumi/plans/goal.ex` | Modify | Add `field :lock_version, :integer, default: 0` (NOT cast) |
| `lib/ayumi/plans.ex` | Modify | `update_service_user/2`: `optimistic_lock` + rescue `StaleEntryError` → `{:error, :stale}` |
| `lib/ayumi_web/presence.ex` | Create | `AyumiWeb.Presence` + `editing_topic/2` helper |
| `lib/ayumi/application.ex` | Modify | Add `AyumiWeb.Presence` to the supervision tree (after PubSub) |
| `lib/ayumi_web/live/service_user_live/form.ex` | Modify | Presence track/subscribe/diff + warning banner; `{:error, :stale}` branch + reload |
| `test/ayumi/plans_optimistic_lock_test.exs` | Create | lock_version default, non-cast guards (all 3 bodies), bump, stale-detection tests — `async: false` |
| `test/ayumi_web/presence_test.exs` | Create | `editing_topic/2` unit test |
| `test/ayumi_web/live/service_user_live_test.exs` | Modify | stale-on-save flow + concurrent-editing warning |

**Note on test async (decided):** per the project convention ("DB tests must be `async: false`"), the optimistic-lock context tests live in a dedicated `test/ayumi/plans_optimistic_lock_test.exs` with `use Ayumi.DataCase, async: false`, rather than being appended to `plans_test.exs` (which stays `async: true`). This keeps the concurrency tests isolated and convention-compliant.

---

## Task 1: `lock_version` column + schema fields

Add the column to all three body tables and the (non-cast) field to all three schemas. TDD driver: new body records must start at `lock_version == 0`.

**Files:**
- Create: `priv/repo/migrations/20260614020000_add_lock_version_to_bodies.exs`
- Modify: `lib/ayumi/plans/service_user.ex`
- Modify: `lib/ayumi/plans/support_plan.ex`
- Modify: `lib/ayumi/plans/goal.ex`
- Test: `test/ayumi/plans_test.exs`

- [x] **Step 1: Write the failing tests**

Add this `describe` block to `test/ayumi/plans_test.exs` (after the existing `describe "goals"` block, before `describe "referential integrity"`):

```elixir
  describe "optimistic locking" do
    test "new body records start at lock_version 0" do
      assert service_user_fixture().lock_version == 0
      assert support_plan_fixture().lock_version == 0
      assert goal_fixture().lock_version == 0
    end

    test "changeset/2 ignores a lock_version supplied via params (no form tampering)" do
      cs = ServiceUser.changeset(%ServiceUser{}, %{"name" => "X", "lock_version" => "999"})
      refute Map.has_key?(cs.changes, :lock_version)
    end
  end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `mix test test/ayumi/plans_test.exs --only describe:"optimistic locking"` — or simply `mix test test/ayumi/plans_test.exs`
Expected: FAIL — the `lock_version == 0` test raises `KeyError` (no such struct field) / DB error (no such column). The non-cast test will pass already (it is a regression guard, kept for intent).

- [x] **Step 3: Create the migration**

Create `priv/repo/migrations/20260614020000_add_lock_version_to_bodies.exs`:

```elixir
defmodule Ayumi.Repo.Migrations.AddLockVersionToBodies do
  use Ecto.Migration

  def change do
    alter table(:service_users) do
      add :lock_version, :integer, null: false, default: 0
    end

    alter table(:support_plans) do
      add :lock_version, :integer, null: false, default: 0
    end

    alter table(:goals) do
      add :lock_version, :integer, null: false, default: 0
    end
  end
end
```

- [x] **Step 4: Add the field to `ServiceUser`**

In `lib/ayumi/plans/service_user.ex`, inside `schema "service_users" do`, add the field immediately after `field :notes, :string` (the last flat field, before the `has_many` associations). Do **not** add it to `@flat_fields`.

```elixir
    field :notes, :string

    field :lock_version, :integer, default: 0

    has_many :support_plans, Ayumi.Plans.SupportPlan
```

- [x] **Step 5: Add the field to `SupportPlan`**

In `lib/ayumi/plans/support_plan.ex`, inside `schema "support_plans" do`, add the field after `field :next_monitoring_date, :date` (before the `belongs_to` associations). Do **not** add it to `@required`.

```elixir
    field :next_monitoring_date, :date

    field :lock_version, :integer, default: 0

    belongs_to :service_user, Ayumi.Plans.ServiceUser
```

- [x] **Step 6: Add the field to `Goal`**

In `lib/ayumi/plans/goal.ex`, inside `schema "goals" do`, add the field after `field :description, :string` (before the `belongs_to`). Do **not** add it to the `cast/3` list.

```elixir
    field :description, :string

    field :lock_version, :integer, default: 0

    belongs_to :support_plan, Ayumi.Plans.SupportPlan
```

- [x] **Step 7: Migrate and run the tests**

Run: `mix ecto.migrate`
Expected: three `alter table ... add :lock_version` statements succeed.

Run: `mix test test/ayumi/plans_test.exs`
Expected: PASS (including the existing service-users / support-plans / goals tests, unchanged).

- [x] **Step 8: Commit**

```bash
git add priv/repo/migrations/20260614020000_add_lock_version_to_bodies.exs \
  lib/ayumi/plans/service_user.ex lib/ayumi/plans/support_plan.ex lib/ayumi/plans/goal.ex \
  test/ayumi/plans_test.exs
git commit -m "feat: add lock_version column and schema field to body tables"
```

---

## Task 2: Optimistic lock in `update_service_user/2`

Wire `optimistic_lock` into the only existing update path and rescue the stale write into a tagged tuple.

**Files:**
- Modify: `lib/ayumi/plans.ex:40-44` (`update_service_user/2`)
- Test: `test/ayumi/plans_test.exs`

- [x] **Step 1: Write the failing tests**

Add these two tests **inside the `describe "optimistic locking"` block** created in Task 1:

```elixir
    test "update_service_user/2 bumps lock_version on success" do
      su = service_user_fixture()
      assert su.lock_version == 0
      assert {:ok, updated} = Plans.update_service_user(su, %{phone: "03-1111-2222"})
      assert updated.lock_version == 1
    end

    test "update_service_user/2 returns {:error, :stale} on a concurrent update" do
      su = service_user_fixture()

      # Two staff load the same row (both at lock_version 0).
      a = Plans.get_service_user!(su.id)
      b = Plans.get_service_user!(su.id)

      assert {:ok, _} = Plans.update_service_user(a, %{phone: "first"})
      assert {:error, :stale} = Plans.update_service_user(b, %{phone: "second"})

      # The first writer's value survives; the second was rejected, never silently lost.
      assert Plans.get_service_user!(su.id).phone == "first"
    end
```

- [x] **Step 2: Run tests to verify they fail**

Run: `mix test test/ayumi/plans_test.exs`
Expected: FAIL — `bumps lock_version` fails (`updated.lock_version == 0`, no increment); `returns {:error, :stale}` fails because the second update silently succeeds (`{:ok, _}` instead of `{:error, :stale}`), proving the lost-update bug is currently present.

- [x] **Step 3: Add `optimistic_lock` + rescue**

Replace the body of `update_service_user/2` in `lib/ayumi/plans.ex` (currently lines 40-44):

```elixir
  def update_service_user(%ServiceUser{} = service_user, attrs) do
    service_user
    |> ServiceUser.changeset(drop_blank_certificates(attrs))
    |> Ecto.Changeset.optimistic_lock(:lock_version)
    |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end
```

Note: `optimistic_lock/2` adds `WHERE lock_version = <loaded value>` and increments the column on success, so the in-memory struct returned by `{:ok, _}` already has the bumped value. `service_user.data` (the struct passed in) supplies the expected version — no hidden form field needed.

- [x] **Step 4: Run the tests**

Run: `mix test test/ayumi/plans_test.exs`
Expected: PASS — all optimistic-locking tests green, and the existing `update_service_user/2` tests (flat fields, certificate update/delete) still pass.

- [x] **Step 5: Commit**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans_test.exs
git commit -m "feat: optimistic lock on update_service_user to block lost updates"
```

---

## Task 3: `AyumiWeb.Presence` module + supervision tree

Add the Presence server (advisory layer) and a topic helper. Built on the already-running `Ayumi.PubSub` — no new external dependency.

**Files:**
- Create: `lib/ayumi_web/presence.ex`
- Modify: `lib/ayumi/application.ex`
- Test: `test/ayumi_web/presence_test.exs`

- [x] **Step 1: Write the failing test**

Create `test/ayumi_web/presence_test.exs`:

```elixir
defmodule AyumiWeb.PresenceTest do
  use ExUnit.Case, async: true

  test "editing_topic/2 builds a per-record topic" do
    assert AyumiWeb.Presence.editing_topic(:service_user, 7) == "editing:service_user:7"
  end
end
```

- [x] **Step 2: Run the test to verify it fails**

Run: `mix test test/ayumi_web/presence_test.exs`
Expected: FAIL — `AyumiWeb.Presence` does not exist (compile error / `UndefinedFunctionError`).

- [x] **Step 3: Create the Presence module**

Create `lib/ayumi_web/presence.ex`:

```elixir
defmodule AyumiWeb.Presence do
  @moduledoc """
  Tracks which staff currently have a body-record edit form open, so the UI can
  warn about concurrent edits. Advisory only — the optimistic lock in
  `Ayumi.Plans` is what actually prevents lost updates. Runs on the local
  `Ayumi.PubSub`; no external dependency.
  """
  use Phoenix.Presence,
    otp_app: :ayumi,
    pubsub_server: Ayumi.PubSub

  @doc """
  PubSub/Presence topic for the edit form of a given body record, e.g.
  `editing_topic(:service_user, 5) == "editing:service_user:5"`.
  """
  def editing_topic(kind, id) when is_atom(kind), do: "editing:#{kind}:#{id}"
end
```

- [x] **Step 4: Add Presence to the supervision tree**

In `lib/ayumi/application.ex`, add `AyumiWeb.Presence` to the `children` list immediately after the PubSub entry:

```elixir
      {Phoenix.PubSub, name: Ayumi.PubSub},
      AyumiWeb.Presence,
      # Start a worker by calling: Ayumi.Worker.start_link(arg)
```

- [x] **Step 5: Run the test**

Run: `mix test test/ayumi_web/presence_test.exs`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add lib/ayumi_web/presence.ex lib/ayumi/application.ex test/ayumi_web/presence_test.exs
git commit -m "feat: add AyumiWeb.Presence for concurrent-edit awareness"
```

---

## Task 4: Wire Layer A + Layer B into the service-user edit LiveView

Add the `{:error, :stale}` save branch with reload (Layer A UX) and Presence track/subscribe/diff + warning banner (Layer B) to `service_user_live/form.ex`.

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/form.ex`
- Test: `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: Write the failing LiveView tests**

Append these two tests to `test/ayumi_web/live/service_user_live_test.exs` (after the existing `"edits a service user via the edit form"` test):

```elixir
  test "saving after a concurrent update shows a stale warning and reloads the latest", %{
    conn: conn
  } do
    su = service_user_fixture(%{name: "編集前", phone: "000"})
    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

    # Another staff member updates the same row behind this LiveView's back.
    {:ok, _} = Ayumi.Plans.update_service_user(su, %{phone: "111-concurrent"})

    html =
      lv
      |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "222-mine"})
      |> render_submit()

    # Stayed on the edit form (no redirect), with a stale warning and the latest data.
    assert html =~ "他のスタッフが先にこの利用者を更新しました"
    assert html =~ "service-user-form"
    assert html =~ "111-concurrent"
    refute html =~ "222-mine"
  end

  test "edit form warns when another staff member is editing the same user", %{conn: conn} do
    su = service_user_fixture()
    topic = AyumiWeb.Presence.editing_topic(:service_user, su.id)

    # Subscribe the test process to synchronize on presence broadcasts.
    Phoenix.PubSub.subscribe(Ayumi.PubSub, topic)

    {:ok, lv1, _html} = live(conn, ~p"/service_users/#{su.id}/edit")
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
    refute render(lv1) =~ "編集中"

    # A different staff member opens the same edit form in a separate session.
    other = staff_fixture(%{name: "別 職員"})
    conn2 = log_in_user(build_conn(), other)
    {:ok, _lv2, _html} = live(conn2, ~p"/service_users/#{su.id}/edit")

    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
    assert render(lv1) =~ "別 職員"
    assert render(lv1) =~ "編集中"
  end
```

These rely on helpers already imported/aliased in the test module: `service_user_fixture/1`, `staff_fixture/1` (from `Ayumi.PlansFixtures` / `Ayumi.AccountsFixtures`), and `log_in_user/2` + `build_conn/0` (from `AyumiWeb.ConnCase`). `staff_fixture/1` sets `name`, so `User.display_name/1` returns "別 職員".

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: FAIL — the stale test currently gets a redirect/crash (no `:stale` branch), and the warning test never sees "編集中" (no Presence wiring / no banner).

- [x] **Step 3: Add the `User` alias**

In `lib/ayumi_web/live/service_user_live/form.ex`, add an alias for the accounts `User` (used for `display_name/1`) below the existing aliases:

```elixir
  alias Ayumi.Plans
  alias Ayumi.Plans.{CertificateKind, DisabilityCertificate, Gender, ServiceUser, SupportCategory}
  alias Ayumi.Accounts.User
```

- [x] **Step 4: Default `:other_editors` on the new form**

In `apply_action(socket, :new, _params)`, add `|> assign(:other_editors, [])` so the banner code can render on the new form too. Replace the trailing assign chain:

```elixir
    socket
    |> assign(:page_title, "利用者の新規登録")
    |> assign(:service_user, service_user)
    |> assign(:other_editors, [])
    |> assign_form(changeset)
  end
```

- [x] **Step 5: Refactor `apply_action(:edit)` to extract the changeset and start presence**

Replace the whole `apply_action(socket, :edit, %{"id" => id})` clause with:

```elixir
  defp apply_action(socket, :edit, %{"id" => id}) do
    service_user = Plans.get_service_user!(id)

    socket
    |> assign(:page_title, "利用者の編集")
    |> assign(:service_user, service_user)
    |> track_editing(service_user.id)
    |> assign_form(edit_changeset(service_user))
  end
```

- [x] **Step 6: Add the private helpers**

Add these private functions to `lib/ayumi_web/live/service_user_live/form.ex` (place them next to the other private helpers, e.g. just above `defp assign_form/2`):

```elixir
  defp edit_changeset(%ServiceUser{} = service_user) do
    if service_user.disability_certificates == [] do
      Plans.change_service_user(service_user)
      |> Ecto.Changeset.put_assoc(:disability_certificates, [%DisabilityCertificate{}])
    else
      Plans.change_service_user(service_user)
    end
  end

  defp track_editing(socket, service_user_id) do
    topic = AyumiWeb.Presence.editing_topic(:service_user, service_user_id)

    if connected?(socket) do
      user = socket.assigns.current_scope.user
      Phoenix.PubSub.subscribe(Ayumi.PubSub, topic)

      AyumiWeb.Presence.track(self(), topic, to_string(user.id), %{
        name: User.display_name(user)
      })
    end

    socket
    |> assign(:editing_topic, topic)
    |> assign_other_editors()
  end

  defp assign_other_editors(socket) do
    self_key = to_string(socket.assigns.current_scope.user.id)

    others =
      socket.assigns.editing_topic
      |> AyumiWeb.Presence.list()
      |> Enum.reject(fn {key, _presence} -> key == self_key end)
      |> Enum.flat_map(fn {_key, %{metas: metas}} -> Enum.map(metas, & &1.name) end)
      |> Enum.uniq()

    assign(socket, :other_editors, others)
  end

  defp reload_edit_form(socket) do
    service_user = Plans.get_service_user!(socket.assigns.service_user.id)

    socket
    |> assign(:service_user, service_user)
    |> assign_form(edit_changeset(service_user))
  end
```

- [x] **Step 7: Handle presence diffs**

Add a `handle_info/2` clause to `lib/ayumi_web/live/service_user_live/form.ex` (e.g. just below the `handle_event("save", ...)` clause):

```elixir
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_other_editors(socket)}
  end
```

- [x] **Step 8: Add the `{:error, :stale}` save branch**

Replace `save_service_user(socket, :edit, params)` with a three-way case that adds the stale branch:

```elixir
  defp save_service_user(socket, :edit, params) do
    case Plans.update_service_user(socket.assigns.service_user, params) do
      {:ok, service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "利用者情報を更新しました")
         |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "他のスタッフが先にこの利用者を更新しました。最新を読み込みました。内容を確認して保存し直してください。"
         )
         |> reload_edit_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
```

- [x] **Step 9: Add the warning banner to `render/1`**

In the `render/1` HEEx, immediately after `<.header>{@page_title}</.header>`, add the advisory banner:

```heex
      <.header>{@page_title}</.header>

      <div
        :if={@other_editors != []}
        class="rounded border border-yellow-400 bg-yellow-100 px-4 py-2 my-4 text-yellow-800"
        role="alert"
      >
        ⚠ {Enum.join(@other_editors, "、")} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。
      </div>
```

- [x] **Step 10: Run the LiveView tests**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS — both new tests green, and the existing edit/new/show tests still pass.

- [x] **Step 11: Commit**

```bash
git add lib/ayumi_web/live/service_user_live/form.ex test/ayumi_web/live/service_user_live_test.exs
git commit -m "feat: stale-save handling and editing-presence warning on service-user edit"
```

---

## Task 5: Quality gate

Run the full gate and confirm green before declaring done.

- [x] **Step 1: Run the full suite**

Run: `mix test`
Expected: PASS, 0 failures.

- [x] **Step 2: Run the review gate**

Run: `mix review`
Expected: `format --check-formatted` clean, `compile --warnings-as-errors --force` clean, `credo` clean, `test` green. Fix any issue (commonly: run `mix format`) and re-run until clean.

- [x] **Step 3: Final commit (only if the gate forced changes)**

```bash
git add -A
git commit -m "chore: mix review clean for concurrent-edit safety"
```

---

## Self-Review

**1. Spec coverage (design → task):**
- 案A migration on all 3 bodies → Task 1 (one migration, 3 `alter`s). ✅
- 案A schema field, not cast → Task 1 Steps 4-6 + non-cast guard test. ✅
- 案A context `optimistic_lock` + `StaleEntryError` rescue → Task 2. ✅
- 案A LiveView third branch + reload-and-assign → Task 4 Steps 5/6/8. ✅
- 案B `AyumiWeb.Presence` + supervision tree → Task 3. ✅
- 案B topic helper → Task 3 (`editing_topic/2`). ✅
- 案B subscribe + track on connected edit mount, others assign → Task 4 Step 6 (`track_editing`, `assign_other_editors`). ✅
- 案B presence_diff handle_info → Task 4 Step 7. ✅
- 案B warning banner, save button stays active → Task 4 Step 9 (banner only; no `disabled`). ✅
- 案B auto-untrack on process exit → free (Phoenix.Presence default; no manual cleanup). ✅
- Error handling: changeset vs `:stale` distinct; non-`StaleEntryError` DB errors not swallowed → Task 2 rescues **only** `Ecto.StaleEntryError`. ✅
- Tests: context (bump,先勝ち/後勝ち), changeset non-cast, LiveView (success unchanged, stale reload, two-mount warning) → Tasks 1/2/4. The "編集成功パスが従来どおり" case is covered by the pre-existing `"edits a service user via the edit form"` test, which Task 4 must keep green. ✅

**2. Placeholder scan:** No TBD/“add error handling”/“similar to Task N”. Every code step shows full code. ✅

**3. Type consistency:** `lock_version` (int, default 0) consistent across migration + 3 schemas. `editing_topic/2` signature `(atom, id)` used identically in `track_editing/2` and both tests. `{:error, :stale}` produced in `Ayumi.Plans.update_service_user/2` and matched in `save_service_user(:edit, …)`. Presence key `to_string(user.id)` used at both `track` and `reject`. `:other_editors` assigned in `apply_action(:new)`, `assign_other_editors/1`, and read in `render/1`. ✅

---

## Notes / open questions for the reviewer

- **Test async (see header note):** appended to `plans_test.exs` at `async: true`; design/memory suggest `async: false`. Confirm or split into a dedicated `async: false` file.
- **Presence test determinism:** the warning test subscribes the test process to the topic and `assert_receive`s the `presence_diff` before re-rendering `lv1`. On a single node the diff is dispatched to all local subscribers in one broadcast, so once the test process has it, `lv1` has it queued before the subsequent `render/1` — deterministic. If it ever flakes under load, gate the second `render` behind a short `assert_receive`-then-retry rather than `Process.sleep`.
- **support_plan / goal:** column shipped now; `optimistic_lock` + presence wiring deferred until they gain update functions and edit UIs (design §スコープ). When added, reuse `editing_topic(:support_plan, id)` / `editing_topic(:goal, id)` and the same `update_*` rescue pattern.
