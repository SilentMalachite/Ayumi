defmodule Ayumi.Plans do
  @moduledoc """
  The Plans context: service users, support plans, goals, and (later) the
  append-only progress and phase-event logs. Current state is derived, never stored.
  """
  import Ecto.Query, warn: false
  alias Ayumi.Repo

  alias Ayumi.Accounts.User
  alias Ayumi.Plans.Goal
  alias Ayumi.Plans.GoalProgress
  alias Ayumi.Plans.ServiceUser
  alias Ayumi.Plans.SupportPlan

  ## Service users

  @doc "Lists service users, ordered by kana then name."
  def list_service_users do
    ServiceUser
    |> order_by([s], asc: s.name_kana, asc: s.name)
    |> Repo.all()
  end

  @doc "Gets a single service user with certificates preloaded. Raises if not found."
  def get_service_user!(id) do
    ServiceUser
    |> preload(:disability_certificates)
    |> Repo.get!(id)
  end

  @doc "Creates a service user. Blank certificate rows are dropped before insert."
  def create_service_user(attrs) do
    %ServiceUser{}
    |> ServiceUser.changeset(drop_blank_certificates(attrs))
    |> Repo.insert()
  end

  @doc """
  Updates a service user's basic info and certificates. The struct must have
  `:disability_certificates` preloaded so `on_replace: :delete` can delete rows
  that were blanked out. Blank certificate rows are dropped before update.
  """
  def update_service_user(%ServiceUser{} = service_user, attrs) do
    service_user
    |> ServiceUser.changeset(drop_blank_certificates(attrs))
    |> Ecto.Changeset.optimistic_lock(:lock_version)
    |> Repo.update()
  rescue
    # Raised when the UPDATE's WHERE (id + lock_version) matches no row: another
    # staff member updated this record first, or it was deleted in the meantime.
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @doc "Returns a changeset for tracking service user changes (forms)."
  def change_service_user(%ServiceUser{} = service_user, attrs \\ %{}) do
    ServiceUser.changeset(service_user, attrs)
  end

  @doc """
  Removes all-blank disability-certificate rows from form params so an untouched
  certificate row is never persisted. A row is blank when every content field
  (`kind`/`number`/`disability_name`/`grade`) is empty. The key is kept (possibly
  as an empty map) so `cast_assoc` still runs and deletes unmatched existing rows
  on update. Pure and string-keyed (the form path); atom-keyed params pass through
  unchanged. Safe to unit-test.
  """
  def drop_blank_certificates(attrs) when is_map(attrs) do
    case Map.pop(attrs, "disability_certificates") do
      {certs, rest} when is_map(certs) ->
        kept =
          certs
          |> Enum.reject(fn {_index, cert} -> blank_certificate?(cert) end)
          |> Map.new()

        Map.put(rest, "disability_certificates", kept)

      {_other, _rest} ->
        attrs
    end
  end

  defp blank_certificate?(cert) when is_map(cert) do
    ~w(kind number disability_name grade)
    |> Enum.all?(fn key -> blank_value?(Map.get(cert, key)) end)
  end

  defp blank_certificate?(_), do: false

  defp blank_value?(nil), do: true
  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(_), do: false

  ## Support plans

  @doc "Lists a service user's plans, newest planning period first."
  def list_support_plans_for_user(%ServiceUser{id: id}), do: list_support_plans_for_user(id)

  def list_support_plans_for_user(service_user_id) when is_integer(service_user_id) do
    SupportPlan
    |> where([p], p.service_user_id == ^service_user_id)
    |> order_by([p], desc: p.period_start, desc: p.id)
    |> preload([:staff])
    |> Repo.all()
  end

  @doc "Gets a support plan with service_user, staff and goals preloaded. Raises if not found."
  def get_support_plan!(id) do
    SupportPlan
    |> preload([:service_user, :staff, :goals])
    |> Repo.get!(id)
  end

  @doc "Creates a support plan."
  def create_support_plan(attrs) do
    %SupportPlan{}
    |> SupportPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a changeset for a support plan (forms)."
  def change_support_plan(%SupportPlan{} = support_plan, attrs \\ %{}) do
    SupportPlan.changeset(support_plan, attrs)
  end

  ## Goals

  @doc "Lists a plan's goals in insertion order (oldest first)."
  def list_goals(%SupportPlan{id: id}), do: list_goals(id)

  def list_goals(support_plan_id) when is_integer(support_plan_id) do
    Goal
    |> where([g], g.support_plan_id == ^support_plan_id)
    |> order_by([g], asc: g.id)
    |> Repo.all()
  end

  @doc "Creates a goal."
  def create_goal(attrs) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> insert_goal()
  end

  @doc "Returns a changeset for a goal (forms)."
  def change_goal(%Goal{} = goal, attrs \\ %{}) do
    Goal.changeset(goal, attrs)
  end

  ## Goal progress

  @doc "Returns a changeset for a goal progress row (forms)."
  def change_goal_progress(%GoalProgress{} = goal_progress, attrs \\ %{}) do
    GoalProgress.changeset(goal_progress, attrs)
  end

  @doc "Appends a goal progress row. Existing rows are never updated."
  def record_goal_progress(attrs) do
    %GoalProgress{}
    |> GoalProgress.changeset(attrs)
    |> insert_goal_progress()
  end

  @doc "Appends progress only when the goal belongs to the given support plan."
  def record_goal_progress_for_plan(%SupportPlan{id: support_plan_id}, attrs)
      when is_map(attrs) do
    case parse_goal_progress_goal_id(attrs) do
      {:ok, goal_id} ->
        if goal_belongs_to_support_plan?(goal_id, support_plan_id) do
          attrs
          |> normalize_goal_progress_attrs(goal_id)
          |> record_goal_progress()
        else
          {:error, scoped_goal_progress_changeset(attrs, goal_id)}
        end

      :error ->
        {:error, scoped_goal_progress_changeset(attrs, nil)}
    end
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

  @doc "Lists progress histories for multiple goals, grouped by goal id."
  def list_goal_progress_for_goals([]), do: %{}

  def list_goal_progress_for_goals(goals) when is_list(goals) do
    goal_ids = Enum.map(goals, & &1.id)
    empty_map = Map.new(goal_ids, &{&1, []})

    histories =
      GoalProgress
      |> where([p], p.goal_id in ^goal_ids)
      |> order_by([p], asc: p.goal_id, asc: p.id)
      |> preload([:recorded_by])
      |> Repo.all()
      |> Enum.group_by(& &1.goal_id)

    Map.merge(empty_map, histories)
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
  def latest_goal_progress_by_goal([]), do: %{}

  def latest_goal_progress_by_goal(goals) when is_list(goals) do
    goal_ids = Enum.map(goals, & &1.id)
    empty_map = Map.new(goal_ids, &{&1, nil})

    latest_ids_query =
      from p in GoalProgress,
        where: p.goal_id in ^goal_ids,
        group_by: p.goal_id,
        select: max(p.id)

    latest =
      GoalProgress
      |> where([p], p.id in subquery(latest_ids_query))
      |> order_by([p], asc: p.goal_id, asc: p.id)
      |> preload([:recorded_by])
      |> Repo.all()
      |> Map.new(&{&1.goal_id, &1})

    Map.merge(empty_map, latest)
  end

  defp parse_goal_progress_goal_id(attrs) do
    attrs
    |> goal_progress_attr(:goal_id)
    |> parse_id()
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp goal_belongs_to_support_plan?(goal_id, support_plan_id) do
    Goal
    |> where([g], g.id == ^goal_id and g.support_plan_id == ^support_plan_id)
    |> Repo.exists?()
  end

  defp scoped_goal_progress_changeset(attrs, goal_id) do
    changeset =
      %GoalProgress{}
      |> GoalProgress.changeset(normalize_goal_progress_attrs(attrs, goal_id))
      |> Ecto.Changeset.add_error(:goal_id, "does not belong to support plan")

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:error, changeset} -> changeset
    end
  end

  defp normalize_goal_progress_attrs(attrs, goal_id) do
    %{
      goal_id: goal_id,
      stage: goal_progress_attr(attrs, :stage),
      note: goal_progress_attr(attrs, :note),
      recorded_by_id: goal_progress_attr(attrs, :recorded_by_id),
      recorded_at: goal_progress_attr(attrs, :recorded_at)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp goal_progress_attr(attrs, key) do
    Map.get(attrs, Atom.to_string(key)) || Map.get(attrs, key)
  end

  defp insert_goal_progress(changeset) do
    Repo.insert(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      if unnamed_foreign_key_constraint_error?(exception) do
        changeset = add_goal_progress_foreign_key_errors(changeset)

        if changeset.valid?, do: reraise(exception, __STACKTRACE__), else: {:error, changeset}
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp add_goal_progress_foreign_key_errors(changeset) do
    changeset
    |> add_missing_assoc_error(:goal_id, Goal)
    |> add_missing_assoc_error(:recorded_by_id, User)
  end

  defp add_missing_assoc_error(%Ecto.Changeset{valid?: true} = changeset, field, schema) do
    id = Ecto.Changeset.get_field(changeset, field)

    if is_integer(id) and assoc_exists?(schema, id) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, field, "does not exist",
        constraint: :foreign,
        constraint_name: nil
      )
    end
  end

  defp add_missing_assoc_error(changeset, _field, _schema), do: changeset

  defp assoc_exists?(schema, id) do
    schema
    |> where([record], record.id == ^id)
    |> Repo.exists?()
  end

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
end
