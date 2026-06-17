defmodule Ayumi.Plans.GoalProgress do
  @moduledoc "An append-only progress update for a short-term goal."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.GoalProgressStage

  @required [:goal_id, :stage, :recorded_by_id, :recorded_at]
  @optional [:note]

  schema "goal_progresses" do
    field :stage, Ecto.Enum, values: GoalProgressStage.all()
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :goal, Ayumi.Plans.Goal
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(goal_progress, attrs) do
    goal_progress
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:stage, GoalProgressStage.all())
    |> foreign_key_constraint(:goal_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
