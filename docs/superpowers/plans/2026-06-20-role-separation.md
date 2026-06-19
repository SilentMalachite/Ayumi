# Role Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manager/supporter role distinction so that only managers can create/edit service users and support plans, while all staff can record progress and view data.

**Architecture:** Add a `role` string field to `users` table (default `"supporter"`). Extend `Scope` to carry the role. Add a `require_manager` on_mount hook in `UserAuth`. Split router live_sessions so create/edit routes require manager role. Gate UI buttons with role checks.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, SQLite

## Global Constraints

- SQLite database (not PostgreSQL)
- TDD: write failing test first, then implement
- All tests and `mix review` must pass before moving to next task
- Japanese UI strings via gettext; English identifiers
- Follow existing enum pattern (`all/0`, `label/1`, `options/0`)
- Append-only log tables are NOT affected by this change

---

### Task 1: Role Enum Module + Tests

**Files:**
- Create: `lib/ayumi/accounts/role.ex`
- Create: `test/ayumi/accounts/role_test.exs`

**Interfaces:**
- Produces: `Ayumi.Accounts.Role.all/0` → `[:manager, :supporter]`
- Produces: `Ayumi.Accounts.Role.label/1` → `"サービス管理責任者"` | `"支援者"`
- Produces: `Ayumi.Accounts.Role.options/0` → `[{"サービス管理責任者", :manager}, {"支援者", :supporter}]`

- [ ] **Step 1: Write the failing test**

```elixir
# test/ayumi/accounts/role_test.exs
defmodule Ayumi.Accounts.RoleTest do
  use ExUnit.Case, async: true

  alias Ayumi.Accounts.Role

  test "all/0 returns both roles in order" do
    assert Role.all() == [:manager, :supporter]
  end

  test "label/1 returns Japanese labels" do
    assert Role.label(:manager) == "サービス管理責任者"
    assert Role.label(:supporter) == "支援者"
  end

  test "label/1 returns nil for unknown value" do
    assert Role.label(:unknown) == nil
  end

  test "options/0 returns {label, value} pairs for select inputs" do
    assert Role.options() == [
             {"サービス管理責任者", :manager},
             {"支援者", :supporter}
           ]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ayumi/accounts/role_test.exs`
