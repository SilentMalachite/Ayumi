# Role Separation Design (ロール分離)

Date: 2026-06-20

## Summary

Add a `role` field to staff users to distinguish service managers (サビ管 / `manager`)
from general support staff (支援者 / `supporter`). Managers can create and edit
service users and support plans; supporters have read-only access to those resources
but can still record progress updates and phase transitions.

## Roles

| Role | Value | Description |
|------|-------|-------------|
| サービス管理責任者 | `manager` | Full access |
| 支援者 | `supporter` | Record progress, view everything, cannot create/edit service users or plans |

Default role for new users: `supporter`.

## Permission Matrix

| Operation | manager | supporter |
|-----------|---------|-----------|
| Dashboard (view) | yes | yes |
| Service user list/show | yes | yes |
| Service user create/edit | yes | no |
| Support plan show | yes | yes |
| Support plan create/edit | yes | no |
| Goal progress record | yes | yes |
| Plan phase event record | yes | yes |
| Own settings (password) | yes | yes |

## Data Changes

### Migration: add `role` to `users`

```elixir
alter table(:users) do
  add :role, :string, null: false, default: "supporter"
end
```

No index needed (6 users).

### User Schema

Add `:role` field (string, default `"supporter"`).
Update `staff_changeset/3` to accept and validate `:role` against `~w(manager supporter)`.

### Enumeration Module: `Ayumi.Accounts.Role`

Follow the existing enum pattern (`all/0`, `label/1`, `options/0`).

```
manager  -> "サービス管理責任者"
supporter -> "支援者"
```

## Authorization Infrastructure

### Scope

Add `role` field to `Ayumi.Accounts.Scope`. Populated from the user on login.

```elixir
defstruct user: nil, role: nil
```

Helper: `Scope.manager?/1` returns `true` when role is `"manager"`.

### UserAuth: `require_manager` on_mount

New on_mount hook that checks `scope.role == "manager"`. If not, redirects to `/`
with a flash message ("この操作にはサービス管理責任者の権限が必要です").

### Router Changes

Split the current `:require_authenticated_user` live_session into two:

1. **`:authenticated`** — all authenticated routes (dashboard, show pages, progress
   recording, settings). Unchanged.
2. **`:require_manager`** — create/edit routes for service users and support plans.
   Adds `{AyumiWeb.UserAuth, :require_manager}` to `on_mount`.

Affected routes moved to manager session:
- `/service_users/new`
- `/service_users/:id/edit`
- `/service_users/:service_user_id/support_plans/new`

Note: `/support_plans/:id` (show) stays in the authenticated session because it
hosts the progress recording and phase transition UI.

### UI Gating

In LiveView templates, conditionally render create/edit buttons and links using
`@current_scope` role check. Supporters see the data but not the mutation controls.

Components affected:
- `ServiceUserLive.Index` — hide "New" button
- `ServiceUserLive.Show` — hide "Edit" link
- `SupportPlanLive.Show` — hide "Edit plan" link (but keep progress/phase controls)
- Navigation — no change needed (all pages are viewable)

## Mix Task Update

`mix ayumi.create_user` gains `--role` option (default: `supporter`).

```bash
mix ayumi.create_user --email mgr@ayumi.local --name "管理 花子" --password "..." --role manager
```

Interactive mode: prompt for role selection.

## Dev Seeds

Update `priv/repo/seeds.exs` to set the existing dev user (`admin@ayumi.local`) as
`manager`.

## Testing Strategy

1. **Unit**: `Role` enum module (all/label/options).
2. **Schema**: `staff_changeset` validates role inclusion.
3. **Context**: No new context functions needed (role is on User, checked in web layer).
4. **Authorization**: `Scope.manager?/1` pure function test.
5. **LiveView**: Test that supporter cannot access create/edit routes (redirected).
   Test that manager can.
6. **Mix task**: Test `--role` flag parsing.

## Non-goals

- No granular permissions beyond manager/supporter.
- No admin UI for changing roles (use mix task or iex for now).
- No per-resource ownership enforcement (all managers can edit all plans).
