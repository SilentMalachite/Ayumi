# CLAUDE.md

Project instructions for Claude Code. Read this at the start of every session.

**Project: Ayumi** (歩み — "steps / progress"). OTP app `ayumi`, module namespace
`Ayumi`. The name reflects the design: the app records each service user's steps over
time as an append-only log, and reads the latest as the current state.

## What this project is

Ayumi is a support-plan progress tracker for a 就労継続支援B型 (type-B sheltered
employment) welfare facility. Support staff record where each service user's 個別支援計画
(individual support plan) stands, log how each short-term goal is progressing, and
the app surfaces upcoming monitoring deadlines so they are never missed.

- People who use the system: ~6 support staff.
- Service users tracked: ~35.
- Built collaboratively with AI. Favor clarity and small, reviewable steps over
  cleverness.

## Tech stack

- Elixir + Phoenix + Phoenix LiveView
- Ecto with **SQLite** via `ecto_sqlite3` — **not** PostgreSQL
- Staff authentication via `phx.gen.auth`
- No external services: no cloud, no email provider, no message queue, no
  Apple/web push backend, no background-job system (Oban is not needed).

## Deployment model (this shapes the whole design)

Single-host + LAN:

- One office PC runs the Phoenix server and owns the single SQLite database file.
- Other staff connect from their own machines with a browser over the facility
  LAN / Wi-Fi (e.g. `http://<host-ip>:4000`). Bind the endpoint so machines on the
  LAN can reach it.
- The app must work fully offline. No runtime dependency on the internet.

Hard rules that follow from this:

- The SQLite file is owned by exactly one running app instance. Never design
  anything that assumes the DB file is opened concurrently by multiple processes
  or machines.
- Never place the SQLite file on a network share (SMB/NFS) or a cloud-sync folder
  (OneDrive / iCloud / Dropbox). These corrupt SQLite under concurrent access. The
  file lives on the host's local disk.
- Enable SQLite WAL mode (`journal_mode: :wal`) for better read concurrency while
  the single writer works.

## Domain model

Two "bodies" (rarely edited) and three append-only logs.

Bodies (rarely edited):

- `support_plan` — one per planning period for a service user. Holds: service user,
  assigned staff (担当者), plan period (start / end), long-term goal (長期目標),
  and the next monitoring date (次回モニタリング予定日).
- `goal` — short-term goals (短期目標) belonging to a `support_plan`. A plan has
  several.

Append-only logs (the core idea):

- `plan_phase_event` — one row per transition of a plan through its lifecycle stage.
- `goal_progress` — one row per progress update of a `goal`.
- `support_record` — one row per daily support note for a service user (category,
  content, recorded_by, recorded_at).

### Append-only principle (do not violate)

- State changes are recorded as **new rows**, never by overwriting existing rows.
- Corrections are also new rows, so history is never lost. This matters for welfare
  documentation and auditability.
- "Current state" is **derived**, not stored: the latest `plan_phase_event` for a
  plan is its current stage; the latest `goal_progress` for a goal is its current
  progress. Do **not** add a mutable `current_stage` column that gets updated in
  place.
- Prefer a pure function that folds the log into the current state, so it is trivial
  to unit-test.

### Enumerations

Plan lifecycle stages (`plan_phase_event.stage`), in order:

`assessment` → `draft` → `support_meeting` → `consent` → `in_progress` →
`monitoring` → `review` (then a new plan begins).

(JP: アセスメント → 計画原案 → 個別支援会議 → 説明・同意・交付 → 支援の実施 →
モニタリング → 見直し)

Goal progress stages (`goal_progress.stage`) — current implemented set. Labels live
in `Ayumi.Plans.GoalProgressStage`; if the facility changes the wording, update the
enum module, tests, and UI together:

`not_started` / `working` / `partially_met` / `mostly_met` / `met`

(JP: 未着手 / 取組中 / 一部達成 / 概ね達成 / 達成)

Every append-only row carries: who recorded it, when, the new stage/value, and a
free-text note (所見).

## Notifications (monitoring deadlines)

Goal: make sure approaching and overdue monitoring deadlines are not missed, for a
team where email is routinely ignored.

- **Reliable baseline (done):** the dashboard surfaces near and overdue
  deadlines at the top, computed by an Ecto query on page load. Staff see it because
  they already open the app for their work. No email, no scheduled job needed for
  this layer.
