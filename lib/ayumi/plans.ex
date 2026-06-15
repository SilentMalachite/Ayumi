defmodule Ayumi.Plans do
  @moduledoc """
  The Plans context: service users, support plans, goals, and (later) the
  append-only progress and phase-event logs. Current state is derived, never stored.
  """
  import Ecto.Query, warn: false
  alias Ayumi.Repo

  alias Ayumi.Plans.Goal
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
