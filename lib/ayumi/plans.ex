defmodule Ayumi.Plans do
  @moduledoc """
  The Plans context: service users, support plans, goals, and (later) the
  append-only progress and phase-event logs. Current state is derived, never stored.
  """
  import Ecto.Query, warn: false
  alias Ayumi.Repo

  alias Ayumi.Plans.ServiceUser
  alias Ayumi.Plans.SupportPlan
  alias Ayumi.Plans.Goal

  ## Service users

  @doc "Lists service users, ordered by kana then name."
  def list_service_users do
    ServiceUser
    |> order_by([s], asc: s.name_kana, asc: s.name)
    |> Repo.all()
  end

  @doc "Gets a single service user. Raises if not found."
  def get_service_user!(id), do: Repo.get!(ServiceUser, id)

  @doc "Creates a service user."
  def create_service_user(attrs) do
    %ServiceUser{}
    |> ServiceUser.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a changeset for tracking service user changes (forms)."
  def change_service_user(%ServiceUser{} = service_user, attrs \\ %{}) do
    ServiceUser.changeset(service_user, attrs)
  end

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
    |> Repo.insert()
  end

  @doc "Returns a changeset for a goal (forms)."
  def change_goal(%Goal{} = goal, attrs \\ %{}) do
    Goal.changeset(goal, attrs)
  end
end
