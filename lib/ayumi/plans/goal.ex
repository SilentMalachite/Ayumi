defmodule Ayumi.Plans.Goal do
  @moduledoc "A short-term goal (短期目標) belonging to a support plan."
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

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
    |> validate_support_plan_exists()
    |> foreign_key_constraint(:support_plan_id, name: :goals_support_plan_id_fkey)
  end

  # SQLite does not return constraint names on FK violations, so we validate
  # existence eagerly. This keeps the changeset error consistent across adapters.
  defp validate_support_plan_exists(changeset) do
    validate_change(changeset, :support_plan_id, fn :support_plan_id, id ->
      exists =
        Ayumi.Repo.exists?(from p in Ayumi.Plans.SupportPlan, where: p.id == ^id)

      if exists, do: [], else: [support_plan_id: "does not exist"]
    end)
  end
end
