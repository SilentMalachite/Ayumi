defmodule Ayumi.Plans.PlanPhaseEvent do
  @moduledoc "An append-only lifecycle stage event for a support plan."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.PlanPhaseStage

  @required [:support_plan_id, :stage, :recorded_by_id, :recorded_at]
  @optional [:note]

  schema "plan_phase_events" do
    field :stage, Ecto.Enum, values: PlanPhaseStage.all()
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :support_plan, Ayumi.Plans.SupportPlan
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(plan_phase_event, attrs) do
    plan_phase_event
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:stage, PlanPhaseStage.all())
    |> foreign_key_constraint(:support_plan_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
