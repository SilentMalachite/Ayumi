defmodule Ayumi.Plans.SupportPlan do
  @moduledoc "A support plan (個別支援計画) for one planning period of a service user."
  use Ecto.Schema
  import Ecto.Changeset

  @required [
    :service_user_id,
    :staff_id,
    :period_start,
    :period_end,
    :long_term_goal,
    :next_monitoring_date
  ]

  schema "support_plans" do
    field :period_start, :date
    field :period_end, :date
    field :long_term_goal, :string
    field :next_monitoring_date, :date

    field :lock_version, :integer, default: 0

    belongs_to :service_user, Ayumi.Plans.ServiceUser
    belongs_to :staff, Ayumi.Accounts.User
    has_many :goals, Ayumi.Plans.Goal
    has_many :plan_phase_events, Ayumi.Plans.PlanPhaseEvent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(support_plan, attrs) do
    support_plan
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_period()
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:staff_id)
  end

  defp validate_period(changeset) do
    start_d = get_field(changeset, :period_start)
    end_d = get_field(changeset, :period_end)

    if start_d && end_d && Date.compare(end_d, start_d) == :lt do
      add_error(changeset, :period_end, "は計画開始日より前にできません")
    else
      changeset
    end
  end
end
