defmodule Ayumi.Plans do
  @moduledoc """
  The Plans context: service users, support plans, goals, and (later) the
  append-only progress and phase-event logs. Current state is derived, never stored.
  """
  import Ecto.Query, warn: false
  alias Ayumi.Repo

  alias Ayumi.Accounts.Scope
  alias Ayumi.Accounts.User
  alias Ayumi.Plans.Goal
  alias Ayumi.Plans.GoalProgress
  alias Ayumi.Plans.PlanPhaseEvent
  alias Ayumi.Plans.ServiceUser
  alias Ayumi.Plans.SupportPlan
  alias Ayumi.Plans.SupportRecord

  ## Service users

  @doc "Lists service users, ordered by kana then name. Excludes withdrawn by default."
  def list_service_users(opts \\ []) do
    include_withdrawn = Keyword.get(opts, :include_withdrawn, false)

    ServiceUser
    |> then(fn q ->
      if include_withdrawn, do: q, else: where(q, [su], su.enrollment_status != :withdrawn)
    end)
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
    |> validate_active_service_user("退所者には支援計画を作成できません")
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

  ## Plan phase events

  @doc "Returns a changeset for a plan phase event row (forms)."
  def change_plan_phase_event(%PlanPhaseEvent{} = event, attrs \\ %{}) do
    PlanPhaseEvent.changeset(event, attrs)
  end

  @doc "Appends a plan phase event row. Existing rows are never updated."
  def record_plan_phase_event(attrs) do
    %PlanPhaseEvent{}
    |> PlanPhaseEvent.changeset(attrs)
    |> insert_plan_phase_event()
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
  def list_monitoring_deadline_alerts(
        %Scope{user: user},
        today \\ Date.utc_today(),
        near_days \\ 30
      ) do
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
    |> join(:inner, [p], su in assoc(p, :service_user))
    |> where([_p, su], su.enrollment_status != :withdrawn)
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

  ## Support records

  @doc "Returns a changeset for a support record (forms)."
  def change_support_record(%SupportRecord{} = support_record, attrs \\ %{}) do
    SupportRecord.changeset(support_record, attrs)
  end

  @doc "Creates a support record. `recorded_by_id` and `recorded_at` are set from scope / clock."
  def create_support_record(%Scope{} = scope, attrs) when is_map(attrs) do
    %SupportRecord{}
    |> SupportRecord.changeset(attrs)
    |> SupportRecord.put_audit(scope.user.id, DateTime.utc_now(:second))
    |> validate_active_service_user("退所者には支援記録を作成できません")
    |> insert_support_record()
  end

  @doc "Lists support records, newest first. Filters: service_user_id, from, to."
  def list_support_records(%Scope{}, opts \\ []) do
    service_user_id = Keyword.get(opts, :service_user_id)
    from_date = Keyword.get(opts, :from)
    to_date = Keyword.get(opts, :to)

    SupportRecord
    |> join(:inner, [r], su in assoc(r, :service_user))
    |> where([_r, su], su.enrollment_status != :withdrawn)
    |> order_by([r], desc: r.recorded_at, desc: r.id)
    |> preload([:service_user, :recorded_by])
    |> then(fn q ->
      if service_user_id,
        do: where(q, [r], r.service_user_id == ^service_user_id),
        else: q
    end)
    |> then(fn q ->
      if from_date do
        from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
        where(q, [r], r.recorded_at >= ^from_dt)
      else
        q
      end
    end)
    |> then(fn q ->
      if to_date do
        to_dt = DateTime.new!(Date.add(to_date, 1), ~T[00:00:00], "Etc/UTC")
        where(q, [r], r.recorded_at < ^to_dt)
      else
        q
      end
    end)
    |> Repo.all()
  end

  defp insert_support_record(changeset) do
    Repo.insert(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      if unnamed_foreign_key_constraint_error?(exception) do
        changeset = add_support_record_foreign_key_errors(changeset)

        if changeset.valid?, do: reraise(exception, __STACKTRACE__), else: {:error, changeset}
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp validate_active_service_user(%Ecto.Changeset{valid?: false} = changeset, _message),
    do: changeset

  defp validate_active_service_user(changeset, message) do
    case Ecto.Changeset.get_field(changeset, :service_user_id) do
      nil ->
        changeset

      id ->
        if withdrawn_service_user?(id) do
          Ecto.Changeset.add_error(changeset, :service_user_id, message)
        else
          changeset
        end
    end
  end

  defp withdrawn_service_user?(id) do
    ServiceUser
    |> where([su], su.id == ^id and su.enrollment_status == :withdrawn)
    |> Repo.exists?()
  end

  defp add_support_record_foreign_key_errors(changeset) do
    changeset
    |> add_missing_assoc_error(:service_user_id, ServiceUser)
    |> add_missing_assoc_error(:recorded_by_id, User)
  end

  ## Certificate expiry

  @doc """
  Returns certificate-expiry alerts for service users whose `recipient_cert_expiry`
  is overdue or within `near_days`.
  """
  def list_certificate_expiry_alerts(
        _scope,
        today \\ Date.utc_today(),
        near_days \\ 60
      ) do
    ServiceUser
    |> where([su], not is_nil(su.recipient_cert_expiry))
    |> where([su], su.enrollment_status != :withdrawn)
    |> Repo.all()
    |> Enum.map(fn su ->
      days_until = Date.diff(su.recipient_cert_expiry, today)

      %{
        service_user: su,
        status: monitoring_deadline_status(su.recipient_cert_expiry, today, near_days),
        days_until: days_until
      }
    end)
    |> Enum.reject(&(&1.status == :ok))
    |> Enum.sort_by(fn alert ->
      su = alert.service_user
      {alert.days_until, su.name_kana || "", su.name || "", su.id}
    end)
  end

  def list_recent_support_records(service_user_id, limit \\ 20) do
    SupportRecord
    |> where([r], r.service_user_id == ^service_user_id)
    |> order_by([r], desc: r.recorded_at, desc: r.id)
    |> limit(^limit)
    |> preload([:service_user, :recorded_by])
    |> Repo.all()
  end

  def list_recent_goal_progress_for_user(service_user_id, limit \\ 20) do
    GoalProgress
    |> join(:inner, [gp], g in Goal, on: gp.goal_id == g.id)
    |> join(:inner, [gp, g], sp in SupportPlan, on: g.support_plan_id == sp.id)
    |> where([gp, g, sp], sp.service_user_id == ^service_user_id)
    |> order_by([gp], desc: gp.id)
    |> limit(^limit)
    |> preload([:recorded_by, goal: :support_plan])
    |> Repo.all()
  end

  def list_recent_plan_phase_events_for_user(service_user_id, limit \\ 20) do
    PlanPhaseEvent
    |> join(:inner, [e], sp in SupportPlan, on: e.support_plan_id == sp.id)
    |> where([e, sp], sp.service_user_id == ^service_user_id)
    |> order_by([e], desc: e.id)
    |> limit(^limit)
    |> preload([:recorded_by, :support_plan])
    |> Repo.all()
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

  defp insert_plan_phase_event(changeset) do
    Repo.insert(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      if unnamed_foreign_key_constraint_error?(exception) do
        changeset = add_plan_phase_event_foreign_key_errors(changeset)

        if changeset.valid?, do: reraise(exception, __STACKTRACE__), else: {:error, changeset}
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp add_plan_phase_event_foreign_key_errors(changeset) do
    changeset
    |> add_missing_assoc_error(:support_plan_id, SupportPlan)
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