- **Optional nudge (done):** while the app is open, a LiveView hook
  (`DeadlineNotifier` in `assets/js/hooks/deadline_notifier.js`) fires an OS
  desktop notification via the browser Web Notifications API. It is a bonus —
  it depends on a per-browser permission grant, so it is never the guarantee. The
  in-app list is the guarantee.
- Out of scope: email, Apple push, mobile push. Do not add them.

Dashboard defaults for the current plan: show **all** facility deadlines, sort the
viewer’s own assigned users first, and treat deadlines within 30 days as near.

## How to work in this repo

- **Conclusion first.** Lead with the answer or decision, then the reasoning.
- **TDD first.** Write the failing test before the implementation. Start with context
  functions and Ecto changesets.
- **Minimal diff, report scope.** Make the smallest change that does the job. After
  editing, state exactly which files and functions changed, and why.
- **One improvement at a time.** Do not bundle unrelated changes. If you spot other
  things worth fixing, list them and ask — do not act on them in the same pass.
- **Design before code.** For anything non-trivial, describe the intended structure
  and data flow first, get agreement, then implement.
- **`mix review` is the quality gate.** Work is not "done" until it (and the tests)
  pass. Run them before declaring completion.
- Ask before large refactors, schema changes beyond the agreed model, or adding
  dependencies.

## Collaboration style

- Explanations should be concept-first and structure-led: describe the shape of the
  solution before the line-by-line detail.
- Keep changes small and explicit about what moved; avoid large diffs that are hard
  to track.
- Prefer making the current state of things derivable and visible over something that
  has to be held in mind.

## Code conventions

- Domain logic lives in Phoenix **contexts**. Keep LiveViews thin: assigns and event
  handlers only, with logic delegated to contexts.
- All validation lives in Ecto **changesets**; no ad-hoc validation inside LiveView.
- Code identifiers, module names, and comments are in **English**. User-facing strings
  are in **Japanese** (the staff are Japanese) — keep them via `gettext` or in one
  central place, not scattered as inline literals.
- Prefer pure functions for anything that derives state (e.g. "current stage from
  events"); keep them easy to unit-test.
- ExUnit for tests. Test contexts and changesets directly; add LiveView tests for the
  key user flows.

## Non-goals

- No PostgreSQL, no cloud hosting, no multi-tenant design.
- No internet-dependent features at runtime.
- No email or push delivery.
- Keep auth simple (local staff accounts with two roles: manager / supporter).

## Build order (current status)

Scaffold with `mix phx.new ayumi --database sqlite3`.

1. Done: `support_plan` + `goal`: create a plan, attach short-term goals, list them.
   Plus `phx.gen.auth` staff login.
2. Done: `goal_progress`: record progress updates per goal (the most-used screen).
   Derive current progress from the latest row.
3. Done: `plan_phase_event` + the monitoring-deadline dashboard: stage transitions, and the
   "deadlines near / overdue" surfacing on the authenticated dashboard.
4. Done: Role separation (manager / supporter). Route-level authorization via
   `on_mount(:require_manager)`, UI gating via `Scope.manager?/1`. Service user and
   support plan create/edit are manager-only; progress recording and viewing are for all
   authenticated staff.

Optional (done):
- Web Notifications nudge via `DeadlineNotifier` JS hook + `push_event` from
  `DashboardLive.Index`. Browser permission required; the in-app list remains
  the guarantee layer.
- Windows binary CI release via GitHub Actions (`release.yml`). `v*` tag push
  builds a Mix release on a Windows runner and attaches the zip to a GitHub
  Release. `Ayumi.Release` module provides `migrate/0` and `create_user/0`
  for `bin/ayumi eval` in compiled releases.
- `support_record` (支援記録): daily support notes per service user, append-only
  with category (work / daily_living / health / interview / other), content,
  recorded_by, recorded_at. `/support_records` for listing, filtering, creating.
- Service user summary page: `ServiceUserLive.Show` extended with deadline badges
  (cert expiry + monitoring), current plan goals with latest progress, recent
  goal progress / phase events (20), and recent support records (20). Read-only
  aggregation, no schema change.

All steps are complete and green. Each was `mix review`-clean before merging.