Expected: FAIL — `Ayumi.Accounts.Role` module not found.

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/ayumi/accounts/role.ex
defmodule Ayumi.Accounts.Role do
  @moduledoc "Staff role enumeration."

  @labels [
    manager: "サービス管理責任者",
    supporter: "支援者"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/ayumi/accounts/role_test.exs`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ayumi/accounts/role.ex test/ayumi/accounts/role_test.exs
git commit -m "feat: add Role enum module with manager/supporter roles"
```

---

### Task 2: Migration + Schema + Changeset

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_role_to_users.exs`
- Modify: `lib/ayumi/accounts/user.ex:5-14` (schema), `lib/ayumi/accounts/user.ex:125-133` (staff_changeset)
- Modify: `test/ayumi/accounts_test.exs` (add role validation tests)

**Interfaces:**
- Consumes: `Ayumi.Accounts.Role.all/0`
- Produces: `User` struct now has `:role` field (string, default `"supporter"`)
- Produces: `User.staff_changeset/3` accepts and validates `:role`

- [ ] **Step 1: Write the failing tests**

Add to `test/ayumi/accounts_test.exs`, inside a new describe block:

```elixir
describe "staff_changeset/3 role validation" do
  test "defaults to supporter when role is not provided" do
    changeset =
      User.staff_changeset(%User{}, %{
        email: "test@example.com",
        name: "テスト",
        password: "a strong password"
      })

    assert Ecto.Changeset.get_field(changeset, :role) == "supporter"
  end

  test "accepts manager role" do
    changeset =
      User.staff_changeset(%User{}, %{
        email: "test@example.com",
        name: "テスト",
        password: "a strong password",
        role: "manager"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :role) == "manager"
  end

  test "rejects invalid role" do
    changeset =
      User.staff_changeset(%User{}, %{
        email: "test@example.com",
        name: "テスト",
        password: "a strong password",
        role: "admin"
      })

    refute changeset.valid?
    assert {"is invalid", _} = changeset.errors[:role]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ayumi/accounts_test.exs --only describe:"staff_changeset/3 role validation"`
Expected: FAIL — `:role` field not in schema.

- [ ] **Step 3: Create migration**

Run: `mix ecto.gen.migration add_role_to_users`

Then write:

```elixir
defmodule Ayumi.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "supporter"
    end
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 4: Update User schema**

In `lib/ayumi/accounts/user.ex`, add to the schema block after `field :name, :string`:

```elixir
field :role, :string, default: "supporter"
```

Update `staff_changeset/3` to cast and validate `:role`:

```elixir
def staff_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:email, :name, :password, :role])
  |> validate_required([:name])
  |> validate_length(:name, max: 160)
  |> validate_inclusion(:role, ~w(manager supporter))
  |> validate_email(opts)
  |> validate_password(opts)
  |> maybe_confirm()
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ayumi/accounts_test.exs`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/*_add_role_to_users.exs lib/ayumi/accounts/user.ex test/ayumi/accounts_test.exs
git commit -m "feat: add role field to users with migration and changeset validation"
```

---

### Task 3: Scope + UserAuth `require_manager` Hook

**Files:**
- Modify: `lib/ayumi/accounts/scope.ex:21` (add role to struct)
- Modify: `lib/ayumi/accounts/scope.ex:28-30` (populate role in `for_user/1`)
- Modify: `lib/ayumi_web/user_auth.ex:218-231` (add `on_mount(:require_manager, ...)`)
- Modify: `test/ayumi_web/user_auth_test.exs` (add require_manager tests)
- Modify: `test/support/fixtures/accounts_fixtures.ex` (add `manager_fixture/1`)
- Modify: `test/support/conn_case.ex` (add `register_and_log_in_manager/1`)

**Interfaces:**
- Consumes: `User.role` field
- Produces: `Scope` struct now has `:role` field
- Produces: `Scope.manager?/1` → boolean
- Produces: `UserAuth.on_mount(:require_manager, ...)` — halts non-managers with redirect to `/`
- Produces: `AccountsFixtures.manager_fixture/1` — creates a manager user for tests
- Produces: `ConnCase.register_and_log_in_manager/1` — setup helper for manager tests

- [ ] **Step 1: Write failing tests for Scope.manager?/1**

Add to `test/ayumi_web/user_auth_test.exs`:

```elixir
describe "Scope.manager?/1" do
  test "returns true for manager role" do
    user = %Ayumi.Accounts.User{role: "manager"}
    scope = Scope.for_user(user)
    assert Scope.manager?(scope)
  end

  test "returns false for supporter role" do
    user = %Ayumi.Accounts.User{role: "supporter"}
    scope = Scope.for_user(user)
    refute Scope.manager?(scope)
  end

  test "returns false for nil scope" do
    refute Scope.manager?(nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ayumi_web/user_auth_test.exs --only describe:"Scope.manager?/1"`
Expected: FAIL — `Scope.manager?/1` undefined.

- [ ] **Step 3: Update Scope module**

Replace `lib/ayumi/accounts/scope.ex`:

```elixir
defmodule Ayumi.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Ayumi.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Ayumi.Accounts.User

  defstruct user: nil, role: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user, role: user.role}
  end

  def for_user(nil), do: nil

  @doc "Returns true when the scope belongs to a manager."
  def manager?(%__MODULE__{role: "manager"}), do: true
  def manager?(_), do: false
end
```

- [ ] **Step 4: Run Scope tests**

Run: `mix test test/ayumi_web/user_auth_test.exs --only describe:"Scope.manager?/1"`
Expected: PASS

- [ ] **Step 5: Write failing test for require_manager on_mount**

Add to `test/ayumi_web/user_auth_test.exs`:

```elixir
describe "on_mount :require_manager" do
  test "allows manager to continue" do
    user = %{staff_fixture(%{role: "manager"}) | authenticated_at: DateTime.utc_now(:second)}
    token = Accounts.generate_user_session_token(user)
    session = %{"user_token" => token}

    socket =
      %LiveView.Socket{
        endpoint: AyumiWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

    {:cont, _socket} = UserAuth.on_mount(:require_manager, %{}, session, socket)
  end

  test "redirects supporter to home" do
    user = %{staff_fixture(%{role: "supporter"}) | authenticated_at: DateTime.utc_now(:second)}
    token = Accounts.generate_user_session_token(user)
    session = %{"user_token" => token}

    socket =
      %LiveView.Socket{
        endpoint: AyumiWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

    {:halt, socket} = UserAuth.on_mount(:require_manager, %{}, session, socket)
    assert socket.assigns.flash["error"] =~ "サービス管理責任者"
  end
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `mix test test/ayumi_web/user_auth_test.exs --only describe:"on_mount :require_manager"`
Expected: FAIL — `on_mount(:require_manager, ...)` clause doesn't exist.

- [ ] **Step 7: Add require_manager on_mount to UserAuth**

In `lib/ayumi_web/user_auth.ex`, add after the `on_mount(:require_sudo_mode, ...)` function (after line 246):

```elixir
def on_mount(:require_manager, _params, session, socket) do
  socket = mount_current_scope(socket, session)

  if Scope.manager?(socket.assigns[:current_scope]) do
    {:cont, socket}
  else
    socket =
      socket
      |> Phoenix.LiveView.put_flash(:error, "この操作にはサービス管理責任者の権限が必要です")
      |> Phoenix.LiveView.redirect(to: ~p"/")

    {:halt, socket}
  end
end
```

- [ ] **Step 8: Add manager_fixture and register_and_log_in_manager**

In `test/support/fixtures/accounts_fixtures.ex`, add after `staff_fixture/1`:

```elixir
@doc "Creates a confirmed staff user with the manager role."
def manager_fixture(attrs \\ %{}) do
  staff_fixture(Map.put_new(attrs, :role, "manager"))
end
```

In `test/support/conn_case.ex`, add after `register_and_log_in_user/1`:

```elixir
@doc """
Setup helper that creates a manager and logs them in.

    setup :register_and_log_in_manager
"""
def register_and_log_in_manager(%{conn: conn} = context) do
  user = Ayumi.AccountsFixtures.manager_fixture()
  scope = Ayumi.Accounts.Scope.for_user(user)

  opts =
    context
    |> Map.take([:token_authenticated_at])
    |> Enum.into([])

  %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
end
```

- [ ] **Step 9: Run all tests**

Run: `mix test test/ayumi_web/user_auth_test.exs`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add lib/ayumi/accounts/scope.ex lib/ayumi_web/user_auth.ex test/ayumi_web/user_auth_test.exs test/support/fixtures/accounts_fixtures.ex test/support/conn_case.ex
git commit -m "feat: add Scope.manager?/1 and require_manager on_mount hook"
```

---

### Task 4: Router — Split Live Sessions for Manager Routes

**Files:**
- Modify: `lib/ayumi_web/router.ex:44-62` (split live_session)
- Modify: `test/ayumi_web/live/service_user_live_test.exs` (update setup, add authorization tests)
- Modify: `test/ayumi_web/live/support_plan_live_test.exs` (update setup, add authorization tests)

**Interfaces:**
- Consumes: `UserAuth.on_mount(:require_manager, ...)`
- Produces: Manager-only routes for `/service_users/new`, `/service_users/:id/edit`, `/service_users/:service_user_id/support_plans/new`

- [ ] **Step 1: Write failing authorization tests**

In `test/ayumi_web/live/service_user_live_test.exs`, add a new describe block and update existing setup:

Replace `setup :register_and_log_in_user` at the top with nothing (each describe will declare its own setup).

```elixir
defmodule AyumiWeb.ServiceUserLiveTest do
  use AyumiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  describe "supporter access" do
    setup :register_and_log_in_user

    test "lists existing service users", %{conn: conn} do
      service_user_fixture(%{name: "既存 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      assert html =~ "既存 利用者"
    end

    test "supporter cannot access new service user form", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/service_users/new")
    end

    test "supporter cannot access edit service user form", %{conn: conn} do
      su = service_user_fixture()
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/service_users/#{su.id}/edit")
    end

    test "supporter cannot access new support plan form", %{conn: conn} do
      su = service_user_fixture()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/service_users/#{su.id}/support_plans/new")
    end

    test "supporter can view service user details", %{conn: conn} do
      su = service_user_fixture(%{name: "閲覧 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "閲覧 利用者"
    end

    test "supporter does not see 新規登録 button on index", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      refute html =~ "新規登録"
    end

    test "supporter does not see 編集 or 支援計画を作成 buttons on show", %{conn: conn} do
      su = service_user_fixture(%{name: "閲覧テスト"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      refute html =~ "編集"
      refute html =~ "支援計画を作成"
    end
  end

  describe "manager access" do
    setup :register_and_log_in_manager

    test "lists existing service users", %{conn: conn} do
      service_user_fixture(%{name: "既存 利用者"})
      {:ok, _lv, html} = live(conn, ~p"/service_users")
      assert html =~ "既存 利用者"
    end

    test "shows a 新規登録 link to the new form", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/service_users")
      assert html =~ "新規登録"

      {:ok, _form_lv, form_html} =
        lv |> element("a", "新規登録") |> render_click() |> follow_redirect(conn)

      assert form_html =~ "利用者の新規登録"
    end

    test "requires login", %{conn: _conn} do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/service_users")
    end

    test "shows a service user with their support plans", %{conn: conn} do
      su = service_user_fixture(%{name: "表示 利用者"})
      support_plan_fixture(%{service_user_id: su.id, long_term_goal: "長期目標テキスト"})

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")
      assert html =~ "表示 利用者"
      assert html =~ "長期目標テキスト"
    end

    test "shows basic info and certificates on the detail page", %{conn: conn} do
      {:ok, su} =
        Ayumi.Plans.create_service_user(%{
          name: "詳細 太郎",
          name_kana: "しょうさい たろう",
          gender: :male,
          phone: "03-1234-5678",
          recipient_cert_number: "R-777",
          disability_certificates: [%{kind: :physical, number: "B-55", grade: "2級"}]
        })

      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

      assert html =~ "詳細 太郎"
      assert html =~ "男性"
      assert html =~ "03-1234-5678"
      assert html =~ "R-777"
      assert html =~ "身体障害者手帳"
      assert html =~ "B-55"
      assert html =~ "編集"
    end

    test "detail page shows a fallback when the user has no certificates", %{conn: conn} do
      su = service_user_fixture(%{name: "手帳なし"})
      {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

      assert html =~ "手帳なし"
      assert html =~ "登録なし"
      refute html =~ ~s(id="disability-certificates")
    end

    test "navigates to the new support plan form", %{conn: conn} do
      su = service_user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}")

      {:ok, _form_lv, html} =
        lv |> element("a", "支援計画を作成") |> render_click() |> follow_redirect(conn)

      assert html =~ "支援計画の作成"
    end

    test "creates a service user with a certificate via the new form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/service_users/new")

      params = %{
        "name" => "新規 太郎",
        "name_kana" => "しんき たろう",
        "disability_certificates" => %{
          "0" => %{"kind" => "physical", "number" => "B-9", "grade" => "2級"}
        }
      }

      {:ok, _show_lv, html} =
        lv
        |> form("#service-user-form", service_user: params)
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "新規 太郎"
      assert html =~ "B-9"
    end

    test "edits a service user via the edit form", %{conn: conn} do
      su = service_user_fixture(%{name: "編集前"})
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

      {:ok, _show_lv, html} =
        lv
        |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "03-9999-0000"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "編集後"
      assert html =~ "03-9999-0000"
    end

    test "saving after a concurrent update shows a stale warning and reloads the latest", %{
      conn: conn
    } do
      su = service_user_fixture(%{name: "編集前", phone: "000"})
      {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

      {:ok, _} = Ayumi.Plans.update_service_user(su, %{phone: "111-concurrent"})

      html =
        lv
        |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "222-mine"})
        |> render_submit()

      assert html =~ "他のスタッフが先にこの利用者を更新しました"
      assert html =~ "service-user-form"
      assert html =~ "111-concurrent"
      refute html =~ "222-mine"
    end

    test "edit form warns when another staff member is editing the same user", %{conn: conn} do
      su = service_user_fixture()
      topic = AyumiWeb.Presence.editing_topic(:service_user, su.id)

      Phoenix.PubSub.subscribe(Ayumi.PubSub, topic)

      {:ok, lv1, _html} = live(conn, ~p"/service_users/#{su.id}/edit")
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 500
      refute render(lv1) =~ "編集中"

      other = staff_fixture(%{name: "別 職員"})
      conn2 = log_in_user(build_conn(), other)
      {:ok, _lv2, _html} = live(conn2, ~p"/service_users/#{su.id}/edit")

      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 500
      assert render(lv1) =~ "別 職員"
      assert render(lv1) =~ "編集中"
    end
  end
end
```

Similarly in `test/ayumi_web/live/support_plan_live_test.exs`, change `setup :register_and_log_in_user` to `setup :register_and_log_in_manager` and add:

```elixir
describe "supporter access to support plans" do
  setup :register_and_log_in_user

  test "supporter cannot access new support plan form", %{conn: conn} do
    su = service_user_fixture()

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, ~p"/service_users/#{su.id}/support_plans/new")
  end

  test "supporter can view support plan and record progress", %{conn: conn, user: staff} do
    plan = support_plan_fixture()
    goal = goal_fixture(%{support_plan_id: plan.id, description: "目標テスト"})

    {:ok, lv, html} = live(conn, ~p"/support_plans/#{plan.id}")
    assert html =~ plan.long_term_goal

    html =
      lv
      |> form("#goal-progress-form-#{goal.id}",
        goal_progress: %{stage: "working", note: "支援者が記録"}
      )
      |> render_submit()

    assert html =~ "取組中"
    assert html =~ "支援者が記録"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs test/ayumi_web/live/support_plan_live_test.exs`
Expected: FAIL — supporter can still access create/edit routes.

- [ ] **Step 3: Update router to split live sessions**

Replace the authenticated scope in `lib/ayumi_web/router.ex`:

```elixir
scope "/", AyumiWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [AyumiWeb.LanOnly, {AyumiWeb.UserAuth, :require_authenticated}] do
    live "/", DashboardLive.Index, :index
    live "/users/settings", UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

    live "/service_users", ServiceUserLive.Index, :index
    live "/service_users/:id", ServiceUserLive.Show, :show
    live "/support_plans/:id", SupportPlanLive.Show, :show
  end

  live_session :require_manager,
    on_mount: [
      AyumiWeb.LanOnly,
      {AyumiWeb.UserAuth, :require_authenticated},
      {AyumiWeb.UserAuth, :require_manager}
    ] do
    live "/service_users/new", ServiceUserLive.Form, :new
    live "/service_users/:id/edit", ServiceUserLive.Form, :edit
    live "/service_users/:service_user_id/support_plans/new", SupportPlanLive.Form, :new
  end

  post "/users/update-password", UserSessionController, :update_password
end
```

- [ ] **Step 4: Run tests to verify authorization passes**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs test/ayumi_web/live/support_plan_live_test.exs`
Expected: Some tests pass (authorization), but UI gating tests may still fail (buttons still visible for supporters). That's expected — Task 5 handles UI.

- [ ] **Step 5: Commit**

```bash
git add lib/ayumi_web/router.ex test/ayumi_web/live/service_user_live_test.exs test/ayumi_web/live/support_plan_live_test.exs
git commit -m "feat: split router live sessions to restrict create/edit to managers"
```

---

### Task 5: UI Gating — Hide Create/Edit Controls for Supporters

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/index.ex:20-22` (conditionally render button)
- Modify: `lib/ayumi_web/live/service_user_live/show.ex:27-32` (conditionally render buttons)
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex:144-155` (conditionally render add-goal form for managers only, if needed)

**Interfaces:**
- Consumes: `@current_scope` in assigns, `Scope.manager?/1`

- [ ] **Step 1: Update ServiceUserLive.Index template**

In `lib/ayumi_web/live/service_user_live/index.ex`, wrap the new-button in a role check:

Replace:
```elixir
<:actions>
  <.button navigate={~p"/service_users/new"}>{gettext("新規登録")}</.button>
</:actions>
```

With:
```elixir
<:actions :if={Ayumi.Accounts.Scope.manager?(@current_scope)}>
  <.button navigate={~p"/service_users/new"}>{gettext("新規登録")}</.button>
</:actions>
```

- [ ] **Step 2: Update ServiceUserLive.Show template**

In `lib/ayumi_web/live/service_user_live/show.ex`, wrap action buttons:

Replace:
```elixir
<:actions>
  <.button navigate={~p"/service_users/#{@service_user.id}/edit"}>{gettext("編集")}</.button>
  <.button navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}>
    {gettext("支援計画を作成")}
  </.button>
</:actions>
```

With:
```elixir
<:actions :if={Ayumi.Accounts.Scope.manager?(@current_scope)}>
  <.button navigate={~p"/service_users/#{@service_user.id}/edit"}>{gettext("編集")}</.button>
  <.button navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}>
    {gettext("支援計画を作成")}
  </.button>
</:actions>
```

- [ ] **Step 3: Run the UI gating tests**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS — supporter tests confirm buttons are hidden, manager tests confirm buttons are visible.

- [ ] **Step 4: Run full test suite**

Run: `mix test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ayumi_web/live/service_user_live/index.ex lib/ayumi_web/live/service_user_live/show.ex
git commit -m "feat: hide create/edit buttons for supporter role in service user views"
```

---

### Task 6: Mix Task + Seeds + Existing User Migration

**Files:**
- Modify: `lib/mix/tasks/ayumi.create_user.ex:32,38-44` (add `--role` switch)
- Modify: `priv/repo/seeds.exs:19-32,37-38` (set admin as manager)

**Interfaces:**
- Consumes: `Accounts.register_staff_user/1` (already accepts `:role`)

- [ ] **Step 1: Update mix task to accept --role**

In `lib/mix/tasks/ayumi.create_user.ex`:

Update `@switches`:
```elixir
@switches [email: :string, name: :string, password: :string, role: :string]
```

Update the moduledoc to include the new option:
```
  * `--role`     ロール（manager / supporter、省略時 supporter）
```

Update `run/1` to read and pass role:

```elixir
def run(args) do
  Mix.Task.run("app.start")

  {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)

  email = opts[:email] || prompt_required("メールアドレス: ")
  name = opts[:name] || prompt_required("氏名: ")
  password = opts[:password] || prompt_password("パスワード（12文字以上）: ")
  role = opts[:role] || prompt_role()

  case Accounts.register_staff_user(%{email: email, name: name, password: password, role: role}) do
    {:ok, user} ->
      Mix.shell().info("職員アカウントを作成しました: #{user.email}（#{user.role}）")

    {:error, changeset} ->
      Mix.shell().error("作成に失敗しました:")

      Enum.each(format_errors(changeset), fn {field, messages} ->
        Mix.shell().error("  - #{field}: #{Enum.join(messages, ", ")}")
      end)

      exit({:shutdown, 1})
  end
end
```

Add `prompt_role/0` private function:

```elixir
defp prompt_role do
  Mix.shell().info("ロールを選択してください:")
  Mix.shell().info("  1) supporter（支援者）")
  Mix.shell().info("  2) manager（サービス管理責任者）")

  case String.trim(Mix.shell().prompt("番号を入力 [1]: ")) do
    "" -> "supporter"
    "1" -> "supporter"
    "2" -> "manager"
    _ ->
      Mix.shell().error("1 または 2 を入力してください。")
      prompt_role()
  end
end
```

- [ ] **Step 2: Update seeds**

In `priv/repo/seeds.exs`, update `ensure_staff` to accept a role parameter:

```elixir
ensure_staff = fn email, name, role ->
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, user} =
        Accounts.register_staff_user(%{
          email: email,
          name: name,
          password: demo_password,
          role: role
        })

      IO.puts("  職員を作成: #{user.email}（#{user.role}）")
      user

    user ->
      IO.puts("  職員は既に存在: #{user.email}")
      user
  end
end
```

Update calls:
```elixir
admin = ensure_staff.("admin@ayumi.local", "管理 太郎", "manager")
_staff = ensure_staff.("staff@ayumi.local", "支援 花子", "supporter")
```

Update the login info section:
```elixir
IO.puts("""

開発用ログイン:
  admin@ayumi.local / #{demo_password} (manager)
  staff@ayumi.local / #{demo_password} (supporter)
""")
```

- [ ] **Step 3: Run mix review and full test suite**

Run: `mix test && mix review`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/mix/tasks/ayumi.create_user.ex priv/repo/seeds.exs
git commit -m "feat: add --role to mix ayumi.create_user and set admin as manager in seeds"
```

---

### Task 7: Update TODO.html — Mark Role Separation as Done

**Files:**
- Modify: `TODO.html:593-594` (check the role separation checkbox)

**Interfaces:**
- None — documentation only

- [ ] **Step 1: Mark the task as checked**

In `TODO.html`, update the role separation checkbox:

Replace:
```html
<li class="task"><input type="checkbox" id="opt-role"><label for="opt-role">ロール分離（サビ管 vs 支援者）。<span class="sub">CLAUDE.md では「後で」。今はやらない。</span></label></li>
```

With:
```html
<li class="task"><input type="checkbox" id="opt-role" checked><label for="opt-role">ロール分離（サビ管 vs 支援者）。<span class="sub">manager / supporter の2ロール。作成・編集は manager のみ。</span></label></li>
```

- [ ] **Step 2: Commit**

```bash
git add TODO.html
git commit -m "docs: mark role separation as done in TODO.html"
```
