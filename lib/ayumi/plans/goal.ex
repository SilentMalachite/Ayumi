defmodule Ayumi.Plans.Goal do
  @moduledoc "A short-term goal (短期目標) belonging to a support plan."
  use Ecto.Schema
  import Ecto.Changeset

  schema "goals" do
    field :description, :string

    belongs_to :support_plan, Ayumi.Plans.SupportPlan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:support_plan_id, :description])
    |> validate_required([:support_plan_id, :description])
    |> foreign_key_constraint(:support_plan_id)
  end
end
