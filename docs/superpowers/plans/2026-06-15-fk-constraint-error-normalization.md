# FK Constraint Error Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Plans.create_goal/1` return `{:error, changeset}` for an invalid `support_plan_id`, matching the original foundation plan instead of raising `Ecto.ConstraintError`.

**Architecture:** SQLite reports foreign-key violations without a constraint name (`[foreign_key: nil]`), so Ecto cannot match the generated `goals_support_plan_id_fkey` constraint annotation. Keep the schema changeset as-is, and add a narrow context-level rescue around the `Repo.insert/1` call for goals only. The rescue converts only unnamed SQLite FK violations into a `support_plan_id` changeset error and reraises every other constraint error.

**Tech Stack:** Elixir, Phoenix, Ecto, ecto_sqlite3, ExUnit. Verification uses the existing `mix review` alias.

---

## File Structure

- Modify: `test/ayumi/plans_test.exs` — restore the plan's expected behavior for invalid goal FK references.
- Modify: `lib/ayumi/plans.ex` — route `create_goal/1` through a helper that normalizes SQLite unnamed FK violations.

---

## Task 1: Restore the plan-level behavior test

**Files:**
- Modify: `test/ayumi/plans_test.exs`

- [ ] **Step 1: Replace the current raise-based test**

In `test/ayumi/plans_test.exs`, replace the current `describe "referential integrity"` block:

```elixir
  describe "referential integrity" do
    test "creating a goal for a non-existent plan is rejected by the database" do
      assert_raise Ecto.ConstraintError, fn ->
        Plans.create_goal(%{support_plan_id: -1, description: "孤児"})
      end
    end
  end
```

with:

```elixir
  describe "referential integrity" do
    test "creating a goal for a non-existent plan returns an error changeset" do
      assert {:error, changeset} =
               Plans.create_goal(%{support_plan_id: -1, description: "孤児"})

      assert errors_on(changeset)[:support_plan_id]
    end
  end
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
mix test test/ayumi/plans_test.exs:201
```

Expected: FAIL with `Ecto.ConstraintError`, proving the current implementation still raises instead of returning `{:error, changeset}`.

- [ ] **Step 3: Commit the failing regression test only if using separate TDD commits**

If committing every red/green checkpoint:

```bash
git add test/ayumi/plans_test.exs
git commit -m "test: expect changeset error for invalid goal support plan"
```

If keeping one final commit for this small fix, skip this commit and continue.

---

## Task 2: Normalize unnamed SQLite FK errors in `create_goal/1`

**Files:**
- Modify: `lib/ayumi/plans.ex`

- [ ] **Step 1: Replace `create_goal/1` with an insert helper**

In `lib/ayumi/plans.ex`, replace:

```elixir
  @doc "Creates a goal."
  def create_goal(attrs) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> Repo.insert()
  end
```

with:

```elixir
  @doc "Creates a goal."
  def create_goal(attrs) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> insert_goal()
  end
```

- [ ] **Step 2: Add the private insert helper**

In `lib/ayumi/plans.ex`, add these private functions below `change_goal/2` and before the module's final `end`:

```elixir
  defp insert_goal(changeset) do
    Repo.insert(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      if unnamed_foreign_key_constraint_error?(exception) do
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :support_plan_id,
           "does not exist",
           constraint: :foreign,
           constraint_name: nil
         )}
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp unnamed_foreign_key_constraint_error?(%Ecto.ConstraintError{
         type: :foreign_key,
         constraint: nil
       }),
       do: true

  defp unnamed_foreign_key_constraint_error?(_exception), do: false
```

Why this shape:
- `ecto_sqlite3` returns unnamed FK violations as `constraint: nil`.
- `foreign_key_constraint/3` cannot be configured with `name: nil`; Ecto falls back to the generated name.
- The helper is scoped to `create_goal/1`, so an unnamed FK here maps to `support_plan_id`.
- Other constraint errors are reraised, preserving fail-fast behavior for unexpected database failures.

- [ ] **Step 3: Run the focused test**

Run:

```bash
mix test test/ayumi/plans_test.exs:201
```

Expected: PASS.

- [ ] **Step 4: Run the related domain tests**

Run:

```bash
mix test test/ayumi/plans_test.exs test/ayumi/plans/goal_test.exs
```

Expected: PASS.

- [ ] **Step 5: Run the full quality gate**

Run:

```bash
mix review
```

Expected: format clean, compile clean, credo no issues, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/ayumi/plans.ex test/ayumi/plans_test.exs
git commit -m "fix: return changeset error for invalid goal support plan"
```

---

## Self-Review

**Spec coverage:** The original foundation plan expected invalid goal FK references to return `{:error, changeset}` with an error on `:support_plan_id`; Task 1 restores that test and Task 2 implements it.

**Placeholder scan:** No TBD/TODO/follow-up placeholders. The test replacement, implementation code, commands, and expected results are explicit.

**Type consistency:** `Plans.create_goal/1` still returns `{:ok, %Goal{}}` on success and now returns `{:error, %Ecto.Changeset{}}` for the invalid `support_plan_id` path. The private predicate matches only `%Ecto.ConstraintError{type: :foreign_key, constraint: nil}`.
